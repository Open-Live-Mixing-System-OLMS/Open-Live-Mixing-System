#!/bin/bash

# Fase 5: Avvio di Ardour - FIX PARSING prlimit
set -euo pipefail

# Configurazione logging
LOG_FILE="/tmp/olms-ardour-startup.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Variabili di configurazione
ARD_SESSION_PATH="/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"
ARD_SESSION_DIR="/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC"
ARD_USER="francesco_ssh"
ARD_UID=1000

# Variabili JACK/D-Bus/X11
JACK_SERVER_NAME="olms"
JACK_SESSION_DIR="/dev/shm/jack_olms_0"
JACK_SOCKET_DIR="/dev/shm/jack_olms_0"
DBUS_SOCKET_ABSTRACT="olms_bus_1000"
XAUTHORITY_PATH="/home/francesco_ssh/.Xauthority"
DISPLAY=":0"
CPU_CORES="2-3"
RT_PRIORITY=70

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRORE: $1" >&2; }

check_user_permissions() {
    log "Verifica permessi utente $ARD_USER..."
    
    # Estraiamo il valore SOFT (terzultimo) e HARD (penultimo) per essere sicuri
    local rtprio_limit=$(sudo -u "$ARD_USER" prlimit --rtprio --pid=$$ --noheadings --output=SOFT)
    local memlock_limit=$(sudo -u "$ARD_USER" prlimit --memlock --pid=$$ --noheadings --output=SOFT)

    log "Rilevato rtprio_limit: $rtprio_limit"
    log "Rilevato memlock_limit: $memlock_limit"

    if [[ "$rtprio_limit" != "unlimited" ]] && [ "$rtprio_limit" -lt 90 ]; then
        log "ERRORE: rtprio troppo basso ($rtprio_limit)"
        return 1
    fi
    return 0
}

start_ardour_with_fallback() {
    log "=== AVVIO ARDOUR ==="
    
    # Ambiente pulito per l'esecuzione come utente target
    local base_env="DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY_PATH XDG_RUNTIME_DIR=/run/user/$ARD_UID DBUS_SESSION_BUS_ADDRESS=unix:abstract=$DBUS_SOCKET_ABSTRACT JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_SESSION_DIR=$JACK_SESSION_DIR JACK_NO_START_SERVER=1 JACK_PROMISCUOUS_SERVER=1"

    log "Esecuzione comando finale..."
    # Aggiungi esplicitamente il flag -Z (o --jack-server) ad Ardour
    sudo -u "$ARD_USER" -E env $base_env taskset -c "$CPU_CORES" chrt -f "$RT_PRIORITY" /usr/bin/ardour8 -Z olms -n "$ARD_SESSION_PATH"
}

main() {
    log "=== FASE 5: STARTUP ARDOUR (Bypass Mode) ==="
    
    # 1. Verifica fisica del socket (più affidabile di jack_lsp in questo setup)
    if [ -S "/dev/shm/jack_olms_0" ]; then
        log "✅ Socket JACK rilevato correttamente in /dev/shm/jack_olms_0"
    else
        error "ERRORE: Socket JACK 'olms' non trovato. Il server è avviato?"
        exit 1
    fi

    # 2. Verifica del processo
    if pgrep -f "jackd.*-n olms" > /dev/shm/null; then
        log "✅ Processo JACK 'olms' verificato."
    else
        error "ERRORE: Processo jackd non trovato."
        exit 1
    fi

    # 3. Lancio di Ardour con iniezione totale dell'ambiente
    log "Avvio Ardour con parametri di compatibilità JACK2..."
    
    # Prepariamo l'ambiente esatto per francesco_ssh
    sudo -u "$ARD_USER" env \
        HOME=/home/francesco_ssh \
        DISPLAY=:0 \
        XAUTHORITY=/home/francesco_ssh/.Xauthority \
        XDG_RUNTIME_DIR=/run/user/1000 \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH"
}

main "$@"