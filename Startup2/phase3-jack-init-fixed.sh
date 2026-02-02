#!/bin/bash
# Phase 3: JACK Server - Fixed Strategy (No D-Bus Conflicts)
# Versione: 4.0 - The "Clean Connection" Fix
set -euo pipefail

# Environment overrides for non-interactive stability
export JACK_NO_AUDIO_RESERVATION=1
export JACK_DEFAULT_SERVER=olms
export JACK_PROMISCUOUS_SERVER=1

# Variabili d'ambiente per l'approccio "tutto come stesso utente"
export TARGET_USER="francesco_ssh"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export XDG_RUNTIME_DIR="/run/user/1000"
export DISPLAY=":0"
export XAUTHORITY="/home/francesco_ssh/.Xauthority"

# Funzioni di logging
log() { echo -e "\e[32m[$(date '+%H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%H:%M:%S')] WARN:\e[0m $1"; }
error() { echo -e "\e[31m[$(date '+%H:%M:%S')] ERROR:\e[0m $1"; }

BUFFER_SIZE=256   
SAMPLE_RATE=48000
PERIODS=3        

# Enhanced cleanup with better USB device handling
nuclear_cleanup() {
    log "Disattivazione temporanea PipeWire/Pulse via Systemd..."
    systemctl --user stop pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
    
    log "Performing hardware release and socket cleanup..."
    
    # Kill any existing JACK processes
    pkill -9 jackd 2>/dev/null || true
    sleep 1
    
    # Clean up ALL socket directories to avoid UID conflicts
    log "Cleaning up JACK socket directories..."
    rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    
    # Force release of audio devices
    log "Forcing release of audio devices..."
    for device in /dev/snd/controlC1 /dev/snd/pcmC1D0p /dev/snd/pcmC1D0c; do
        if [ -e "$device" ]; then
            log "Releasing device: $device"
            fuser -k "$device" 2>/dev/null || true
        fi
    done
    
    # Resetting the specific USB port found in your logs (1-3)
    # NOTA: Rimossa la scrittura su /sys/bus/usb/devices/1-3/authorized per evitare errori di permesso
    # Il dispositivo verrà gestito dal normale rilevamento ALSA
    log "USB device at 1-3 will be handled by normal ALSA detection"
    
    # Additional USB reset for the entire bus
    # NOTA: Rimossa la scrittura su /sys/bus/usb/devices/*/authorized per evitare errori di permesso
    # Il dispositivo verrà gestito dal normale rilevamento ALSA
    log "USB devices will be handled by normal ALSA detection"
    
    # Final cleanup
    rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    sleep 2
}

# Enhanced socket permission and symlink management
setup_socket_permissions() {
    log "Setting up socket permissions and symbolic links..."
    
    # Wait for JACK to create its socket directory
    sleep 2
    
    # Find the actual socket directory created by JACK
    local actual_socket=""
    
    # Search in /dev/shm first
    for socket_dir in /dev/shm/jack-olms-* /dev/shm/jack-*; do
        if [ -d "$socket_dir" ]; then
            actual_socket="$socket_dir"
            break
        fi
    done
    
    # If not found in /dev/shm, check /tmp
    if [ -z "$actual_socket" ]; then
        for socket_dir in /tmp/jack-olms-* /tmp/jack-*; do
            if [ -d "$socket_dir" ]; then
                actual_socket="$socket_dir"
                log "Found JACK socket directory in /tmp: $actual_socket"
                break
            fi
        done
    fi
    
    # If still not found, create fallback directory in user space
    if [ -z "$actual_socket" ]; then
        log "No JACK socket directory found, creating fallback in user space..."
        actual_socket="/home/francesco_ssh/.local/share/jack-olms"
        mkdir -p "$actual_socket"
        chmod -R 775 "$actual_socket"
        chown francesco_ssh:audio "$actual_socket"
    fi
    
    if [ -n "$actual_socket" ]; then
        log "Using JACK socket directory: $actual_socket"
        
        # Create comprehensive symbolic links for all possible paths
        # This ensures Ardour can find JACK regardless of UID or search path
        local target_user="${TARGET_USER:-francesco_ssh}"
        local target_uid=$(id -u "$target_user" 2>/dev/null || echo "1000")
        
        # Create links for all possible socket paths Ardour might search
        local socket_links=(
            "/dev/shm/jack-olms-${target_uid}"
            "/dev/shm/jack-0/default"
            "/tmp/jack-olms-${target_uid}"
            "/tmp/jack-0/default"
            "/dev/shm/jack-default_${target_uid}_0"
            "/tmp/jack-default_${target_uid}_0"
        )
        
        for link_path in "${socket_links[@]}"; do
            local link_dir=$(dirname "$link_path")
            mkdir -p "$link_dir"
            
            if [ ! -L "$link_path" ]; then
                ln -sfn "$actual_socket" "$link_path" 2>/dev/null || true
                log "Created symbolic link: $actual_socket -> $link_path"
            fi
        done
        
        # Ensure all socket directories have proper permissions
        chmod -R 775 /dev/shm/jack-* 2>/dev/null || true
        chmod -R 775 /tmp/jack-* 2>/dev/null || true
        chmod 775 /dev/shm/jack-shm-registry 2>/dev/null || true
        
        log "Comprehensive socket permissions and links setup complete"
        log "Socket directory: $actual_socket"
        log "Target user: $target_user (UID: $target_uid)"
    else
        error "Failed to establish JACK socket directory"
        return 1
    fi
}

