#!/bin/bash

# Script di test per l'adattamento sessione Ardour
# Questo script testa le funzioni di rilevamento porte e modifica sessione

set -euo pipefail

# Configurazione test
TEST_SESSION_PATH="/tmp/test-ardour-session.ardour"
TEST_BACKUP_PATH="${TEST_SESSION_PATH}.backup"
TEST_TEMP_PATH="${TEST_SESSION_PATH}.temp"
JACK_SERVER_NAME="test_jack"

# Mock delle funzioni per test
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRORE: $1" >&2; }

# Mock di jack_lsp per test
mock_jack_lsp() {
    case "$1" in
        "capture")
            echo "system:capture_3"
            echo "system:capture_4"
            ;;
        "playback")
            echo "system:playback_5"
            echo "system:playback_6"
            echo "system:playback_7"
            echo "system:playback_8"
            ;;
    esac
}

# Funzione di rilevamento porte (versione test)
detect_jack_ports_test() {
    log "🔍 Rilevamento porte JACK disponibili per il server '$JACK_SERVER_NAME'..."
    
    # Simula porte JACK disponibili
    local available_ports
    available_ports=$(mock_jack_lsp "capture"; mock_jack_lsp "playback")
    
    log "Porte JACK disponibili simulate:"
    echo "$available_ports" | while read -r port; do
        log "  - $port"
    done
    
    # Salva le porte disponibili in variabili globali
    export JACK_CAPTURE_PORTS=$(echo "$available_ports" | grep "capture" | head -10)
    export JACK_PLAYBACK_PORTS=$(echo "$available_ports" | grep "playback" | head -10)
    
    # Conta le porte disponibili
    export CAPTURE_COUNT=$(echo "$JACK_CAPTURE_PORTS" | wc -l)
    export PLAYBACK_COUNT=$(echo "$JACK_PLAYBACK_PORTS" | wc -l)
    
    log "Porte disponibili: $CAPTURE_COUNT capture, $PLAYBACK_COUNT playback"
    
    return 0
}

# Funzione di backup (versione test)
backup_session_test() {
    log "📁 Creazione backup sessione Ardour..."
    
    if [ -f "$TEST_SESSION_PATH" ]; then
        cp "$TEST_SESSION_PATH" "$TEST_BACKUP_PATH"
        if [ $? -eq 0 ]; then
            log "✅ Backup sessione creato: $TEST_BACKUP_PATH"
            return 0
        else
            error "Impossibile creare il backup della sessione"
            return 1
        fi
    else
        error "File sessione non trovato: $TEST_SESSION_PATH"
        return 1
    fi
}

# Funzione di validazione porte (versione test)
validate_port_mapping_test() {
    log "✅ Validazione mappatura porte..."
    
    # Controlla che ci siano abbastanza porte per la sessione
    local required_capture=1  # Audio 1 richiede 1 porta capture
    local required_playback=2 # Master e Click richiedono 2 porte playback
    
    if [ "$CAPTURE_COUNT" -lt "$required_capture" ]; then
        error "Porte capture insufficienti: necessarie $required_capture, disponibili $CAPTURE_COUNT"
        return 1
    fi
    
    if [ "$PLAYBACK_COUNT" -lt "$required_playback" ]; then
        error "Porte playback insufficienti: necessarie $required_playback, disponibili $PLAYBACK_COUNT"
        return 1
    fi
    
    log "✅ Validazione superata: porte sufficienti per la sessione"
    return 0
}

