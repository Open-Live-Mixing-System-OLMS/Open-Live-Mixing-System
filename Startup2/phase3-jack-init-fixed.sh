#!/bin/bash
# Phase 3: JACK Server - Fixed Strategy (No D-Bus Conflicts)
# Versione: 4.0 - The "Clean Connection" Fix
set -euo pipefail

# Environment overrides for non-interactive stability
export JACK_NO_AUDIO_RESERVATION=1
export JACK_DEFAULT_SERVER=olms
export JACK_PROMISCUOUS_SERVER=1

TARGET_HW="hw:1" 
BUFFER_SIZE=256   
SAMPLE_RATE=48000
PERIODS=3        

log() { echo -e "\e[32m[$(date '+%H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%H:%M:%S')] WARN:\e[0m $1"; }
error() { echo -e "\e[31m[$(date '+%H:%M:%S')] ERROR:\e[0m $1"; }

# Enhanced cleanup with better USB device handling
nuclear_cleanup() {
    log "Performing hardware release and socket cleanup..."
    
    # Kill any existing JACK processes
    sudo pkill -9 jackd 2>/dev/null || true
    sleep 1
    
    # Clean up ALL socket directories to avoid UID conflicts
    log "Cleaning up JACK socket directories..."
    sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    
    # Force release of audio devices
    log "Forcing release of audio devices..."
    for device in /dev/snd/controlC1 /dev/snd/pcmC1D0p /dev/snd/pcmC1D0c; do
        if [ -e "$device" ]; then
            log "Releasing device: $device"
            sudo fuser -k "$device" 2>/dev/null || true
        fi
    done
    
    # Resetting the specific USB port found in your logs (1-3)
    if [ -f /sys/bus/usb/devices/1-3/authorized ]; then
        log "Resetting USB device at 1-3"
        echo 0 | sudo tee /sys/bus/usb/devices/1-3/authorized >/dev/null
        sleep 2
        echo 1 | sudo tee /sys/bus/usb/devices/1-3/authorized >/dev/null
        log "Waiting 5s for ALSA to settle..."
        sleep 5 # Critical: gives the kernel time to rebuild device nodes
    fi
    
    # Additional USB reset for the entire bus
    log "Resetting USB bus for audio devices..."
    for usb_device in /sys/bus/usb/devices/*; do
        if [ -f "$usb_device/product" ]; then
            local product=$(cat "$usb_device/product" 2>/dev/null || true)
            if echo "$product" | grep -iq "audio\|codec\|ti\|burr"; then
                log "Resetting USB audio device: $usb_device ($product)"
                if [ -f "$usb_device/authorized" ]; then
                    echo 0 | sudo tee "$usb_device/authorized" >/dev/null
                    sleep 1
                    echo 1 | sudo tee "$usb_device/authorized" >/dev/null
                fi
            fi
        fi
    done
    
    # Final cleanup
    sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
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
    
    # If still not found, create fallback directory
    if [ -z "$actual_socket" ]; then
        log "No JACK socket directory found, creating fallback..."
        actual_socket="/dev/shm/jack-olms-0"
        sudo mkdir -p "$actual_socket"
        sudo chmod -R 777 "$actual_socket"
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
            sudo mkdir -p "$link_dir"
            
            if [ ! -L "$link_path" ]; then
                sudo ln -sfn "$actual_socket" "$link_path" 2>/dev/null || true
                log "Created symbolic link: $actual_socket -> $link_path"
            fi
        done
        
        # Ensure all socket directories have proper permissions
        sudo chmod -R 777 /dev/shm/jack-* 2>/dev/null || true
        sudo chmod -R 777 /tmp/jack-* 2>/dev/null || true
        sudo chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
        
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
    log "Starting JACK with proper permissions (No D-Bus)..."
    
    # Create socket directory with correct permissions BEFORE starting JACK
    local socket_dir="/dev/shm/jack-olms-0"
    sudo mkdir -p "$socket_dir"
    
    # Set CORRECT permissions: user ownership and group access
    sudo chown francesco_ssh:audio "$socket_dir"
    sudo chmod -R 775 "$socket_dir"
    sudo chmod 775 /dev/shm/jack-shm-registry 2>/dev/null || true
    
    # Ensure audio group has access to all JACK directories
    sudo chown -R francesco_ssh:audio /dev/shm/jack-* 2>/dev/null || true
    sudo chmod -R 775 /dev/shm/jack-* 2>/dev/null || true
    sudo chown -R francesco_ssh:audio /tmp/jack-* 2>/dev/null || true
    sudo chmod -R 775 /tmp/jack-* 2>/dev/null || true
    
    log "Socket directory permissions set: $socket_dir (owner: francesco_ssh:audio, perms: 775)"
    
    # Launch JACK as user with proper environment - NO D-BUS
    local jack_command=(
        sudo -u francesco_ssh env 
        JACK_NO_AUDIO_RESERVATION=1 
        JACK_DEFAULT_SERVER=olms
        JACK_PROMISCUOUS_SERVER=1
        jackd 
        -R -P 80 
        -n olms 
        -d alsa 
        -d "$TARGET_HW" 
        -r "$SAMPLE_RATE" 
        -p "$BUFFER_SIZE" 
        -n "$PERIODS" 
        -s
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
    sudo chmod -R 777 /dev/shm/jack-* /tmp/jack-* 2>/dev/null || true
    sudo chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
    
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
        if sudo -u francesco_ssh -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
            log "✅ JACK connectivity verified with jack_lsp (attempt $attempt/$max_attempts)"
            
            # Additional verification: check for actual ports
            local port_count=$(sudo -u francesco_ssh -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | wc -l || echo "0")
            if [ "$port_count" -gt 0 ]; then
                log "✅ JACK ports detected: $port_count ports available"
                log "Port list:"
                sudo -u francesco_ssh -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | while read -r port; do
                    log "  $port"
                done
                return 0
            else
                warn "JACK server running but no ports detected (attempt $attempt/$max_attempts)"
            fi
        else
            warn "JACK connectivity test failed with jack_lsp (attempt $attempt/$max_attempts)"
            warn "Debug: Available JACK servers:"
            if sudo -u francesco_ssh -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
                sudo -u francesco_ssh -E JACK_DEFAULT_SERVER=olms jack_lsp 2>&1 | head -5
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
        sudo pkill -9 jackd 2>/dev/null || true
        sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
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
        if sudo -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | grep -q "system"; then
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