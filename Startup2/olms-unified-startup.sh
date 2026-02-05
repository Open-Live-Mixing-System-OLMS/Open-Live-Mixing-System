#!/bin/bash
# OLMS-Core: Unified JACK 'olms' & Ardour Startup
set -e

USER="francesco_ssh"
UID_USER=1000
SERVER_NAME="olms"
SESSION_PATH="/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"

echo "=== [1] PULIZIA AGGRESSIVA SHM E PROCESSI ==="
sudo pkill -9 jackdbus || true
sudo pkill -9 ardour8 || true
sudo pkill -9 jackd || true
sudo rm -rf /dev/shm/jack* /tmp/jack* /dev/shm/sem.jack*

echo "=== [2] PREPARAZIONE AMBIENTE SOCKET ==="
sudo mkdir -p /dev/shm/jack-$UID_USER
sudo chown $USER:francesco /dev/shm/jack-$UID_USER

echo "=== [3] AVVIO SERVER JACK 'olms' (FORZATURA 2 CANALI) ==="
sudo -u $USER env -i \
    HOME=/home/$USER \
    PATH=/usr/bin:/bin \
    XDG_RUNTIME_DIR=/run/user/$UID_USER \
    JACK_NO_AUDIO_RESERVATION=1 \
    /usr/bin/jackd -R -P 80 -n $SERVER_NAME -d alsa -d hw:1 \
    -r 48000 -p 128 -n 3 \
    -i 2 -o 2 -S 24bit > /tmp/jack_olms.log 2>&1 &

sleep 3 # Tempo per l'inizializzazione hardware

echo "=== [4] FIX SYMLINK CRITICI (Pattern rilevato: _1000_0) ==="
# Usiamo il pattern corretto emerso dai log precedenti
REAL_SOCKET="/dev/shm/jack_olms_${UID_USER}_0"

if [ -S "$REAL_SOCKET" ]; then
    sudo ln -sf "$REAL_SOCKET" /dev/shm/jack-$UID_USER/$SERVER_NAME
    sudo ln -sf "$REAL_SOCKET" /dev/shm/jack-$UID_USER/default
    sudo chown -h $USER:francesco /dev/shm/jack-$UID_USER/*
    echo "✅ Socket mappati: $REAL_SOCKET -> /dev/shm/jack-$UID_USER/$SERVER_NAME"
else
    echo "❌ Errore: Il server JACK non ha creato $REAL_SOCKET"
    exit 1
fi

echo "=== [5] AVVIO ARDOUR FORZATO SU OLMS ==="
# Puliamo i file di stato temporanei di Ardour che potrebbero contenere vecchie porte dummy
rm -f /home/$USER/.config/ardour8/jack_connections

sudo -u $USER env \
    HOME=/home/$USER \
    DISPLAY=:0 \
    XAUTHORITY=/home/$USER/.Xauthority \
    XDG_RUNTIME_DIR=/run/user/$UID_USER \
    JACK_DEFAULT_SERVER=$SERVER_NAME \
    JACK_NO_START_SERVER=1 \
    /usr/bin/ardour8 --no-splash -P "$SESSION_PATH" &

echo "=== [6] ATTESA E PATCHING AUTOMATICO ==="
sleep 10 # Tempo per caricare la sessione

# Funzione per connettere le porte
connect_ports() {
    sudo -u $USER env JACK_DEFAULT_SERVER=$SERVER_NAME jack_connect "$1" "$2" 2>/dev/null || echo "⚠️ Già connesso o porta non trovata: $2"
}

echo "Mapping degli ingressi hardware ad Ardour..."
connect_ports "system:capture_1" "ardour:Audio 1/audio_in 1"
connect_ports "system:capture_2" "ardour:Audio 1/audio_in 2"

echo "Mapping del Master alle uscite fisiche..."
connect_ports "ardour:Master/audio_out 1" "system:playback_1"
connect_ports "ardour:Master/audio_out 2" "system:playback_2"

echo "=== SETUP COMPLETATO ==="
sudo -u $USER env JACK_DEFAULT_SERVER=$SERVER_NAME jack_lsp