# Enhanced JACK startup with proper permissions - NO D-BUS
start_jack_with_isolation() {
    log "Searching for USB Audio CODEC..."
    
    # Cerchiamo il nome esatto tra parentesi quadre che ALSA riconosce
    local CARD_NAME=$(aplay -l | grep -i "CODEC" | head -n1 | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
    
    if [ -z "$CARD_NAME" ]; then
        error "ERRORE: Scheda USB 'CODEC' non trovata dopo il reset!"
        aplay -l
        exit 1
    fi
    
    # Usiamo il nome simbolico invece del numero (es. hw:CODEC invece di hw:1)
    # Questo risolve il problema se la scheda cambia posizione (da 1 a 2)
    # Basato sul feedback dell'utente, il nome ALSA corretto è "CODEC"
    local TARGET_ALSA_DEVICE="hw:CODEC"
    log "Starting JACK on device: $TARGET_ALSA_DEVICE"
    
    log "Starting JACK with proper permissions (No D-Bus)..."
    
    # Create socket directory with correct permissions BEFORE starting JACK
    local socket_dir="/home/francesco_ssh/.local/share/jack-olms"
    mkdir -p "$socket_dir"
    
    # Set CORRECT permissions: user ownership and group access
    chown francesco_ssh:audio "$socket_dir"
    chmod -R 775 "$socket_dir"
    chmod 775 /dev/shm/jack-shm-registry 2>/dev/null || true
    
    # Ensure audio group has access to all JACK directories
    chown -R francesco_ssh:audio /dev/shm/jack-* 2>/dev/null || true
    chmod -R 775 /dev/shm/jack-* 2>/dev/null || true
    chown -R francesco_ssh:audio /tmp/jack-* 2>/dev/null || true
    chmod -R 775 /tmp/jack-* 2>/dev/null || true
    
    log "Socket directory permissions set: $socket_dir (owner: francesco_ssh:audio, perms: 775)"
    
    # Clean up any existing JACK processes and sockets before starting
    log "Cleaning up existing JACK processes and sockets..."
    pkill -9 jackd 2>/dev/null || true
    sleep 2
    
    # Remove socket files with proper permissions (now allowed by udev rules)
    log "Removing JACK socket files..."
    for socket_file in /dev/shm/jack-* /tmp/jack-*; do
        if [ -e "$socket_file" ]; then
            log "Removing socket file: $socket_file"
            rm -rf "$socket_file" 2>/dev/null || warn "Cannot remove $socket_file (continuing anyway)"
        fi
    done
    
    # Remove JACK shared memory registry
    if [ -e "/dev/shm/jack-shm-registry" ]; then
        log "Removing JACK shared memory registry"
        rm -f "/dev/shm/jack-shm-registry" 2>/dev/null || warn "Cannot remove jack-shm-registry (continuing anyway)"
    fi
    
    # Additional cleanup for any remaining JACK processes
    log "Final JACK cleanup..."
    pkill -9 jackd 2>/dev/null || true
    sleep 3
    
    sleep 1
    
    # Gestione Socket "Hardcore" (Senza Sudo)
    local server_name="olms"
    # Se il socket standard esiste ed è di un altro utente, cambiamo nome al volo
    if [[ -e "/dev/shm/jack_${server_name}_0" ]]; then
        local owner=$(stat -c '%U' "/dev/shm/jack_${server_name}_0")
        if [[ "$owner" != "$(whoami)" ]]; then
            warn "Socket di $owner rilevato. Cambio nome server per evitare collisioni."
            server_name="olms_$(date +%H%M)"
            export JACK_DEFAULT_SERVER="$server_name"
        fi
    fi
    
    # Launch JACK as user with proper environment - NO D-BUS
    local jack_command=(
        env 
        JACK_NO_AUDIO_RESERVATION=1 
        JACK_DEFAULT_SERVER="$server_name"
        JACK_PROMISCUOUS_SERVER=1
        jackd 
        -R -P 80 
        -n olms 
        -d alsa 
        -d "$TARGET_ALSA_DEVICE" 
        -r "$SAMPLE_RATE" 
        -p "$BUFFER_SIZE" 
        -n 2
    )
    
    log "Executing: ${jack_command[*]}"
    
    # Start JACK in background
    "${jack_command[@]}" > /tmp/jack_startup.log 2>&1 &
    local pid=$!
    
    # Save PID for monitoring
    echo "$pid" > /tmp/jack.pid
    
    log "JACK started with PID: $pid"
    
    # Verify permissions are still correct after JACK startup
    sleep 2
    log "Verifying socket permissions after JACK startup..."
    ls -la "$socket_dir" 2>/dev/null || log "Socket directory not accessible"
    
    # Fix permissions permanently to prevent client connection issues
    log "Fixing socket permissions permanently..."
    chmod -R 777 /dev/shm/jack-* /tmp/jack-* 2>/dev/null || true
    chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
    
    return 0
}

# Enhanced monitoring and verification using JACK connectivity test
verify_jack_stability() {
    local pid=$1
    local max_attempts=10
    local attempt=1
    
    log "Verifying JACK stability (PID: $pid)..."
    
    # Wait for JACK to fully initialize
    sleep 5
    
    while [ $attempt -le $max_attempts ]; do
        if ! ps -p $pid > /dev/null; then
            warn "JACK process died during verification (attempt $attempt/$max_attempts)"
            return 1
        fi
        
        # Test connectivity with jack_lsp directly (no D-Bus)
        if env JACK_DEFAULT_SERVER="olms" jack_lsp >/dev/null 2>&1; then
            log "✅ JACK connectivity verified with jack_lsp (attempt $attempt/$max_attempts)"
            
            # Additional verification: check for actual ports
            local port_count=$(env JACK_DEFAULT_SERVER="olms" jack_lsp 2>/dev/null | wc -l || echo "0")
            if [ "$port_count" -gt 0 ]; then
                log "✅ JACK ports detected: $port_count ports available"
                log "Port list:"
                env JACK_DEFAULT_SERVER="olms" jack_lsp 2>/dev/null | while read -r port; do
                    log "  $port"
                done
                return 0
            else
                warn "JACK server running but no ports detected (attempt $attempt/$max_attempts)"
            fi
        else
            warn "JACK connectivity test failed with jack_lsp (attempt $attempt/$max_attempts)"
            warn "Debug: Available JACK servers:"
            if env JACK_DEFAULT_SERVER="olms" jack_lsp >/dev/null 2>&1; then
                env JACK_DEFAULT_SERVER="olms" jack_lsp 2>&1 | head -5
            else
                warn "jack_lsp not available or failed"
            fi
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log "Retrying JACK verification in 2 seconds..."
            sleep 2
        fi
        
        attempt=$((attempt + 1))
    done
    
    warn "JACK verification failed after $max_attempts attempts"
    warn "JACK may be running but unstable. Check /tmp/jack_startup.log for details"
    return 1
}

# Signal handling to prevent premature termination
setup_signal_handling() {
    log "Setting up signal handling to prevent premature termination..."
    
    # Trap common signals that could kill JACK
    trap 'warn "Received signal, attempting graceful shutdown..."; cleanup_and_exit' SIGINT SIGTERM
    
    cleanup_and_exit() {
        log "Cleaning up JACK processes..."
        pkill -9 jackd 2>/dev/null || true
        rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
        exit 1
    }
}

main() {
    log "=== JACK INITIALIZATION: CLEAN CONNECTION STRATEGY ==="
    log "The 'Clean Connection' Solution - No D-Bus Conflicts"
    
    # Setup signal handling
    setup_signal_handling
    
    # Perform nuclear cleanup
    nuclear_cleanup
    
    # Start JACK with proper isolation
    start_jack_with_isolation
    
    local jack_pid=$(cat /tmp/jack.pid 2>/dev/null || echo "")
    
    if [ -z "$jack_pid" ]; then
        error "Could not determine JACK PID"
        exit 1
    fi
    
    # Setup socket permissions and symbolic links
    setup_socket_permissions
    
    # Verify JACK stability
    if verify_jack_stability "$jack_pid"; then
        log "✅ JACK INITIALIZATION COMPLETE - STABLE AND READY"
        log "Server name: olms"
        log "PID: $jack_pid"
        log "Socket directory: $(find /dev/shm -name "jack-olms-*" -type d 2>/dev/null | head -1 || echo "Not found")"
        
        # Final connectivity test for Ardour compatibility
        log "Testing Ardour compatibility..."
        if -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | grep -q "system"; then
            log "✅ Ardour compatibility verified - system ports available"
        else
            warn "Ardour compatibility test inconclusive - manual verification recommended"
        fi
        
        exit 0
    else
        warn "JACK initialization completed but with stability issues"
        warn "Check /tmp/jack_startup.log for detailed error information"
        warn "Manual intervention may be required"
        exit 1
    fi
}

# Execute main function
main "$@"