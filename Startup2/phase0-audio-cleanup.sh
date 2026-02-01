#!/bin/bash

# Fase 0.2: Audio Environment Nuclear Cleanup
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
TEMP_DIR="/tmp"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Terminazione processi audio aggressiva
kill_audio_processes() {
    log "Terminazione processi audio con strategia aggressiva..."
    
    # Lista processi da terminare
    local audio_processes=(
        "jackd" "jackdbus"
        "pipewire" "wireplumber"
        "pulseaudio" "pulseaudio-module"
        "alsa" "alsactl"
        "artix-alsa" "artix-pulse"
        "pipewire-pulse" "pipewire-alsa"
    )
    
    for process in "${audio_processes[@]}"; do
        local pids=$(pgrep -f "$process" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log "Trovati processi $process: $pids"
            
            # Fase 1: SIGTERM
            for pid in $pids; do
                kill -TERM "$pid" 2>/dev/null || true
            done
            sleep 1
            
            # Fase 2: SIGKILL
            local remaining=$(pgrep -f "$process" 2>/dev/null || true)
            for pid in $remaining; do
                kill -KILL "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
    done
    
    # Verifica terminazione
    local remaining_audio=$(pgrep -f "jackd|pipewire|pulseaudio" 2>/dev/null || true)
    if [[ -n "$remaining_audio" ]]; then
        warn "Alcuni processi audio non sono stati terminati: $remaining_audio"
    else
        log "Tutti i processi audio sono stati terminati"
    fi
}

# Rimozione file socket
remove_socket_files() {
    log "Rimozione file socket audio..."
    
    # Pattern socket JACK
    local jack_patterns=(
        "/tmp/jack_*"
        "/dev/shm/jack_*"
        "/var/run/jack_*"
        "/run/jack_*"
        "/tmp/.jack*"
        "/var/lock/.jack*"
    )
    
    # Pattern socket Pipewire
    local pipewire_patterns=(
        "/tmp/pipewire*"
        "/dev/shm/pipewire*"
        "/var/run/pipewire*"
        "/run/pipewire*"
        "/tmp/.pipewire*"
        "/var/lock/.pipewire*"
    )
    
    # Rimuovi file socket JACK
    for pattern in "${jack_patterns[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            log "Rimozione socket JACK: $pattern"
            rm -rf $pattern
        fi
    done
    
    # Rimuovi file socket Pipewire
    for pattern in "${pipewire_patterns[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            log "Rimozione socket Pipewire: $pattern"
            rm -rf $pattern
        fi
    done
    
    log "File socket rimossi"
}

# Cleanup shared memory IPC
cleanup_shared_memory() {
    log "Cleanup shared memory IPC..."
    
    # Rimuovi shared memory segments
    local shm_ids=$(ipcs -m | awk 'NR>3 {print $2}' 2>/dev/null || true)
    for shm_id in $shm_ids; do
        if [[ -n "$shm_id" ]]; then
            ipcrm -m "$shm_id" 2>/dev/null || true
        fi
    done
    
    # Rimuovi semaphores
    local sem_ids=$(ipcs -s | awk 'NR>3 {print $2}' 2>/dev/null || true)
    for sem_id in $sem_ids; do
        if [[ -n "$sem_id" ]]; then
            ipcrm -s "$sem_id" 2>/dev/null || true
        fi
    done
    
    log "Shared memory IPC pulito"
}

# Hardware reset - rilascio dispositivi audio
reset_audio_hardware() {
    log "Hardware reset - rilascio dispositivi audio..."
    
    # Forza il rilascio dei dispositivi audio
    if [[ -d "/dev/snd" ]]; then
        log "Rilascio dispositivi /dev/snd/*"
        fuser -k /dev/snd/* 2>/dev/null || true
        sleep 1
    fi
    
    # Unload/reload moduli kernel (se possibile)
    local kernel_modules=(
        "snd_hda_intel"
        "snd_usb_audio"
        "snd_hda_codec"
        "snd_seq"
    )
    
    for module in "${kernel_modules[@]}"; do
        if lsmod | grep -q "^$module "; then
            log "Unloading kernel module: $module"
            modprobe -r "$module" 2>/dev/null || true
            sleep 0.5
        fi
    done
    
    # Reload moduli
    for module in "${kernel_modules[@]}"; do
        log "Reloading kernel module: $module"
        modprobe "$module" 2>/dev/null || true
        sleep 0.5
    done
    
    log "Hardware audio resettato"
}

# Pulizia directory temporanee
cleanup_temp_directories() {
    log "Pulizia directory temporanee..."
    
    # Directory da pulire
    local temp_dirs=(
        "/tmp/jack*"
        "/tmp/pipewire*"
        "/dev/shm/jack*"
        "/dev/shm/pipewire*"
    )
    
    for dir_pattern in "${temp_dirs[@]}"; do
        if ls $dir_pattern 1> /dev/null 2>&1; then
            log "Pulizia directory: $dir_pattern"
            rm -rf $dir_pattern
        fi
    done
    
    log "Directory temporanee pulite"
}

# Verifica cleanup completato
verify_cleanup() {
    log "Verifica cleanup audio completato..."
    
    # Verifica processi
    local remaining_audio=$(pgrep -f "jackd|pipewire|pulseaudio" 2>/dev/null || true)
    if [[ -n "$remaining_audio" ]]; then
        warn "Processi audio ancora attivi: $remaining_audio"
    else
        log "Nessun processo audio attivo"
    fi
    
    # Verifica socket
    local remaining_sockets=$(find /tmp /dev/shm /var/run /run -name "*jack*" -o -name "*pipewire*" 2>/dev/null || true)
    if [[ -n "$remaining_sockets" ]]; then
        warn "Socket audio ancora presenti: $remaining_sockets"
    else
        log "Nessun socket audio presente"
    fi
    
    # Verifica dispositivi
    if [[ -d "/dev/snd" ]]; then
        local device_users=$(fuser /dev/snd/* 2>/dev/null || true)
        if [[ -n "$device_users" ]]; then
            warn "Dispositivi audio ancora in uso: $device_users"
        else
            log "Dispositivi audio liberi"
        fi
    fi
}

# Funzione principale
main() {
    log "=== FASE 0.2: AUDIO ENVIRONMENT NUCLEAR CLEANUP ==="
    
    kill_audio_processes
    remove_socket_files
    cleanup_shared_memory
    reset_audio_hardware
    cleanup_temp_directories
    verify_cleanup
    
    log "Audio environment cleanup completato"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi