#!/bin/bash

# OLMS Hard Reset Script
# Pulisce i processi audio e avvia JACK con configurazione ottimale
# Basato su test su Arch Linux (Kernel 6.14)

set -e

echo "=== OLMS HARD RESET ==="
echo "Data: $(date)"
echo

# Funzione per verificare se un comando è disponibile
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Errore: comando '$1' non disponibile"
        exit 1
    fi
}

# 1. Verifica privilegi real-time attivi
echo "1. Verifica privilegi real-time attivi:"
echo "Current user limits:"
ulimit -r
ulimit -l
echo

# 2. Verifica gruppi utente effettivi
echo "2. Verifica gruppi utente effettivi:"
id $USER
echo

# 3. Pulizia completa processi audio (Hard Reset)
echo "3. Pulizia completa processi audio (Hard Reset)..."
echo "Fermo tutti i processi JACK e jackdbus..."
killall -9 jackd jackdbus 2>/dev/null || true
sleep 2
echo "Processi JACK dopo pulizia:"
pgrep -f jackd || echo "Nessun processo JACK trovato"
echo

# 4. Avvio JACK con configurazione ottimale
echo "4. Avvio JACK con configurazione ottimale..."
echo "Comando: taskset -c 2-3 chrt -f 80 jackd -R -P 80 -d alsa -d hw:1,0 -r 48000 -p 64 -n 3"
taskset -c 2-3 chrt -f 80 jackd -R -P 80 -d alsa -d hw:1,0 -r 48000 -p 64 -n 3 &
JACK_PID=$!
echo "JACK avviato con PID: $JACK_PID"
sleep 5
echo

# 5. Verifica stato JACK
echo "5. Verifica stato JACK:"
if command -v jack_control >/dev/null 2>&1; then
    echo "Stato JACK:"
    jack_control status
else
    echo "⚠ jack_control non disponibile"
fi
echo

# 6. Verifica priorità processi JACK
echo "6. Verifica priorità processi JACK:"
for pid in $(pgrep -f jackd 2>/dev/null); do
    echo "PID $pid:"
    chrt -p $pid 2>/dev/null || echo "Non disponibile"
done
echo

# 7. Verifica porte JACK disponibili
echo "7. Verifica porte JACK disponibili:"
if command -v jack_lsp >/dev/null 2>&1; then
    echo "Porte JACK:"
    jack_lsp 2>/dev/null | head -10 || echo "Nessuna porta disponibile"
else
    echo "⚠ jack_lsp non disponibile"
fi
echo

# 8. Verifica ambiente X11 per Ardour
echo "8. Verifica ambiente X11 per Ardour:"
echo "DISPLAY: $DISPLAY"
echo "XAUTHORITY: $XAUTHORITY"
echo "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
if [ -n "$DISPLAY" ]; then
    if xset q >/dev/null 2>&1; then
        echo "✓ Connessione X11 OK"
    else
        echo "⚠ Connessione X11 FALLITA"
    fi
else
    echo "⚠ Nessun DISPLAY impostato"
fi
echo

# 9. Avvia Ardour se JACK è attivo
echo "9. Verifica se avviare Ardour:"
if command -v jack_control >/dev/null 2>&1; then
    JACK_STATUS=$(jack_control status 2>/dev/null | grep -i "running\|active" || echo "")
    if [ -n "$JACK_STATUS" ]; then
        echo "✓ JACK è attivo, provo ad avviare Ardour..."
        if command -v ardour >/dev/null 2>&1; then
            echo "Avvio Ardour in background..."
            ardour &
            ARDOUR_PID=$!
            echo "Ardour avviato con PID: $ARDOUR_PID"
            sleep 2
            echo "Processi Ardour attivi:"
            pgrep -f ardour || echo "Nessun processo Ardour trovato"
        else
            echo "⚠ Ardour non disponibile nel sistema"
        fi
    else
        echo "⚠ JACK non è attivo, Ardour non verrà avviato"
    fi
else
    echo "⚠ Impossibile verificare lo stato di JACK"
fi
echo

# 10. Verifica finale
echo "10. Verifica finale:"
echo "Processi audio attivi:"
ps aux | grep -E "(jack|ardour)" | grep -v grep || echo "Nessun processo audio trovato"
echo

echo "=== HARD RESET COMPLETATO ==="
echo "Se JACK è attivo e Ardour è stato avviato, il sistema è pronto per l'uso!"
echo "Stato atteso: JACK Running, Ardour attivo, latenza ~1.3ms, nessun XRUN"