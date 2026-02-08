#!/bin/bash

# Fase 5: Avvio di Ardour - FIX PARSING prlimit
set -euo pipefail

# Configurazione logging
LOG_FILE="/tmp/olms-ardour-startup.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Variabili universali per architettura CPU dinamica
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))
SYSTEM_CORE="0"
IRQ_CORE="1"
AUDIO_CORES="2-$LAST_CORE"

# Variabili JACK/D-Bus/X11
JACK_SERVER_NAME="olms"
JACK_SESSION_DIR="/dev/shm/jack_olms_0"
JACK_SOCKET_DIR="/dev/shm/jack_olms_0"
DBUS_SOCKET_ABSTRACT="olms_bus_1000"
XAUTHORITY_PATH="/home/francesco_ssh/.Xauthority"
DISPLAY=":0"
CPU_CORES="$AUDIO_CORES"
RT_PRIORITY=70

# Variabili di configurazione
ARD_SESSION_PATH="/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"
ARD_SESSION_DIR="/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC"
ARD_USER="francesco_ssh"
ARD_UID=1000

# Variabili per l'adattamento sessione
JACK_SERVER_NAME="olms"
SESSION_BACKUP_PATH="${ARD_SESSION_PATH}.backup"
SESSION_TEMP_PATH="${ARD_SESSION_PATH}.temp"

# Funzioni di logging (per coerenza con altri script)
log() { echo -e "\e[32m[$(date '+%Y-%m-%d %H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%Y-%m-%d %H:%M:%S')] WARN:\e[0m $1"; }
error() { echo -e "\e[31m[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:\e[0m $1"; }

