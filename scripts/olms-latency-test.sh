#!/bin/bash
# OLMS Latency Test Utility - Professional Version
# Target: Precision measurement < 5ms

set -e

# --- CONFIGURAZIONE AMBIENTE (La chiave del successo) ---
export TARGET_USER="francesco_ssh"
# Aggiungiamo il PATH esplicito per evitare "No such file or directory"
export J_ENV="PATH=/usr/bin:/bin JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1"
export J_CMD="sudo -u $TARGET_USER env $J_ENV"

# Parametri Audio
SAMPLE_RATE=48000
BUFFER_SIZE=64
PERIODS=3

# --- COLORI ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# --- LOGICA DI TEST ---

check_system() {
    log_info "Verifica integrità sistema OLMS..."
    if ! pgrep -f "jackd.*olms" > /dev/null; then
        log_err "JACK server 'olms' non trovato. Avvia prima OLMS Core."
        exit 1
    fi
    
    # Controllo se jack_delay è installato
    if ! command -v jack_delay &> /dev/null && ! [ -f /usr/bin/jack_delay ]; then
        log_err "jack_delay non trovato. Installa: sudo pacman -S jack-example-tools"
        exit 1
    fi
    
    log_info "Server JACK rilevato. Accesso come $TARGET_USER validato."
    log_info "jack_delay disponibile per le misurazioni."
}

run_test() {
    local mode=$1 # "software" o "hardware"
    local output_file="/tmp/latency_${mode}_result.txt"
    
    echo -e "\n--- TEST: MISURAZIONE $(echo $mode | tr '[:lower:]' '[:upper:]') ---"
    
    if [ "$mode" == "software" ]; then
        log_info "Configurazione routing per test attraverso Ardour..."
        
        # 1. Troviamo il nome esatto della traccia (usiamo il primo ingresso audio di ardour rilevato)
        local ARDOUR_IN=$( $J_CMD jack_lsp | grep "ardour:.*audio_in" | head -n 1 )
        local ARDOUR_OUT=$( $J_CMD jack_lsp | grep "ardour:.*audio_out" | head -n 1 )

        if [ -z "$ARDOUR_IN" ]; then
            log_err "Non trovo tracce audio attive in Ardour. Assicurati che Ardour sia aperto con una traccia creata."
            return 1
        fi

        log_info "Iniezione segnale in: $ARDOUR_IN"
        
        # 2. Colleghiamo jack_delay (che scrive su playback_1) all'ingresso della traccia
        $J_CMD jack_connect system:playback_1 "$ARDOUR_IN" || true
        
        # 3. Colleghiamo l'uscita della traccia all'ingresso di jack_delay (che legge da capture_1)
        # Nota: per semplicità, colleghiamo il Master di Ardour al capture_1 così misuriamo tutto il percorso
        $J_CMD jack_connect ardour:Master/audio_out_1 system:capture_1 || true
    else
        log_warn "MODALITÀ HARDWARE: Collega il cavo fisico OUT 1 -> IN 1"
        echo "Premi INVIO quando sei pronto..."
        read
    fi

    # Esecuzione jack_delay senza flag -n che causava l'errore
    set +e
    $J_CMD jack_delay -I system:capture_1 -O system:playback_1 > "$output_file" 2>&1 &
    local J_PID=$!
    
    log_info "Campionamento segnale per 5 secondi..."
    sleep 5
    kill $J_PID 2>/dev/null || true
    set -e

    if grep -q "latency" "$output_file"; then
        # Estraiamo l'ultima riga valida che contiene la misurazione
        local result=$(grep "latency" "$output_file" | tail -n 1)
        echo -e "${GREEN}SUCCESSO:${NC} $result"
    else
        log_err "Nessun segnale rilevato."
        log_info "Log errore:\n$(head -n 5 $output_file)"
    fi
    
    if [ "$mode" == "software" ]; then
        # Scollegare le connessioni software create per il test
        $J_CMD jack_disconnect system:playback_1 "$ARDOUR_IN" 2>/dev/null || true
        $J_CMD jack_disconnect ardour:Master/audio_out_1 system:capture_1 2>/dev/null || true
    fi
}

# --- MAIN ---
clear
echo "==============================================="
echo "   OLMS LATENCY ANALYZER - v1.2"
echo "==============================================="

check_system
run_test "software"
run_test "hardware"

echo -e "\n==============================================="
log_info "Analisi completata."
\