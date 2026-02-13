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

# JACK Connectivity Diagnostic Script
# Version: 1.0

# Initialize OLMS paths for relative path support
init_olms_paths() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 1. Direct detection from Startup2 directory
    if [[ "$script_dir" == */Startup2 ]]; then
        local olms_core_root="$(dirname "$script_dir")"
        export OLMS_CORE_ROOT="$olms_core_root"
        export OLMS_ENGINE_DIR="$olms_core_root/engine"
        export OLMS_CONFIG_DIR="$olms_core_root/config"
        export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
        export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
        export OLMS_TEST_DIR="$olms_core_root/test"
        export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
        export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
        log "OLMS paths initialized from Startup2 directory: $olms_core_root"
        return 0
    fi
    
    # 2. Search for OLMS marker files
    local search_dirs=("$HOME" "/opt" "/usr/local")
    for search_dir in "${search_dirs[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' potential_root; do
                if [[ -f "$potential_root/OLMS_specs.md" ]] && [[ -f "$potential_root/OLMS_STARTUP_SPECIFICATION.md" ]]; then
                    export OLMS_CORE_ROOT="$potential_root"
                    export OLMS_ENGINE_DIR="$olms_core_root/engine"
                    export OLMS_CONFIG_DIR="$olms_core_root/config"
                    export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
                    export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
                    export OLMS_TEST_DIR="$olms_core_root/test"
                    export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
                    export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
                    log "OLMS paths initialized from marker files: $olms_core_root"
                    return 0
                fi
            done < <(find "$search_dir" -maxdepth 3 -type d -name "OLMS-Core" -print0 2>/dev/null)
        fi
    done
    
    # 3. Fallback to standard locations
    if [[ -d "$HOME/Progetti/OLMS-Core" ]]; then
        export OLMS_CORE_ROOT="$HOME/Progetti/OLMS-Core"
        export OLMS_ENGINE_DIR="$olms_core_root/engine"
        export OLMS_CONFIG_DIR="$olms_core_root/config"
        export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
        export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
        export OLMS_TEST_DIR="$olms_core_root/test"
        export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
        export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
        log "OLMS paths initialized from fallback location: $olms_core_root"
        return 0
    fi
    
    # 4. Final fallback - search recursively in home directory
    if [[ -d "$HOME" ]]; then
        while IFS= read -r -d '' potential_root; do
            if [[ -f "$potential_root/OLMS_specs.md" ]] && [[ -f "$potential_root/OLMS_STARTUP_SPECIFICATION.md" ]]; then
                export OLMS_CORE_ROOT="$potential_root"
                export OLMS_ENGINE_DIR="$olms_core_root/engine"
                export OLMS_CONFIG_DIR="$olms_core_root/config"
                export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
                export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
                export OLMS_TEST_DIR="$olms_core_root/test"
                export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
                export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
                log "OLMS paths initialized from recursive search: $olms_core_root"
                return 0
            fi
        done < <(find "$HOME" -maxdepth 4 -type d -name "OLMS-Core" -print0 2>/dev/null)
    fi
    
    warn "OLMS-Core directory not found, using current directory"
    export OLMS_CORE_ROOT="$(pwd)"
    export OLMS_ENGINE_DIR="$olms_core_root/engine"
    export OLMS_CONFIG_DIR="$olms_core_root/config"
    export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
    export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
    export OLMS_TEST_DIR="$olms_core_root/test"
    export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
    export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
    return 1
}

get_olms_path() {
    local path_type="$1"
    
    case "$path_type" in
        "core_root") echo "$OLMS_CORE_ROOT" ;;
        "engine_dir") echo "$OLMS_ENGINE_DIR" ;;
        "config_dir") echo "$OLMS_CONFIG_DIR" ;;
        "startup_dir") echo "$OLMS_STARTUP_DIR" ;;
        "systemd_dir") echo "$OLMS_SYSTEMD_DIR" ;;
        "test_dir") echo "$OLMS_TEST_DIR" ;;
        "ardour_session_path") echo "$OLMS_ARDOUR_SESSION_PATH" ;;
        "ardour_session_dir") echo "$OLMS_ARDOUR_SESSION_DIR" ;;
        *) warn "Unknown path type: $path_type"; echo "$OLMS_CORE_ROOT" ;;
    esac
}

# Initialize paths at the beginning
init_olms_paths

set -euo pipefail