# Funzione di adattamento sessione (versione test)
adapt_session_to_ports_test() {
    log "🔧 Adattamento sessione Ardour alle porte disponibili..."
    
    if ! validate_port_mapping_test; then
        return 1
    fi
    
    # Estrai la prima porta capture disponibile
    local capture_port=$(echo "$JACK_CAPTURE_PORTS" | head -1)
    # Estrai le prime 2 porte playback disponibili
    local playback_port_1=$(echo "$JACK_PLAYBACK_PORTS" | head -1)
    local playback_port_2=$(echo "$JACK_PLAYBACK_PORTS" | sed -n '2p')
    
    log "Mappatura porte:"
    log "  Capture: system:capture_1 → $capture_port"
    log "  Playback 1: system:playback_1 → $playback_port_1"
    log "  Playback 2: system:playback_2 → $playback_port_2"
    
    # Crea il file temporaneo con le sostituzioni
    cp "$TEST_SESSION_PATH" "$TEST_TEMP_PATH"
    
    # Sostituzione delle connessioni JACK nel file XML
    # Usiamo sed per sostituire i pattern specifici
    sed -i "s/other=\"system:capture_1\"/other=\"$capture_port\"/g" "$TEST_TEMP_PATH"
    sed -i "s/other=\"system:playback_1\"/other=\"$playback_port_1\"/g" "$TEST_TEMP_PATH"
    sed -i "s/other=\"system:playback_2\"/other=\"$playback_port_2\"/g" "$TEST_TEMP_PATH"
    
    # Verifica che le sostituzioni siano avvenute correttamente
    local capture_subs=$(grep -c "$capture_port" "$TEST_TEMP_PATH")
    local playback1_subs=$(grep -c "$playback_port_1" "$TEST_TEMP_PATH")
    local playback2_subs=$(grep -c "$playback_port_2" "$TEST_TEMP_PATH")
    
    log "Sostituzioni effettuate:"
    log "  Capture: $capture_subs occorrenze"
    log "  Playback 1: $playback1_subs occorrenze"
    log "  Playback 2: $playback2_subs occorrenze"
    
    if [ "$capture_subs" -gt 0 ] && [ "$playback1_subs" -gt 0 ] && [ "$playback2_subs" -gt 0 ]; then
        log "✅ Sessione adattata correttamente alle porte disponibili"
        return 0
    else
        error "Sostituzione porte fallita o incompleta"
        return 1
    fi
}

# Funzione per creare un file di sessione di test
create_test_session() {
    log "📝 Creazione file sessione di test..."
    
    cat > "$TEST_SESSION_PATH" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Session version="7003" name="SESSIONE DI TEST" sample-rate="48000">
  <Routes>
    <Route name="Audio 1" default-type="audio">
      <IO name="Audio 1" direction="Input" default-type="audio">
        <Port name="Audio 1/audio_in 1" type="audio" direction="Input">
          <ExtConnection for="JACK" other="system:capture_1"/>
        </Port>
      </IO>
      <IO name="Audio 1" direction="Output" default-type="audio">
        <Port name="Audio 1/audio_out 1" type="audio" direction="Output">
          <ExtConnection for="JACK" other="system:playback_1"/>
        </Port>
        <Port name="Audio 1/audio_out 2" type="audio" direction="Output">
          <ExtConnection for="JACK" other="system:playback_2"/>
        </Port>
      </IO>
    </Route>
    <Route name="Master" default-type="audio">
      <IO name="Master" direction="Output" default-type="audio">
        <Port name="Master/audio_out 1" type="audio" direction="Output">
          <ExtConnection for="JACK" other="system:playback_1"/>
        </Port>
        <Port name="Master/audio_out 2" type="audio" direction="Output">
          <ExtConnection for="JACK" other="system:playback_2"/>
        </Port>
      </IO>
    </Route>
    <Route name="Click" default-type="audio">
      <IO name="Click" direction="Output" default-type="audio">
        <Port name="Click/audio_out 1" type="audio" direction="Output">
          <ExtConnection for="JACK" other="system:playback_1"/>
        </Port>
        <Port name="Click/audio_out 2" type="audio" direction="Output">
          <ExtConnection for="JACK" other="system:playback_2"/>
        </Port>
      </IO>
    </Route>
  </Routes>
</Session>
EOF
    
    if [ $? -eq 0 ]; then
        log "✅ File sessione di test creato: $TEST_SESSION_PATH"
        return 0
    else
        error "Impossibile creare il file sessione di test"
        return 1
    fi
}

