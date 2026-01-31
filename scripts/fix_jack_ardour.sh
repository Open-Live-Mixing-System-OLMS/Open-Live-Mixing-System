# Copyright (C) 2024 Francesco Nano and AI
# 
# This file is part of the Open Live Mixing System (OLMS) project.
# Created by Francesco Nano with AI assistance at https://openlivemixingsystem.org/
#
# Connect, collaborate, and stay updated with announcements at:
# https://openlivemixingsystem.org/
#
# Licensed under the GNU General Public License v3.0 (GPL-3.0)
# See LICENSE file for full license terms and conditions.
#
# This software is provided 'as-is', without any express or implied warranty.
# In no event will the authors be held liable for any damages arising from
# the use of this software.

#!/bin/bash

# Script di correzione per problemi JACK e Ardour
# Risolve i problemi di privilegi real-time e avvio dei servizi audio

set -e  # Esci in caso di errore

echo "=== SCRIPT DI CORREZIONE JACK/ARDOUR ==="
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

# 3. Verifica stato attuale di JACK
echo "3. Stato attuale di JACK:"
if command -v jack_control >/dev/null 2>&1; then
    jack_control status
else
    echo "⚠ jack_control non disponibile"
fi
echo

# 4. Ferma processi JACK esistenti
echo "4. Ferma processi JACK esistenti..."
echo "Processi JACK prima:"
pgrep -f jackd || echo "Nessun processo JACK trovato"
echo "Fermo i processi JACK..."
sudo pkill -f jackd 2>/dev/null || true
sleep 2
echo "Processi JACK dopo:"
pgrep -f jackd || echo "Nessun processo JACK trovato"
echo

# 5. Avvia JACK con priorità real-time corretta
echo "5. Avvio JACK con priorità real-time..."
echo "Avvio JACK con taskset e chrt..."
sudo taskset -c 2-3 chrt -f 80 jackd -R -d alsa -r48000 -p64 -n 3 -d hw:1,0 &
JACK_PID=$!
echo "JACK avviato con PID: $JACK_PID"
sleep 3
echo

# 6. Verifica stato JACK dopo riavvio
echo "6. Verifica stato JACK dopo riavvio:"
if command -v jack_control >/dev/null 2>&1; then
    echo "Stato JACK:"
    jack_control status
else
    echo "⚠ jack_control non disponibile"
fi
echo

# 7. Verifica priorità processi JACK
echo "7. Verifica priorità processi JACK:"
for pid in $(pgrep -f jackd 2>/dev/null); do
    echo "PID $pid:"
    chrt -p $pid 2>/dev/null || echo "Non disponibile"
done
echo

# 8. Verifica porte JACK disponibili
echo "8. Verifica porte JACK disponibili:"
if command -v jack_lsp >/dev/null 2>&1; then
    echo "Porte JACK:"
    jack_lsp 2>/dev/null | head -10 || echo "Nessuna porta disponibile"
else
    echo "⚠ jack_lsp non disponibile"
fi
echo

# 9. Verifica ambiente X11 per Ardour
echo "9. Verifica ambiente X11 per Ardour:"
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

# 10. Avvia Ardour se JACK è attivo
echo "10. Verifica se avviare Ardour:"
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

# 11. Verifica finale
echo "11. Verifica finale:"
echo "Processi audio attivi:"
ps aux | grep -E "(jack|ardour)" | grep -v grep || echo "Nessun processo audio trovato"
echo

echo "=== VERIFICA COMPLETATA ==="
echo "Se JACK è attivo e Ardour è stato avviato, i problemi sono stati risolti!"