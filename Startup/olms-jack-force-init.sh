# Copyright (C) 2024 Francesco Nano <tua@email.com>
# 
# This file is part of the Open Live Mixing System (OLMS).
#
# OLMS is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# Created with AI collaboration. Visit: https://openlivemixingsystem.org/

#!/bin/bash
# Force JACK environment for 'olms' identity
set -e

# Importa le funzioni di gestione dei percorsi
source "$(dirname "${BASH_SOURCE[0]}")/olms-path-utils.sh"

# Inizializza i percorsi OLMS
init_olms_paths

USER="$(whoami)"
UID_USER=$(id -u)
SERVER_NAME="olms"

echo "=== [1] AGGRESSIVE SHM AND PROCESS CLEANUP ==="
sudo pkill -9 jackd || true
sudo pkill -9 jackdbus || true
# Remove all residual memory segments and sockets
sudo rm -rf /dev/shm/jack*
sudo rm -rf /tmp/jack*
sudo rm -f /dev/shm/sem.jack*

echo "=== [2] SOCKET ENVIRONMENT PREPARATION ==="
# Create directory structure that JACK2 expects internally
sudo mkdir -p /dev/shm/jack-$UID_USER
sudo chown $USER:francesco /dev/shm/jack-$UID_USER
sudo chmod 700 /dev/shm/jack-$UID_USER

echo "=== [3] START JACK SERVER 'olms' ==="
# Use env -i to ensure no old variables interfere
sudo -u $USER env -i \
    HOME=/home/$USER \
    PATH=/usr/bin:/bin \
    XDG_RUNTIME_DIR=/run/user/$UID_USER \
    JACK_NO_AUDIO_RESERVATION=1 \
    /usr/bin/jackd -R -P 80 -n $SERVER_NAME -d alsa -d hw:1 -r 48000 -p 128 -n 3 > /tmp/jack_olms.log 2>&1 &

sleep 2

echo "=== [4] CRITICAL SYMLINK FIX ==="
# JACK2 with -n olms creates /dev/shm/jack_olms_0
# But client looks for it in /dev/shm/jack-$(id -u)/olms
if [ -S /dev/shm/jack_olms_0 ]; then
    sudo ln -sf /dev/shm/jack_olms_0 /dev/shm/jack-$UID_USER/$SERVER_NAME
    sudo ln -sf /dev/shm/jack_olms_0 /dev/shm/jack-$UID_USER/default
    sudo chown -h $USER:francesco /dev/shm/jack-$UID_USER/*
    echo "✅ Sockets mapped correctly."
else
    echo "❌ Error: JACK server did not create /dev/shm/jack_olms_0"
    exit 1
fi

echo "=== [5] CONVERSION TEST (Without D-Bus) ==="
sudo -u $USER env \
    JACK_DEFAULT_SERVER=$SERVER_NAME \
    JACK_NO_START_SERVER=1 \
    jack_lsp