# Configuration
LOG_FILE="/tmp/jack_connectivity_test.log"
TARGET_USER="${TARGET_USER:-$(whoami)}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "$(id -u)")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Test 1: Verify JACK processes
test_jack_processes() {
    log "=== TEST 1: Verify JACK processes ==="
    
    local jack_pids=$(pgrep -f "jackd" 2>/dev/null || true)
    if [[ -n "$jack_pids" ]]; then
        log "JACK processes found: $jack_pids"
        for pid in $jack_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                log "PID $pid: active"
                local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo "unknown")
                log "  Command: $cmd"
            else
                warn "PID $pid: not active"
            fi
        done
        return 0
    else
        warn "No JACK processes found"
        return 1
    fi
}

# Test 2: Verify JACK sockets
test_jack_sockets() {
    log "=== TEST 2: Verify JACK sockets ==="
    
    local socket_found=false
    local socket_dirs=(
        "/dev/shm/jack-olms-*"
        "/dev/shm/jack-*"
        "/tmp/jack-olms-*"
        "/tmp/jack-*"
    )
    
    for socket_pattern in "${socket_dirs[@]}"; do
        for socket_dir in $socket_pattern; do
            if [[ -d "$socket_dir" ]]; then
                log "JACK socket found: $socket_dir"
                socket_found=true
                
                # Verify permissions
                local perms=$(ls -ld "$socket_dir" | awk '{print $1}')
                log "  Permissions: $perms"
                
                # Verify content
                if [[ -d "$socket_dir" ]]; then
                    local contents=$(ls -la "$socket_dir" 2>/dev/null || echo "empty")
                    log "  Content: $contents"
                fi
            fi
        done
    done
    
    if [[ "$socket_found" == "false" ]]; then
        warn "No JACK socket found"
        return 1
    fi
    
    return 0
}

