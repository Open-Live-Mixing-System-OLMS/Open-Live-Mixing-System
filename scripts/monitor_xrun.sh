#!/bin/bash
# MONITOR XRUN - Strumento per monitorare gli xrun di JACK da terminale
# Questo script monitora gli xrun del server JACK in tempo reale

set -e

# Configurazione
export TARGET_USER="francesco_ssh"
export J_ENV="XDG_RUNTIME_DIR=/run/user/1000 JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1"
export J_CMD="sudo -u $TARGET_USER env $J_ENV"

# Colori
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Funzione per ottenere gli xrun
get_xruns() {
    local stats=$($J_CMD jack_lsp -p 2>/dev/null)
    if [ -z "$stats" ]; then
        echo "0"
    else
        local result=$(echo "$stats" | grep "xruns" | head -n1 | awk -F'xruns: ' '{print $2}' | awk '{print $1}' | tr -dc '0-9')
        echo "${result:-0}"
    fi
}

# Funzione per ottenere il carico CPU
get_cpu_load() {
    $J_CMD jack_cpu_load 2>/dev/null | head -n1 | awk '{printf "%.1f%%", $1}' || echo "0.0%"
}

# Funzione di cleanup
cleanup() {
    echo -e "\n${YELLOW}[MONITOR]${NC} Arresto monitoraggio..."
    tput cnorm
    exit 0
}

# Handler per i segnali
trap cleanup INT TERM

# Controllo se JACK è attivo
if ! pgrep -f "jackd.*olms" > /dev/null; then
    echo -e "${RED}[ERROR]${NC} JACK server non attivo."
    exit 1
fi

# Inizio monitoraggio
echo "=================================================="
echo "    MONITOR XRUN - JACK Server: olms"
echo "=================================================="
echo -e "${CYAN}[INFO]${NC} Monitoraggio avviato. Premi Ctrl+C per terminare."
echo ""

# Variabili di stato
START_XRUNS=$(get_xruns)
LAST_XRUNS=$START_XRUNS
TOTAL_XRUNS=0
CHECK_COUNT=0

# Loop di monitoraggio
while true; do
    CURRENT_XRUNS=$(get_xruns)
    CURRENT_CPU=$(get_cpu_load)
    
    # Calcolo delta
    DELTA=$(( CURRENT_XRUNS - LAST_XRUNS ))
    TOTAL_DELTA=$(( CURRENT_XRUNS - START_XRUNS ))
    
    # Aggiorna stato
    if [ $DELTA -gt 0 ]; then
        TOTAL_XRUNS=$((TOTAL_XRUNS + DELTA))
        CHECK_COUNT=$((CHECK_COUNT + 1))
        echo -e "${RED}[XRUN]${NC} Nuovi xrun rilevati: $DELTA (Totale sessione: $TOTAL_DELTA, Media: $(( TOTAL_XRUNS / (CHECK_COUNT + 1) )))"
        echo -e "${YELLOW}[INFO]${NC} Carico CPU: $CURRENT_CPU"
        echo -e "${CYAN}[INFO]${NC} Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
    fi
    
    LAST_XRUNS=$CURRENT_XRUNS
    sleep 1
done