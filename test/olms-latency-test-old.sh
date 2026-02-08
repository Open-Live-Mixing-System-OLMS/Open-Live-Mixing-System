#!/bin/bash
# OLMS LATENCY ANALYZER - v1.9 (CLEAN OUTPUT)
# Fix: Logica identica alla v1.8, migliorata solo la leggibilità dei log.
# Feature: Allineamento colonne e calcolo differenziale nel report finale.

set -e

# --- CONFIGURAZIONE ---
export TARGET_USER="francesco_ssh"
export BIN_JACK_DELAY="/usr/bin/jack_delay"
export J_ENV="PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1"
export J_CMD="sudo -u $TARGET_USER env $J_ENV"

# Impostazioni attuali (solo per calcolo teorico)
BUFFER=64
RATE=48000
PERIODS=3

# --- COLORI E STILI ---
GREEN='\033[1;32m' # Bold Green
YELLOW='\033[1;33m' # Bold Yellow
RED='\033[1;31m'   # Bold Red
CYAN='\033[1;36m'  # Bold Cyan
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Funzione di analisi robusta (Output pulito)
analyze_result() {
    local file=$1
    local phase=$2
    
    if grep -q "frames" "$file"; then
        # Prende l'ultima riga valida
        local last_line=$(grep "frames" "$file" | tail -n 1)
        
        # PULIZIA OUTPUT: Rimuove spazi iniziali e tabulazioni per allineamento
        # Esempio Raw: "  384.597 frames     8.012 ms" -> Clean: "384.597 frames | 8.012 ms"
        local clean_val=$(echo "$last_line" | sed 's/^[ \t]*//' | sed 's/[ \t]*frames[ \t]*/ frames | /')
        
        echo -e "   > Risultato $phase: ${GREEN}${clean_val}${NC}"
        return 0
    else
        log_warn "Parsing automatico fallito. Output grezzo:"
        tail -n 3 "$file"
        return 1
    fi
}

run_software_test() {
    log_step "FASE 1: Verifica Routing Software (Ardour)"
    
    local ardour_in="ardour:Audio 1/audio_in 1"
    local ardour_out="ardour:Master/audio_out 1"
    local logfile="/tmp/lat_soft.log"

    # Verifica porte
    if ! $J_CMD jack_lsp | grep -Fq "$ardour_in"; then
        log_warn "Traccia '$ardour_in' non trovata. Ardour è aperto?"
        return
    fi

    echo "   Routing: $ardour_in -> $ardour_out"
    echo "   Stato:   Iniezione segnale (I meter DEVONO muoversi)..."

    $J_CMD "$BIN_JACK_DELAY" -O "$ardour_in" -I "$ardour_out" > "$logfile" 2>&1 &
    local pid=$!
    
    sleep 4
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    
    analyze_result "$logfile" "Software"
}

run_hardware_test() {
    log_step "FASE 2: TEST HARDWARE (Loopback Fisico)"
    log_warn "Configurazione richiesta: Cavo Loopback (OUT 1 -> IN 1)"
    log_warn "IMPORTANTE: Metti in MUTE il Master di Ardour o disattiva Input Monitoring!"
    echo -n "   Premi INVIO per misurare..."
    read
    
    local logfile="/tmp/lat_hard.log"
    
    # Esecuzione su porte fisiche
    $J_CMD "$BIN_JACK_DELAY" -I system:capture_1 -O system:playback_1 > "$logfile" 2>&1 &
    local pid=$!
    
    echo "   Campionamento in corso (5s)..."
    sleep 5
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    
    if analyze_result "$logfile" "Hardware"; then
        # Estrazione dati per report finale
        local last_line=$(grep "frames" "$logfile" | tail -n 1)
        # Estrae solo i millisecondi (es. 8.012)
        local ms_measured=$(echo "$last_line" | grep -oE "[0-9]+\.[0-9]+ ms" | awk '{print $1}')
        
        # Calcolo Teorico
        local theoretical_ms=$(echo "scale=3; ($BUFFER * $PERIODS + $BUFFER) / $RATE * 1000" | bc)
        # Calcolo Overhead (Hardware puro)
        local overhead_ms=$(echo "scale=3; $ms_measured - $theoretical_ms" | bc)

        echo ""
        echo "======================================================="
        echo -e "              ${CYAN}REPORT FINALE OLMS${NC}"
        echo "======================================================="
        printf "   %-25s : %s ms\n" "Latenza Teorica (Buffer)" "$theoretical_ms"
        printf "   %-25s : %s ms\n" "Overhead (USB+Conv)" "$overhead_ms"
        echo "   ---------------------------------------"
        printf "   %-25s : ${GREEN}%s ms${NC} (TOTALE)\n" "LATENZA REALE RILEVATA" "$ms_measured"
        echo "======================================================="
    else
        log_err "Test Hardware fallito. Segnale non ricevuto."
    fi
}

# --- MAIN ---
clear
echo "==============================================="
echo "   OLMS LATENCY ANALYZER - v1.9 (CLEAN)"
echo "==============================================="

if ! pgrep -f "jackd.*olms" > /dev/null; then
    log_err "JACK server non attivo."
    exit 1
fi

run_software_test
run_hardware_test

echo -e "\nAnalisi completata."