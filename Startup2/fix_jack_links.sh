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

# JACK Links Fix Script
# Version: 1.0

set -euo pipefail

# Configuration
TARGET_USER="${TARGET_USER:-$(whoami)}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "$(id -u)")
ACTUAL_SOCKET="/dev/shm/jack-olms-0"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Create all necessary symbolic links
create_jack_links() {
    log "Creating complete JACK symbolic links..."
    
    # JACK actually uses the socket: /dev/shm/jack_olms_0 (with underscore)
    local actual_jack_socket="/dev/shm/jack_olms_0"
    
    # Create socket directory if it doesn't exist
    sudo mkdir -p "$actual_jack_socket"
    sudo chmod -R 777 "$actual_jack_socket"
    
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
            sudo ln -sfn "$actual_jack_socket" "$link_path" 2>/dev/null || true
            log "Created link: $link_path -> $actual_jack_socket"
        else
            log "Link already exists: $link_path"
        fi
    done
    
    # Verify all links
    log "Verifying complete links..."
    local all_links=(
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
        "/dev/shm/jack-default_${TARGET_UID}_0"
        "/tmp/jack-default_${TARGET_UID}_0"
    )
    
    local working_links=0
    for link in "${all_links[@]}"; do
        if [[ -L "$link" ]] && [[ -S "$(readlink "$link" 2>/dev/null || echo "")" ]]; then
            log "✓ Working link: $link"
            working_links=$((working_links + 1))
        else
            warn "✗ Non-working link: $link"
        fi
    done
    
    log "Working links: $working_links/${#all_links[@]}"
    
    if [[ $working_links -eq ${#all_links[@]} ]]; then
        log "✅ All JACK links have been created correctly"
        return 0
    else
        warn "⚠️  Some links are not working"
        return 1
    fi
}

# Set correct permissions
set_permissions() {
    log "Setting JACK permissions..."
    
    # Permissions for all socket directories
    sudo chmod -R 777 /dev/shm/jack-* 2>/dev/null || true
    sudo chmod -R 777 /tmp/jack-* 2>/dev/null || true
    sudo chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
    
    log "Permissions set on all socket directories"
}

# Test connectivity after fix
test_connectivity() {
    log "Testing JACK connectivity after fix..."
    
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
        warn "❌ JACK connectivity still failed"
        return 1
    fi
}

# Main function
main() {
    log "=== JACK LINKS FIX SCRIPT ==="
    log "Target user: $TARGET_USER (UID: $TARGET_UID)"
    log "Socket directory: $ACTUAL_SOCKET"
    
    # Create links
    if ! create_jack_links; then
        error "Error creating links"
        exit 1
    fi
    
    # Set permissions
    set_permissions
    
    # Test connectivity
    if test_connectivity; then
        log "✅ Fix completed successfully"
    else
        warn "⚠️  Partial fix - further actions may be needed"
    fi
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
