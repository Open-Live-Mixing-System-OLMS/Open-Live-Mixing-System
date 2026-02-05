#!/bin/bash
# Forza l'ambiente JACK per l'identità 'olms'
set -e

USER="francesco_ssh"
UID_USER=1000
SERVER_NAME="olms"

echo "=== [1] PULIZIA AGGRESSIVA SHM E PROCESSI ==="
sudo pkill -9 jackd || true
sudo pkill -9 jackdbus || true
# Rimuove tutti i segmenti di memoria e i socket residui
sudo rm -rf /dev/shm/jack*
sudo rm -rf /tmp/jack*
sudo rm -f /dev/shm/sem.jack*

echo "=== [2] PREPARAZIONE AMBIENTE SOCKET ==="
# Creiamo la struttura directory che JACK2 si aspetta internamente
sudo mkdir -p /dev/shm/jack-$UID_USER
sudo chown $USER:francesco /dev/shm/jack-$UID_USER
sudo chmod 700 /dev/shm/jack-$UID_USER

echo "=== [3] AVVIO SERVER JACK 'olms' ==="
# Usiamo env -i per garantire che nessuna vecchia variabile interferisca
sudo -u $USER env -i \
    HOME=/home/$USER \
    PATH=/usr/bin:/bin \
    XDG_RUNTIME_DIR=/run/user/$UID_USER \
    JACK_NO_AUDIO_RESERVATION=1 \
    /usr/bin/jackd -R -P 80 -n $SERVER_NAME -d alsa -d hw:1 -r 48000 -p 128 -n 3 > /tmp/jack_olms.log 2>&1 &

sleep 2

echo "=== [4] FIX SYMLINK CRITICI ==="
# JACK2 con -n olms crea /dev/shm/jack_olms_0
# Ma il client lo cerca in /dev/shm/jack-1000/olms
if [ -S /dev/shm/jack_olms_0 ]; then
    sudo ln -sf /dev/shm/jack_olms_0 /dev/shm/jack-$UID_USER/$SERVER_NAME
    sudo ln -sf /dev/shm/jack_olms_0 /dev/shm/jack-$UID_USER/default
    sudo chown -h $USER:francesco /dev/shm/jack-$UID_USER/*
    echo "✅ Socket mappati correttamente."
else
    echo "❌ Errore: Il server JACK non ha creato /dev/shm/jack_olms_0"
    exit 1
fi

echo "=== [5] TEST DI CONVERSIONE (Senza D-Bus) ==="
sudo -u $USER env \
    JACK_DEFAULT_SERVER=$SERVER_NAME \
    JACK_NO_START_SERVER=1 \
    jack_lsp