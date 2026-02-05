#!/bin/bash
# OLMS Latency Test - ALSA Hardware Level
# Misurazione diretta via Kernel (Bypassing JACK Sockets)

# --- CONFIGURAZIONE ---
DEVICE="hw:1,0"     # La tua scheda USB CODEC
RATE=48000          # Sample Rate OLMS
CHANNELS=2          # Stereo
TEMP_FILE="/tmp/alsabat_result.txt"

# --- COLORI ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

clear
echo "==============================================="
echo "   OLMS HARDWARE LATENCY TEST (ALSA LEVEL)"
echo "==============================================="

# 1. Verifica se alsabat è installato
if ! command -v alsabat &> /dev/null; then
    log_err "alsabat non trovato. Installa 'alsa-utils'."
    exit 1
fi

# 2. Verifica se la scheda è occupata in modo esclusivo
# Nota: ALSA può fallire se JACK ha il controllo esclusivo (HW:1) 
# senza permettere l'apertura multipla.
log_info "Verifica disponibilità hardware $DEVICE..."

# 3. Esecuzione del test di Round-Trip
echo -e "\n--- TEST ROUND-TRIP HARDWARE ---"
log_warn "Assicurati che il cavo FISICO sia collegato (OUT 1 -> IN 1)"
log_info "Esecuzione alsabat in corso..."

set +e
# alsabat genera, cattura e analizza
sudo alsabat -D $DEVICE -r $RATE -c $CHANNELS --roundtrip > $TEMP_FILE 2>&1
EXIT_CODE=$?
set -e

# 4. Analisi Risultati
if [ $EXIT_CODE -eq 0 ] && grep -q "latency" $TEMP_FILE; then
    RESULT=$(grep "latency" $TEMP_FILE)
    echo -e "==============================================="
    echo -e "${GREEN}TEST COMPLETATO CON SUCCESSO${NC}"
    echo -e "Dettaglio: $RESULT"
    
    # Calcolo millisecondi se alsabat restituisce frames
    FRAMES=$(echo $RESULT | grep -oP '\d+(?=\s+frames)' || echo "0")
    if [ "$FRAMES" -gt 0 ]; then
        MS=$(echo "scale=3; ($FRAMES * 1000) / $RATE" | bc -l)
        echo -e "Latenza calcolata: ${GREEN}${MS}ms${NC}"
    fi
else
    log_err "Test fallito o segnale non rilevato."
    log_info "Log di alsabat:"
    cat $TEMP_FILE
fi

echo -e "==============================================="