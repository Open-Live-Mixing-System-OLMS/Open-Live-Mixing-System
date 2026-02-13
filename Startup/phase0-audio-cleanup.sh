#!/bin/bash

# Phase 0.2: Audio Environment Nuclear Cleanup
# Version: 2.0

set -euo pipefail

# Configuration
# Smart home path management to handle sudo execution
if [[ "$EUID" -eq 0 ]]; then
    # If we are root, we need to determine the actual user
    if [[ -n "${SUDO_USER:-}" ]]; then
        # Executed with sudo, use the original user
        ACTUAL_USER="$SUDO_USER"
        ACTUAL_HOME=$(eval echo ~$SUDO_USER)
    elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
        # Executed as root but USER is set to a non-root user
        ACTUAL_USER="$USER"
        ACTUAL_HOME=$(eval echo ~$USER)
    else
        # Executed directly as root
        ACTUAL_USER="root"
        ACTUAL_HOME="/root"
    fi
else
    # Executed as normal user
    ACTUAL_USER="$(whoami)"
    ACTUAL_HOME="$HOME"
fi

LOG_FILE="$ACTUAL_HOME/olms-orchestrator.log"
TEMP_DIR="/tmp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} Startup process aborted due to warning: $1" | tee -a "$LOG_FILE"
    exit 1
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Aggressive audio process termination
kill_audio_processes() {
    log "Terminating audio processes with aggressive strategy..."
    
    # List of processes to terminate
    local audio_processes=(
        "jackd" "jackdbus"
        "pipewire" "wireplumber"
        "pulseaudio" "pulseaudio-module"
        "alsa" "alsactl"
        "artix-alsa" "artix-pulse"
        "pipewire-pulse" "pipewire-alsa"
        "ardour" "ardour8"
        "Xvfb" "xvfb"
    )
    
    for process in "${audio_processes[@]}"; do
        local pids=$(pgrep -f "$process" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log "Found $process processes: $pids"
            
            # Phase 1: SIGTERM
            for pid in $pids; do
                kill -TERM "$pid" 2>/dev/null || true
            done
            sleep 1
            
            # Phase 2: SIGKILL with sudo for root processes
            local remaining=$(pgrep -f "$process" 2>/dev/null || true)
            for pid in $remaining; do
                # Try first without sudo, then with sudo if necessary
                if ! kill -KILL "$pid" 2>/dev/null; then
                    log "Attempting forced termination with sudo for PID $pid"
                    sudo kill -9 "$pid" 2>/dev/null || warn "Unable to terminate PID $pid even with sudo"
                fi
            done
            sleep 1
        fi
    done
    
    # Verify termination
    local remaining_audio=$(pgrep -f "jackd|pipewire|pulseaudio" 2>/dev/null || true)
    if [[ -n "$remaining_audio" ]]; then
        warn "Some audio processes were not terminated: $remaining_audio"
        # Attempt forced termination with sudo for root processes
        for pid in $remaining_audio; do
            if kill -0 "$pid" 2>/dev/null; then
                log "Attempting forced termination with sudo for PID $pid"
                sudo kill -9 "$pid" 2>/dev/null || warn "Unable to terminate PID $pid even with sudo"
            fi
        done
    else
        log "All audio processes have been terminated"
    fi
}

# Remove socket files
remove_socket_files() {
    log "Removing audio socket files..."
    
    # JACK socket patterns
    local jack_patterns=(
        "/tmp/jack_*"
        "/dev/shm/jack_*"
        "/dev/shm/jack-default_*"
        "/var/run/jack_*"
        "/run/jack_*"
        "/tmp/.jack*"
        "/var/lock/.jack*"
    )
    
    # Pipewire socket patterns
    local pipewire_patterns=(
        "/tmp/pipewire*"
        "/dev/shm/pipewire*"
        "/var/run/pipewire*"
        "/run/pipewire*"
        "/tmp/.pipewire*"
        "/var/lock/.pipewire*"
    )
    
    # Remove JACK socket files (AGGRESSIVE - remove ALL files)
    # BUT: Don't remove JACK sockets if JACK is already running (to avoid conflicts with Phase 3)
    local jack_running=false
    if pgrep -f "jackd" >/dev/null 2>&1; then
        log "JACK is already running, skipping JACK socket removal"
        jack_running=true
    fi
    
    if [[ "$jack_running" == "false" ]]; then
        for pattern in "${jack_patterns[@]}"; do
            if ls $pattern 1> /dev/null 2>&1; then
                log "Removing JACK socket: $pattern"
                # Remove ALL JACK socket files, regardless of owner
                # Use sudo to remove files owned by user $(whoami) as well
                for file in $pattern; do
                    if [[ -e "$file" ]]; then
                        log "Forced removal of JACK socket: $file"
                        sudo rm -rf "$file" 2>/dev/null || warn "Unable to remove $file (continuing anyway)"
                    fi
                done
            fi
        done
    fi
    
    # Remove Pipewire socket files
    for pattern in "${pipewire_patterns[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            log "Removing Pipewire socket: $pattern"
            # Only remove files/directories that belong to the current user
            for file in $pattern; do
                if [[ -e "$file" ]]; then
                    file_owner=$(stat -c '%U' "$file" 2>/dev/null || echo "unknown")
                    if [[ "$file_owner" == "$(whoami)" ]]; then
                        rm -rf "$file" 2>/dev/null || warn "Unable to remove $file (permission denied)"
                    else
                        log "Skipped $file (belongs to $file_owner)"
                    fi
                fi
            done
        fi
    done
    
    log "Socket files removed"
}

# Cleanup shared memory IPC
cleanup_shared_memory() {
    log "Cleaning up shared memory IPC..."
    
    # Remove shared memory segments
    local shm_ids=$(ipcs -m | awk 'NR>3 {print $2}' 2>/dev/null || true)
    for shm_id in $shm_ids; do
        if [[ -n "$shm_id" ]]; then
            ipcrm -m "$shm_id" 2>/dev/null || true
        fi
    done
    
    # Remove semaphores
    local sem_ids=$(ipcs -s | awk 'NR>3 {print $2}' 2>/dev/null || true)
    for sem_id in $sem_ids; do
        if [[ -n "$sem_id" ]]; then
            ipcrm -s "$sem_id" 2>/dev/null || true
        fi
    done
    
    log "Shared memory IPC cleaned"
}

# Disable internal audio cards
disable_internal_audio() {
    log "Disabling internal audio cards..."
    
    # Pre-check: verify if audio is already disabled via kernel parameter
    local enable_status=$(cat /sys/module/snd_hda_intel/parameters/enable 2>/dev/null || echo "")
    if [[ "$enable_status" =~ ^N, ]]; then
        log "Integrated audio already disabled via kernel parameter - skipping PCI disable"
        return 0
    fi
    
    # Identify all PCI audio cards (excluding USB)
    local pci_audio_devices=$(lspci | grep -i "audio" | grep -v "usb" | awk '{print $1}')
    
    if [[ -n "$pci_audio_devices" ]]; then
        log "PCI audio cards found: $pci_audio_devices"
        
        for device in $pci_audio_devices; do
            local device_path="/sys/bus/pci/devices/0000:$device"
            
            if [[ -d "$device_path" ]]; then
                log "Disabling PCI audio card: $device"
                
                # Try to disable the card
                if echo 0 > "$device_path/enable" 2>/dev/null; then
                    log "Audio card $device disabled successfully"
                else
                    # If it fails, log but DON'T block startup
                    warn "Unable to disable audio card $device (insufficient permissions - will continue startup)"
                fi
            fi
        done
        
        # Wait for disable completion
        sleep 2
        
        # Verify disable
        local remaining_pci_audio=$(lspci | grep -i "audio" | grep -v "usb" | wc -l)
        if [[ $remaining_pci_audio -eq 0 ]]; then
            log "All PCI audio cards disabled successfully"
        else
            warn "Some PCI audio cards might still be active"
        fi
    else
        log "No PCI audio cards found to disable"
    fi
}

# Wait for USB audio device detection (Universal UAC Version)
wait_usb_audio_devices() {
    log "Waiting for USB audio device detection (Kernel-Class Method)..."
    
    local usb_audio_wait=30
    local usb_audio_found=false
    
    for i in $(seq 1 $usb_audio_wait); do
        # 1. Primary check: snd-usb-audio driver loaded and active
        if grep -q "usb" /proc/asound/cards 2>/dev/null; then
            local card_info=$(grep "usb" /proc/asound/cards | head -n1)
            log "✅ USB Audio device detected in kernel: $card_info"
            usb_audio_found=true
            break
        fi
        
        # 2. Secondary check: Physical presence via SysFS (faster than lsusb)
        if find /sys/class/sound/card* -name "id" -exec grep -l "" {} + 2>/dev/null | xargs cat | grep -qi "usb\|codec\|audio" 2>/dev/null; then
            log "✅ USB Audio device detected via SysFS"
            usb_audio_found=true
            break
        fi

        log "Attempt $i/$usb_audio_wait: No USB audio device ready yet..."
        sleep 1
    done
    
    if [[ "$usb_audio_found" == "true" ]]; then
        log "USB audio devices detected, continuing startup"
    else
        # Instead of 'warn' which causes exit 1, we use an error log but allow fallback
        error "No USB audio device detected. JACK will try to use dummy or integrated backend."
    fi
}

# Hardware reset - audio device release
reset_audio_hardware() {
    log "Hardware reset - releasing audio devices..."
    
    # Force release of audio devices
    if [[ -d "/dev/snd" ]]; then
        log "Releasing /dev/snd/* devices"
        fuser -k /dev/snd/* 2>/dev/null || true
        sleep 1
    fi
    
    # Unload/reload kernel modules (if possible)
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
    
    # Reload modules
    for module in "${kernel_modules[@]}"; do
        log "Reloading kernel module: $module"
        modprobe "$module" 2>/dev/null || true
        sleep 0.5
    done
    
    log "Hardware audio reset"
}

# Clean temporary directories
cleanup_temp_directories() {
    log "Cleaning temporary directories..."
    
    # Directories to clean (AGGRESSIVE - remove ALL files)
    local temp_dirs=(
        "/tmp/jack*"
        "/tmp/pipewire*"
        "/dev/shm/jack*"
        "/dev/shm/jack-default_*"
        "/dev/shm/pipewire*"
    )
    
    for dir_pattern in "${temp_dirs[@]}"; do
        if ls $dir_pattern 1> /dev/null 2>&1; then
            log "Cleaning directory: $dir_pattern"
            # Remove ALL JACK socket files, regardless of owner
            # Use sudo to remove files owned by user $(whoami) as well
            for file in $dir_pattern; do
                if [[ -e "$file" ]]; then
                    log "Forced removal of temporary directory: $file"
                    sudo rm -rf "$file" 2>/dev/null || warn "Unable to remove $file (continuing anyway)"
                fi
            done
        fi
    done
    
    log "Temporary directories cleaned"
}

# Verify cleanup completed
verify_cleanup() {
    log "Verifying audio cleanup completed..."
    
    # Check how many USB devices there are (excluding hubs and non-critical devices)
    local usb_count=$(lsusb | grep -v "Alcor Micro Corp. USB Hub" | grep -v "Linux Foundation" | wc -l)
    if [[ $usb_count -gt 3 ]]; then
        warn "Too many USB devices detected ($usb_count). Possible block during cleanup."
        warn "SUGGESTION: Unplug external HD or non-essential devices before audio startup."
        warn "EXECUTE: sudo /home/$ACTUAL_USER/Progetti/OLMS-Core/Startup2/olms-orchestrator.sh after unplugging devices"
        exit 1
    fi
    
    # Verify processes
    local remaining_audio=$(pgrep -f "jackd|pipewire|pulseaudio" 2>/dev/null || true)
    if [[ -n "$remaining_audio" ]]; then
        warn "Audio processes still active: $remaining_audio"
    else
        log "No active audio processes"
    fi
    
    # Verify sockets (improved) - LIMIT SEARCH TO FIRST 20 RESULTS
    local remaining_sockets=$(find /tmp /dev/shm /var/run /run -name "*jack*" -o -name "*pipewire*" 2>/dev/null | head -20)
    if [[ -n "$remaining_sockets" ]]; then
        # Filter only existing sockets
        local existing_sockets=""
        for socket in $remaining_sockets; do
            if [[ -e "$socket" ]]; then
                existing_sockets="$existing_sockets $socket"
            fi
        done
        
        if [[ -n "$existing_sockets" ]]; then
            warn "Audio sockets still present: $existing_sockets"
        else
            log "No audio sockets present (patterns found but files don't exist)"
        fi
    else
        log "No audio sockets present"
    fi
    
    # Verify devices
    if [[ -d "/dev/snd" ]]; then
        local device_users=$(fuser /dev/snd/* 2>/dev/null || true)
        if [[ -n "$device_users" ]]; then
            warn "Audio devices still in use: $device_users"
        else
            log "Audio devices free"
        fi
    fi
}

# Main function
main() {
    log "=== PHASE 0.2: AUDIO ENVIRONMENT NUCLEAR CLEANUP ==="
    
    kill_audio_processes
    remove_socket_files
    cleanup_shared_memory
    disable_internal_audio
    wait_usb_audio_devices
    reset_audio_hardware
    cleanup_temp_directories
    verify_cleanup
    
    log "Audio environment cleanup completed"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