# Test 3: Verify socket symbolic links
test_socket_links() {
    log "=== TEST 3: Verify socket symbolic links ==="
    
    local link_paths=(
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
        "/dev/shm/jack-default_${TARGET_UID}_0"
        "/tmp/jack-default_${TARGET_UID}_0"
    )
    
    local links_working=0
    local total_links=${#link_paths[@]}
    
    for link_path in "${link_paths[@]}"; do
        if [[ -L "$link_path" ]]; then
            local target=$(readlink "$link_path" 2>/dev/null || echo "unknown")
            if [[ -d "$target" ]]; then
                log "Link OK: $link_path -> $target"
                links_working=$((links_working + 1))
            else
                warn "Broken link: $link_path -> $target"
            fi
        else
            warn "Link does not exist: $link_path"
        fi
    done
    
    log "Symbolic links: $links_working/$total_links working"
    
    if [[ $links_working -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 4: Test JACK connectivity
test_jack_connectivity() {
    log "=== TEST 4: Test JACK connectivity ==="
    
    # Test with jack_lsp
    if command -v jack_lsp >/dev/null 2>&1; then
        log "Testing connectivity with jack_lsp..."
        
        # Test as root
        if sudo -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="/dev/shm/jack-olms-0" jack_lsp >/dev/null 2>&1; then
            log "✅ JACK connectivity as root: OK"
        else
            warn "❌ JACK connectivity as root: FAILED"
        fi
        
        # Test as target user
        if sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="/dev/shm/jack-olms-0" jack_lsp >/dev/null 2>&1; then
            log "✅ JACK connectivity as user $TARGET_USER: OK"
        else
            warn "❌ JACK connectivity as user $TARGET_USER: FAILED"
        fi
        
        # Test with different session paths
        local test_paths=(
            "/dev/shm/jack-olms-0"
            "/dev/shm/jack-olms-${TARGET_UID}"
            "/tmp/jack-olms-0"
            "/tmp/jack-olms-${TARGET_UID}"
        )
        
        for test_path in "${test_paths[@]}"; do
            if [[ -d "$test_path" ]]; then
                if sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="$test_path" jack_lsp >/dev/null 2>&1; then
                    log "✅ JACK connectivity with path $test_path: OK"
                else
                    warn "❌ JACK connectivity with path $test_path: FAILED"
                fi
            fi
        done
        
        return 0
    else
        warn "jack_lsp not available"
        return 1
    fi
}

# Test 5: Test Ardour connectivity
test_ardour_connectivity() {
    log "=== TEST 5: Test Ardour connectivity ==="
    
    # Verify if Ardour is running
    local ardour_pids=$(pgrep -f "ardour" 2>/dev/null || true)
    if [[ -n "$ardour_pids" ]]; then
        log "Ardour processes found: $ardour_pids"
        
        # Test Ardour ports
        if command -v jack_lsp >/dev/null 2>&1; then
            local ardour_ports=$(jack_lsp 2>/dev/null | grep -i ardour || true)
            if [[ -n "$ardour_ports" ]]; then
                log "Ardour ports found:"
                echo "$ardour_ports" | while read -r port; do
                    log "  $port"
                done
                return 0
            else
                warn "No Ardour ports found"
                return 1
            fi
        fi
    else
        warn "No Ardour processes running"
        return 1
    fi
}

# Test 6: Verify permissions and access
test_permissions() {
    log "=== TEST 6: Verify permissions and access ==="
    
    # Verify socket permissions
    local socket_dirs=(
        "/dev/shm/jack-*"
        "/tmp/jack-*"
    )
    
    for socket_pattern in "${socket_dirs[@]}"; do
        for socket_dir in $socket_pattern; do
            if [[ -d "$socket_dir" ]]; then
                local perms=$(ls -ld "$socket_dir" | awk '{print $1}')
                log "Socket $socket_dir: permissions $perms"
                
                # Verify if user can access
                if sudo -u "$TARGET_USER" ls "$socket_dir" >/dev/null 2>&1; then
                    log "  User $TARGET_USER: access allowed"
                else
                    warn "  User $TARGET_USER: access denied"
                fi
            fi
        done
    done
    
    # Verify jack-shm-registry
    if [[ -f "/dev/shm/jack-shm-registry" ]]; then
        local perms=$(ls -l "/dev/shm/jack-shm-registry" | awk '{print $1}')
        log "jack-shm-registry: permissions $perms"
    fi
}

# Test 7: Verify environment variables
test_environment_variables() {
    log "=== TEST 7: Verify environment variables ==="
    
    local env_vars=(
        "JACK_DEFAULT_SERVER"
        "JACK_NO_START_SERVER"
        "JACK_PROMISCUOUS_SERVER"
        "JACK_SESSION_DIR"
        "JACK_NO_AUDIO_RESERVATION"
    )
    
    for var in "${env_vars[@]}"; do
        local value=$(printenv "$var" 2>/dev/null || echo "not set")
        log "$var: $value"
    done
    
    # Verify variables for target user
    log "Environment variables for user $TARGET_USER:"
    sudo -u "$TARGET_USER" env | grep -E "^JACK_" | while read -r line; do
        log "  $line"
    done
}

# Test 8: Verify X11 access
test_x11_access() {
    log "=== TEST 8: Verify X11 access ==="
    
    # Verify DISPLAY
    local display="${DISPLAY:-:0}"
    log "DISPLAY: $display"
    
    # Verify XAUTHORITY
    local xauth_file="/home/${TARGET_USER}/.Xauthority"
    if [[ -f "$xauth_file" ]]; then
        log "XAUTHORITY: $xauth_file (exists)"
        if [[ -r "$xauth_file" ]]; then
            log "XAUTHORITY: readable"
        else
            warn "XAUTHORITY: not readable"
        fi
    else
        warn "XAUTHORITY: file does not exist"
    fi
    
    # Verify X11 connection
    if command -v xdpyinfo >/dev/null 2>&1; then
        if xdpyinfo -display "$display" >/dev/null 2>&1; then
            log "X11 connection: OK"
        else
            warn "X11 connection: FAILED"
        fi
    fi
}

# Final report
generate_report() {
    log "=== FINAL REPORT ==="
    
    local total_tests=8
    local passed_tests=0
    
    # Count passed tests (based on logs)
    local passed_count=$(grep -c "✅" "$LOG_FILE" 2>/dev/null || echo "0")
    local failed_count=$(grep -c "❌" "$LOG_FILE" 2>/dev/null || echo "0")
    local warning_count=$(grep -c "WARNING:" "$LOG_FILE" 2>/dev/null || echo "0")
    
    log "Test summary:"
    log "  Tests completed: $total_tests"
    log "  Tests passed: $passed_count"
    log "  Tests failed: $failed_count"
    log "  Warnings: $warning_count"
    
    if [[ $failed_count -eq 0 ]]; then
        log "✅ All tests passed - JACK connectivity OK"
    else
        warn "❌ Some tests failed - JACK connectivity issues"
    fi
    
    if [[ $warning_count -gt 5 ]]; then
        warn "⚠️  Numerous warnings detected - Check log for details"
    fi
    
    log "Detailed log: $LOG_FILE"
}

# Main function
main() {
    log "=== JACK CONNECTIVITY DIAGNOSTIC SCRIPT ==="
    log "Target user: $TARGET_USER (UID: $TARGET_UID)"
    log "Timestamp: $(date)"
    
    # Run all tests
    test_jack_processes
    test_jack_sockets
    test_socket_links
    test_jack_connectivity
    test_ardour_connectivity
    test_permissions
    test_environment_variables
    test_x11_access
    
    # Generate report
    generate_report
    
    log "Diagnostic script completed"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