# Funzioni di adattamento sessione Ardour
detect_jack_ports() {
    log "🔍 Rilevamento porte JACK disponibili per il server '$JACK_SERVER_NAME'..."
    
    # Configurazione ambiente completa (come nel latency test)
    local base_env="PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1"
    
    # Rileva le porte JACK disponibili con ambiente completo
    local available_ports
    available_ports=$(sudo -u "$ARD_USER" env $base_env jack_lsp 2>/dev/null | grep "^system:" | sort)
    
    if [ -z "$available_ports" ]; then
        warn "⚠️ Nessuna porta JACK trovata per il server '$JACK_SERVER_NAME'"
        warn "💡 JACK è stabile ma jack_lsp non riesce a vedere le porte (problema comune con schede economiche)"
        warn "⚠️ Continuo con la sessione originale - potrebbero esserci problemi di connessione"
        return 1
    fi
    
    log "✅ Porte JACK disponibili trovate:"
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

backup_session() {
    log "📁 Creazione backup sessione Ardour..."
    
    if [ -f "$ARD_SESSION_PATH" ]; then
        sudo -u francesco_ssh cp "$ARD_SESSION_PATH" "$SESSION_BACKUP_PATH"
        if [ $? -eq 0 ]; then
            log "✅ Backup sessione creato: $SESSION_BACKUP_PATH"
            return 0
        else
            error "Impossibile creare il backup della sessione"
            return 1
        fi
    else
        error "File sessione non trovato: $ARD_SESSION_PATH"
        return 1
    fi
}

validate_port_mapping() {
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

adapt_session_to_ports() {
    log "🔧 Adattamento sessione Ardour alle porte disponibili..."
    
    if ! validate_port_mapping; then
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
    
    # Crea il file temporaneo con le sostituzioni come utente francesco_ssh
    sudo -u francesco_ssh cp "$ARD_SESSION_PATH" "$SESSION_TEMP_PATH"
    
    # Sostituzione delle connessioni JACK nel file XML come utente francesco_ssh
    # Usiamo sed per sostituire i pattern specifici
    sudo -u francesco_ssh sed -i "s/other=\"system:capture_1\"/other=\"$capture_port\"/g" "$SESSION_TEMP_PATH"
    sudo -u francesco_ssh sed -i "s/other=\"system:playback_1\"/other=\"$playback_port_1\"/g" "$SESSION_TEMP_PATH"
    sudo -u francesco_ssh sed -i "s/other=\"system:playback_2\"/other=\"$playback_port_2\"/g" "$SESSION_TEMP_PATH"
    
    # Verifica che le sostituzioni siano avvenute correttamente
    local capture_subs=$(grep -c "$capture_port" "$SESSION_TEMP_PATH")
    local playback1_subs=$(grep -c "$playback_port_1" "$SESSION_TEMP_PATH")
    local playback2_subs=$(grep -c "$playback_port_2" "$SESSION_TEMP_PATH")
    
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

reload_ardour_session() {
    log "🔄 Ricaricamento sessione Ardour..."
    
    # Trova il PID di Ardour
    local ardour_pid
    ardour_pid=$(pgrep -f "ardour8.*--no-splash")
    
    if [ -z "$ardour_pid" ]; then
        error "Impossibile trovare il processo Ardour"
        return 1
    fi
    
    log "Ardour in esecuzione (PID: $ardour_pid)"
    
    # Invia segnale di ricarica alla sessione
    # Ardour non supporta il reload diretto via segnale, quindi dobbiamo riavviarlo
    log "Riavvio Ardour con sessione aggiornata..."
    
    # Termina Ardour in modo pulito
    kill -TERM "$ardour_pid" 2>/dev/null || true
    sleep 2
    
    # Verifica che Ardour sia terminato
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        log "Ardour non si è chiuso correttamente, forzatura terminazione..."
        kill -KILL "$ardour_pid" 2>/dev/null || true
        sleep 1
    fi
    
    # Sposta il file temporaneo al posto di quello originale come utente francesco_ssh
    sudo -u francesco_ssh mv "$SESSION_TEMP_PATH" "$ARD_SESSION_PATH"
    
    # Riavvia Ardour con la sessione aggiornata
    log "Riavvio Ardour con sessione adattata..."
    
    sudo -u "$ARD_USER" env \
        HOME=/home/francesco_ssh \
        DISPLAY=:0 \
        XAUTHORITY=/home/francesco_ssh/.Xauthority \
        XDG_RUNTIME_DIR=/run/user/1000 \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH" &
    
    # Aspetta che Ardour si riavvii
    sleep 3
    
    # Verifica che Ardour sia di nuovo in esecuzione
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        local new_ardour_pid=$(pgrep -f "ardour8.*--no-splash")
        log "✅ Ardour riavviato con sessione adattata (PID: $new_ardour_pid)"
        return 0
    else
        error "Riavvio Ardour fallito"
        return 1
    fi
}

# Controllo modalità headless
if [[ "${OLMS_MODE:-}" == "headless" ]]; then
    log "FASE 5: Modalità headless - Configurazione Xvfb e Ardour"

    # 1. Pulizia e avvio Xvfb sul display :99
    # Rimuoviamo eventuali lock residui se il server è crashato in precedenza
    sudo rm -f /tmp/.X99-lock
    
    log "Avvio server grafico virtuale (Xvfb) su :99..."
    sudo -u "$ARD_USER" Xvfb :99 -screen 0 1024x768x16 > /dev/null 2>&1 &
    XVFB_PID=$!
    
    # Aspetta che Xvfb sia pronto
    sleep 1

    # 2. Avvio Ardour puntando al display virtuale
    log "Avvio Ardour su DISPLAY=:99 (Headless)"
    
    exec sudo -u "$ARD_USER" env \
        HOME=/home/francesco_ssh \
        DISPLAY=:99 \
        XAUTHORITY=/home/francesco_ssh/.Xauthority \
        XDG_RUNTIME_DIR=/run/user/1000 \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH" &
    
    # Aspetta un momento per l'inizializzazione
    sleep 3
    
    # 3. Verifica processi
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        ardour_pid=$(pgrep -f "ardour8.*--no-splash")
        log "✅ Ardour (Headless) e Xvfb avviati (Ardour PID: $ardour_pid, Xvfb PID: $XVFB_PID)"
    else
        error "ERRORE: Ardour headless non è partito. Controlla i log."
        kill $XVFB_PID 2>/dev/null
        exit 1
    fi
    exit 0
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRORE: $1" >&2; }

check_user_permissions() {
    log "Verifica permessi utente $ARD_USER..."
    
    # Estraiamo il valore SOFT (terzultimo) e HARD (penultimo) per essere sicuri
    local rtprio_limit=$(sudo -u "$ARD_USER" prlimit --rtprio --pid=$$ --noheadings --output=SOFT)
    local memlock_limit=$(sudo -u "$ARD_USER" prlimit --memlock --pid=$$ --noheadings --output=SOFT)

    log "Rilevato rtprio_limit: $rtprio_limit"
    log "Rilevato memlock_limit: $memlock_limit"

    if [[ "$rtprio_limit" != "unlimited" ]] && [ "$rtprio_limit" -lt 90 ]; then
        log "ERRORE: rtprio troppo basso ($rtprio_limit)"
        return 1
    fi
    return 0
}

start_ardour_with_fallback() {
    log "=== AVVIO ARDOUR ==="
    
    # Ambiente pulito per l'esecuzione come utente target
    local base_env="DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY_PATH XDG_RUNTIME_DIR=/run/user/$ARD_UID DBUS_SESSION_BUS_ADDRESS=unix:abstract=$DBUS_SOCKET_ABSTRACT JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_SESSION_DIR=$JACK_SESSION_DIR JACK_NO_START_SERVER=1 JACK_PROMISCUOUS_SERVER=1"

    log "Esecuzione comando finale..."
    log "Transizione utente: sudo -u $ARD_USER (UID: $ARD_UID)"
    log "Ambiente impostato: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY_PATH"
    log "Comando: taskset -c $CPU_CORES chrt -f $RT_PRIORITY /usr/bin/ardour8 -Z olms -n $ARD_SESSION_PATH"
    
    # Aggiungi esplicitamente il flag -Z (o --jack-server) ad Ardour
    sudo -u "$ARD_USER" -E env $base_env taskset -c "$CPU_CORES" chrt -f "$RT_PRIORITY" /usr/bin/ardour8 -Z olms -n "$ARD_SESSION_PATH"
}

main() {
    log "=== FASE 5: STARTUP ARDOUR (Bypass Mode) ==="
    
    # 1. Verifica fisica del socket (più affidabile di jack_lsp in questo setup)
    if [ -S "/dev/shm/jack_olms_0" ]; then
        log "✅ Socket JACK rilevato correttamente in /dev/shm/jack_olms_0"
    else
        error "ERRORE: Socket JACK 'olms' non trovato. Il server è avviato?"
        exit 1
    fi

    # 2. Verifica del processo
    if pgrep -f "jackd.*-n olms" > /dev/null; then
        log "✅ Processo JACK 'olms' verificato."
    else
        error "ERRORE: Processo jackd non trovato."
        exit 1
    fi

    # 3. Controllo preventivo: verifica che JACK sia stabile prima di lanciare Ardour
    log "🔍 Controllo preventivo: verifica stabilità JACK prima di lanciare Ardour..."
    
    # Leggi il PID di JACK dal file
    local jack_pid_file="/tmp/jack.pid"
    local jack_pid=""
    if [ -f "$jack_pid_file" ]; then
        jack_pid=$(cat "$jack_pid_file" 2>/dev/null)
    fi
    
    if [ -z "$jack_pid" ]; then
        log "⚠️ Nessun PID JACK trovato in $jack_pid_file, procedo con verifica generica..."
    else
        log "Verifica PID JACK: $jack_pid"
        if ps -p "$jack_pid" > /dev/null 2>&1; then
            log "✅ JACK stabile (PID: $jack_pid)"
        else
            log "🚨 JACK non stabile - PID $jack_pid non attivo"
            log "🚨 Attivazione procedura di emergenza..."
            
            # Procedura di emergenza: riavvia Phase 3 con parametri conservativi
            log "🔄 Riavvio Phase 3 con parametri conservativi (256:3)..."
            
            # Kill any existing JACK processes
            pkill -9 jackd 2>/dev/null || true
            sleep 2
            
            # Clean up JACK socket and shm files
            log "🧹 Pulizia socket e shm files..."
            sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
            
            # Launch JACK with conservative parameters (256:3)
            log "🚀 Avvio JACK con parametri conservativi: Buffer=256, Periods=3"
            sudo -u francesco_ssh env -i \
                HOME=/home/francesco_ssh \
                PATH=/usr/bin:/bin \
                XDG_RUNTIME_DIR=/run/user/1000 \
                JACK_NO_AUDIO_RESERVATION=1 \
                JACK_PROMISCUOUS_SERVER=1 \
                taskset -c "$AUDIO_CORES" chrt -f 80 \
                /usr/bin/jackd -R -P 80 -n olms -d alsa -d hw:1 -r 48000 -p 256 -n 3 -S 16 > /tmp/jack_emergency.log 2>&1 &
            local emergency_jack_pid=$!
            
            # Save PID for monitoring
            echo "$emergency_jack_pid" > /tmp/jack.pid
            
            # Wait for JACK to initialize
            sleep 5
            
            # Verify emergency JACK is running
            if ps -p "$emergency_jack_pid" > /dev/null 2>&1; then
                log "✅ JACK riavviato con successo (PID: $emergency_jack_pid)"
                log "✅ Parametri conservativi applicati: Buffer=256, Periods=3"
            else
                error "ERRORE: JACK non è stato riavviato correttamente con parametri conservativi"
                exit 1
            fi
        fi
    fi

    # 4. Adattamento automatico della sessione alle porte JACK disponibili
    log "🔧 INIZIO ADATTAMENTO SESSIONE ARDOUR"
    
    # Rileva le porte JACK disponibili
    if ! detect_jack_ports; then
        error "Impossibile rilevare le porte JACK disponibili"
        log "⚠️ Continuo con la sessione originale (potrebbero esserci problemi di connessione)"
        return 0
    fi
    
    # Crea backup della sessione originale
    if ! backup_session; then
        error "Impossibile creare il backup della sessione"
        log "⚠️ Continuo senza backup (rischio di perdita configurazione)"
    fi
    
    # Adatta la sessione alle porte disponibili
    if ! adapt_session_to_ports; then
        error "Impossibile adattare la sessione alle porte disponibili"
        log "⚠️ Ripristino sessione originale dal backup"
        
        # Ripristina il backup se esiste
        if [ -f "$SESSION_BACKUP_PATH" ]; then
            cp "$SESSION_BACKUP_PATH" "$ARD_SESSION_PATH"
            log "✅ Sessione ripristinata dal backup"
        fi
        
        # Verifica connessioni manualmente
        log "🔍 Verifica connessioni JACK manuali..."
        sudo -u "$ARD_USER" env JACK_DEFAULT_SERVER="$JACK_SERVER_NAME" jack_lsp -c | grep -E "(capture|playback)" || log "Nessuna connessione trovata"
        
        return 1
    fi
    
    # 4. Lancio di Ardour con sessione già adattata
    log "Avvio Ardour con sessione già adattata..."
    
    # Prepariamo l'ambiente esatto per francesco_ssh
    log "Transizione utente: sudo -u $ARD_USER (UID: $ARD_UID)"
    log "Ambiente impostato per utente $ARD_USER:"
    log "  HOME=/home/francesco_ssh"
    log "  DISPLAY=:0"
    log "  XAUTHORITY=/home/francesco_ssh/.Xauthority"
    log "  XDG_RUNTIME_DIR=/run/user/1000"
    log "  JACK_DEFAULT_SERVER=olms"
    log "  JACK_PROMISCUOUS_SERVER=1"
    log "  JACK_NO_START_SERVER=1"
    log "  CPU affinity: taskset -c $CPU_CORES"
    log "  RT priority: chrt -f $RT_PRIORITY"
    log "Comando finale: /usr/bin/ardour8 --no-splash $ARD_SESSION_PATH"
    
    # Avvio Ardour in background per permettere al processo di continuare (usando exec per evitare shell shim)
    exec sudo -u "$ARD_USER" env \
        HOME=/home/francesco_ssh \
        DISPLAY=:0 \
        XAUTHORITY=/home/francesco_ssh/.Xauthority \
        XDG_RUNTIME_DIR=/run/user/1000 \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH" &
    
    # Aspetta un momento per assicurarsi che Ardour sia avviato
    sleep 2
    
    # Verifica che Ardour sia effettivamente in esecuzione
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        local ardour_pid=$(pgrep -f "ardour8.*--no-splash")
        log "✅ Ardour avviato correttamente in background (PID: $ardour_pid)"
    else
        error "ERRORE: Ardour non è stato avviato correttamente"
        exit 1
    fi
    
    log "✅ ADATTAMENTO SESSIONE COMPLETATO CON SUCCESSO"
    log "✅ Ardour è ora configurato per utilizzare le porte della scheda audio corrente"
    
    return 0
}

main "$@"