# Funzione per mostrare il contenuto del file
show_file_content() {
    local file_path="$1"
    local description="$2"
    
    log "📄 Contenuto $description:"
    echo "----------------------------------------"
    grep -E "(other=\"system:)" "$file_path" | head -10
    echo "----------------------------------------"
}

# Funzione principale di test
run_tests() {
    log "🧪 INIZIO TEST ADATTAMENTO SESSIONE ARDOUR"
    
    # 1. Crea file di sessione di test
    if ! create_test_session; then
        error "Impossibile creare il file di sessione di test"
        return 1
    fi
    
    # Mostra contenuto originale
    show_file_content "$TEST_SESSION_PATH" "originale"
    
    # 2. Rileva porte JACK (simulate)
    if ! detect_jack_ports_test; then
        error "Impossibile rilevare le porte JACK simulate"
        return 1
    fi
    
    # 3. Crea backup della sessione
    if ! backup_session_test; then
        error "Impossibile creare il backup della sessione"
        return 1
    fi
    
    # 4. Adatta la sessione alle porte disponibili
    if ! adapt_session_to_ports_test; then
        error "Impossibile adattare la sessione alle porte disponibili"
        return 1
    fi
    
    # Mostra contenuto modificato
    show_file_content "$TEST_TEMP_PATH" "modificato"
    
    # 5. Verifica che le sostituzioni siano corrette
    log "🔍 Verifica sostituzioni..."
    
    local capture_port=$(echo "$JACK_CAPTURE_PORTS" | head -1)
    local playback_port_1=$(echo "$JACK_PLAYBACK_PORTS" | head -1)
    local playback_port_2=$(echo "$JACK_PLAYBACK_PORTS" | sed -n '2p')
    
    # Controlla che le sostituzioni siano avvenute
    if grep -q "other=\"$capture_port\"" "$TEST_TEMP_PATH" && \
       grep -q "other=\"$playback_port_1\"" "$TEST_TEMP_PATH" && \
       grep -q "other=\"$playback_port_2\"" "$TEST_TEMP_PATH"; then
        log "✅ Verifica sostituzioni: TUTTO CORRETTO"
        log "✅ Le porte sono state sostituite correttamente"
    else
        error "Verifica sostituzioni: FALLITA"
        return 1
    fi
    
    # 6. Verifica che non ci siano più riferimenti alle porte vecchie
    if ! grep -q "other=\"system:capture_1\"" "$TEST_TEMP_PATH" && \
       ! grep -q "other=\"system:playback_1\"" "$TEST_TEMP_PATH" && \
       ! grep -q "other=\"system:playback_2\"" "$TEST_TEMP_PATH"; then
        log "✅ Verifica pulizia: Nessun riferimento alle porte vecchie"
    else
        error "Verifica pulizia: Sono ancora presenti riferimenti alle porte vecchie"
        return 1
    fi
    
    log "✅ TEST COMPLETATO CON SUCCESSO"
    log "✅ L'adattamento sessione funziona correttamente"
    
    return 0
}

# Pulizia file di test
cleanup() {
    log "🧹 Pulizia file di test..."
    rm -f "$TEST_SESSION_PATH" "$TEST_BACKUP_PATH" "$TEST_TEMP_PATH"
    log "✅ File di test rimossi"
}

# Esecuzione principale
main() {
    log "🚀 AVVIO TEST ADATTAMENTO SESSIONE ARDOUR"
    
    # Esegui i test
    if run_tests; then
        log "🎉 TUTTI I TEST SONO ANDATI A BUON FINE"
        cleanup
        exit 0
    else
        error "❌ ALCUNI TEST SONO FALLITI"
        cleanup
        exit 1
    fi
}

# Gestione segnali per pulizia
trap cleanup EXIT

# Esegui il test
main "$@"