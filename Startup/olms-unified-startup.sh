# Copyright (C) 2026 Francesco Nano
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
# OLMS-Core: Unified JACK 'olms' & Ardour Startup
set -e

USER="$(whoami)"
UID_USER=$(id -u)
SERVER_NAME="olms"
SESSION_PATH="/home/$(whoami)/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"

echo "=== [1] AGGRESSIVE SHM AND PROCESS CLEANUP ==="
sudo pkill -9 jackdbus || true
sudo pkill -9 ardour8 || true
sudo pkill -9 jackd || true
sudo rm -rf /dev/shm/jack* /tmp/jack* /dev/shm/sem.jack*

echo "=== [2] SOCKET ENVIRONMENT PREPARATION ==="
sudo mkdir -p /dev/shm/jack-$UID_USER
sudo chown $USER:francesco /dev/shm/jack-$UID_USER

echo "=== [3] STARTING JACK SERVER 'olms' (FORCED 2 CHANNELS) ==="
sudo -u $USER env -i \
    HOME=/home/$USER \
    PATH=/usr/bin:/bin \
    XDG_RUNTIME_DIR=/run/user/$UID_USER \
    JACK_NO_AUDIO_RESERVATION=1 \
    /usr/bin/jackd -R -P 80 -n $SERVER_NAME -d alsa -d hw:1 \
    -r 48000 -p 128 -n 3 \
    -i 2 -o 2 -S 24bit > /tmp/jack_olms.log 2>&1 &

sleep 3 # Time for hardware initialization

echo "=== [4] CRITICAL SYMLINK FIX (Pattern detected: _$(id -u)_0) ==="
# Use the correct pattern from previous logs
REAL_SOCKET="/dev/shm/jack_olms_${UID_USER}_0"

if [ -S "$REAL_SOCKET" ]; then
    sudo ln -sf "$REAL_SOCKET" /dev/shm/jack-$UID_USER/$SERVER_NAME
    sudo ln -sf "$REAL_SOCKET" /dev/shm/jack-$UID_USER/default
    sudo chown -h $USER:francesco /dev/shm/jack-$UID_USER/*
    echo "✅ Sockets mapped: $REAL_SOCKET -> /dev/shm/jack-$UID_USER/$SERVER_NAME"
else
    echo "❌ Error: JACK server did not create $REAL_SOCKET"
    exit 1
fi

echo "=== [5] FORCED ARDOUR STARTUP ON OLMS ==="
# Clean Ardour temporary state files that might contain old dummy ports
rm -f /home/$USER/.config/ardour8/jack_connections

sudo -u $USER env \
    HOME=/home/$USER \
    DISPLAY=:0 \
    XAUTHORITY=/home/$USER/.Xauthority \
    XDG_RUNTIME_DIR=/run/user/$UID_USER \
    JACK_DEFAULT_SERVER=$SERVER_NAME \
    JACK_NO_START_SERVER=1 \
    /usr/bin/ardour8 --no-splash -P "$SESSION_PATH" &

echo "=== [6] WAIT AND AUTOMATIC PATCHING ==="
sleep 10 # Time to load session

# Function to connect ports
connect_ports() {
    sudo -u $USER env JACK_DEFAULT_SERVER=$SERVER_NAME jack_connect "$1" "$2" 2>/dev/null || echo "⚠️ Already connected or port not found: $2"
}

echo "Mapping hardware inputs to Ardour..."
connect_ports "system:capture_1" "ardour:Audio 1/audio_in 1"
connect_ports "system:capture_2" "ardour:Audio 1/audio_in 2"

echo "Mapping Master to physical outputs..."
connect_ports "ardour:Master/audio_out 1" "system:playback_1"
connect_ports "ardour:Master/audio_out 2" "system:playback_2"

echo "=== SETUP COMPLETED ==="
sudo -u $USER env JACK_DEFAULT_SERVER=$SERVER_NAME jack_lsp
