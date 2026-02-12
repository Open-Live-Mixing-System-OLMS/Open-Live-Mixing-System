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

# JACK System Reset Script
# Version: 1.0
# Purpose: Quickly restore the JACK system in case of connectivity issues

set -euo pipefail

# Configuration
TARGET_USER="${TARGET_USER:-$(whoami)}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "$(id -u)")
ACTUAL_SOCKET="/dev/shm/jack_olms_0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Terminate all JACK processes
kill_jack_processes() {
    log "Terminating JACK processes..."
    
    # Termina processi jackd
    sudo pkill -f jackd 2>/dev/null || true
    sleep 1
    
    # Verifica che i processi siano terminati
    if pgrep -f jackd >/dev/null 2>&1; then
        warn "Some JACK processes are still active, forced termination..."
        sudo pkill -9 -f jackd 2>/dev/null || true
        sleep 1
    fi
    
    log "JACK processes terminated"
}

# Clean corrupted sockets and links
cleanup_jack_files() {
    log "Cleaning JACK sockets and links..."
    
    # Remove corrupted links
    sudo rm -f /tmp/jack-default_$(id -u)_0 /tmp/jack-olms-$(id -u) 2>/dev/null || true
    sudo rm -rf /dev/shm/jack-0 /tmp/jack-0 /dev/shm/jack_db-0 2>/dev/null || true
    
    # Remove temporary log files
    sudo rm -f /tmp/jack.pid /tmp/jack_connectivity_test.log /tmp/jack_startup.log 2>/dev/null || true
    
    log "JACK files cleaned"
}

# Create necessary symbolic links
create_jack_links() {
    log "Creating JACK symbolic links..."
    
    # Create socket directory if it doesn't exist
    sudo mkdir -p "$ACTUAL_SOCKET"
    sudo chmod -R 777 "$ACTUAL_SOCKET"
    
    # Links to create that point to the real JACK socket
    local links_to_create=(
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
        "/dev/shm/jack-default_${TARGET_UID}_0"
        "/tmp/jack-default_${TARGET_UID}_0"
    )
    
    for link_path in "${links_to_create[@]}"; do
        local link_dir=$(dirname "$link_path")
        sudo mkdir -p "$link_dir"
        
        if [[ ! -L "$link_path" ]]; then
            sudo ln -sfn "$ACTUAL_SOCKET" "$link_path" 2>/dev/null || true
            log "Created link: $link_path -> $ACTUAL_SOCKET"
        else
            log "Link already exists: $link_path"
        fi
    done
    
    # Set correct permissions
    sudo chmod -R 777 /dev/shm/jack-* /tmp/jack-* 2>/dev/null || true
    sudo chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
    
    log "JACK links created and configured"
}

# Verify JACK connectivity
verify_connectivity() {
    log "Verifying JACK connectivity..."
    
    # Test with different paths
    local test_paths=(
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
    )
    
    local connectivity_working=false
    
    for test_path in "${test_paths[@]}"; do
        if [[ -d "$test_path" ]]; then
            if sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="$test_path" jack_lsp >/dev/null 2>&1; then
                log "✅ JACK connectivity OK with path: $test_path"
                connectivity_working=true
                break
            else
                warn "❌ JACK connectivity FAILED with path: $test_path"
            fi
        fi
    done
    
    if [[ "$connectivity_working" == "true" ]]; then
        log "✅ JACK connectivity restored"
        return 0
    else
        warn "⚠️  JACK connectivity still failed"
        return 1
    fi
}

# Start the JACK server
start_jack_server() {
    log "Starting JACK server..."
    
    # Start JACK in background
    sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms jackd -d alsa -d hw:1 -r 48000 -p 1024 -n 2 -s -S >/dev/null 2>&1 &
    local jack_pid=$!
    
    # Wait for JACK to start
    sleep 3
    
    # Verify that JACK is active
    if kill -0 $jack_pid 2>/dev/null; then
        log "✅ JACK server started (PID: $jack_pid)"
        return 0
    else
        error "❌ Unable to start JACK server"
        return 1
    fi
}

# Complete final test
final_test() {
    log "Complete final test..."
    
    # Connectivity test
    if ! verify_connectivity; then
        error "❌ Connectivity test failed"
        return 1
    fi
    
    # jack_lsp test
    if ! sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
        error "❌ jack_lsp test failed"
        return 1
    fi
    
    # jack_control test
    if ! sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms jack_control status >/dev/null 2>&1; then
        error "❌ jack_control test failed"
        return 1
    fi
    
    log "✅ All tests passed"
    return 0
}

# Main function
main() {
    log "=== JACK SYSTEM RESET SCRIPT ==="
    log "Target user: $TARGET_USER (UID: $TARGET_UID)"
    log "Socket directory: $ACTUAL_SOCKET"
    
    # Step 1: Terminate JACK processes
    kill_jack_processes
    
    # Step 2: Clean files
    cleanup_jack_files
    
    # Step 3: Create links
    create_jack_links
    
    # Step 4: Start JACK server
    if ! start_jack_server; then
        error "Unable to start JACK server"
        exit 1
    fi
    
    # Step 5: Final test
    if final_test; then
        log "✅ JACK System Reset completed successfully"
        log "The JACK system is now functional and ready to use"
    else
        error "❌ JACK System Reset failed"
        error "Check logs for further details"
        exit 1
    fi
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi