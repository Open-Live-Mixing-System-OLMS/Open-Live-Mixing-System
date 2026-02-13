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
# Test script for JACK Fixed-Path Socket Strategy
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

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $1"
}

# Test 1: Socket Path and Permissions
test_socket_permissions() {
    log "=== TEST 1: Socket Path and Permissions ==="
    
    # Find JACK socket directory created by JACK
    local socket_dirs=($(find /dev/shm -name "jack-*" -type d 2>/dev/null || true))
    
    if [ ${#socket_dirs[@]} -eq 0 ]; then
        warn "No JACK socket directory found"
        return 1
    fi
    
    for socket_dir in "${socket_dirs[@]}"; do
        log "Verifying socket directory: $socket_dir"
        
        # Check permissions
        local perms=$(stat -c "%a" "$socket_dir" 2>/dev/null || echo "unknown")
        if [ "$perms" = "777" ]; then
            log "✅ Correct permissions: $perms"
        else
            warn "Non-optimal permissions: $perms (expected: 777)"
        fi
        
        # Check content
        local socket_files=$(find "$socket_dir" -type s 2>/dev/null | wc -l)
        if [ "$socket_files" -gt 0 ]; then
            log "✅ Socket files found: $socket_files"
        else
            warn "No socket file found in $socket_dir"
        fi
    done
    
    # Verify symbolic links
    local user_uid=$(id -u "${TARGET_USER:-$(whoami)}" 2>/dev/null || echo "$(id -u)")
    local user_socket="/dev/shm/jack-olms-${user_uid}"
    local default_socket="/dev/shm/jack-0/default"
    
    if [ -L "$user_socket" ]; then
        log "✅ User symbolic link found: $user_socket"
    else
        warn "User symbolic link missing: $user_socket"
    fi
    
    if [ -L "$default_socket" ]; then
        log "✅ Default symbolic link found: $default_socket"
    else
        warn "Default symbolic link missing: $default_socket"
    fi
    
    return 0
}

# Test 2: JACK Connectivity
test_jack_connectivity() {
    log "=== TEST 2: JACK Connectivity ==="
    
    # Test base connectivity
    if sudo -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
        log "✅ JACK connectivity base test passed"
    else
        warn "JACK connectivity base test failed"
        return 1
    fi
    
    # Test with specific user
    local target_user="${TARGET_USER:-$(whoami)}"
    if sudo -u "$target_user" -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
        log "✅ JACK connectivity user test passed for $target_user"
    else
        warn "JACK connectivity user test failed for $target_user"
    fi
    
    # Count available ports
    local port_count=$(sudo -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | wc -l || echo "0")
    if [ "$port_count" -gt 0 ]; then
        log "✅ Available JACK ports: $port_count"
    else
        warn "No JACK ports available"
    fi
    
    return 0
}

# Test 3: Process Stability
test_process_stability() {
    log "=== TEST 3: Process Stability ==="
    
    # Verify JACK PID
    local jack_pid=$(cat /tmp/jack.pid 2>/dev/null || echo "")
    if [ -n "$jack_pid" ] && kill -0 "$jack_pid" 2>/dev/null; then
        log "✅ Active JACK PID: $jack_pid"
        
        # Check process status
        local proc_status=$(ps -p "$jack_pid" -o state --no-headers 2>/dev/null || echo "unknown")
        if [ "$proc_status" = "S" ] || [ "$proc_status" = "R" ]; then
            log "✅ JACK process status: $proc_status (running/sleeping)"
        else
            warn "JACK process status: $proc_status"
        fi
    else
        warn "JACK PID not active or not found"
        return 1
    fi
    
    # Verify absence of termination signals
    local signal_count=$(grep -c "SIGINT\|SIGTERM\|killed" /tmp/jack_startup.log 2>/dev/null || echo "0")
    if [[ "$signal_count" == *"0"* ]]; then
        log "✅ No termination signals detected"
    else
        warn "Detected $signal_count termination signals in /tmp/jack_startup.log"
    fi
    
    return 0
}

# Test 4: Ardour Integration
test_ardour_integration() {
    log "=== TEST 4: Ardour Integration ==="
    
    # Verify Ardour PID
    local ardour_pid=$(cat /tmp/ardour.pid 2>/dev/null || echo "")
    if [ -n "$ardour_pid" ] && kill -0 "$ardour_pid" 2>/dev/null; then
        log "✅ Active Ardour PID: $ardour_pid"
    else
        warn "Ardour PID not active or not found"
        return 1
    fi
    
    # Verify Ardour ports
    local ardour_ports=$(sudo -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | grep -i ardour | wc -l 2>/dev/null || echo "0")
    if [ "$ardour_ports" -gt 0 ]; then
        log "✅ Found Ardour ports: $ardour_ports"
    else
        warn "No Ardour ports found"
    fi
    
    # Verify audio processes
    local audio_processes=$(pgrep -f "ardour|jack" 2>/dev/null | wc -l 2>/dev/null || echo "0")
    if [ "$audio_processes" -gt 0 ]; then
        log "✅ Active audio processes: $audio_processes"
    else
        warn "No active audio processes"
    fi
    
    return 0
}

# Test 5: D-Bus Isolation
test_dbus_isolation() {
    log "=== TEST 5: D-Bus Isolation ==="
    
    # Check if dbus-run-session is running
    local dbus_session=$(pgrep -f "dbus-run-session" 2>/dev/null | wc -l 2>/dev/null || echo "0")
    if [ "$dbus_session" -gt 0 ]; then
        log "✅ D-Bus session isolation active: $dbus_session processes"
    else
        warn "D-Bus session isolation not detected"
    fi
    
    # Verify that JACK is not connected to system D-Bus
    local jack_dbus=$(ps aux | grep jackd | grep -v grep | grep -c "dbus" 2>/dev/null || echo "0")
    if [ "$jack_dbus" -eq 0 ]; then
        log "✅ JACK isolated from system D-Bus"
    else
        warn "JACK might be connected to system D-Bus"
    fi
    
    return 0
}

# Complete test
run_all_tests() {
    log "=== JACK STABILITY TEST SUITE ==="
    log "Fixed-Path Socket Strategy Verification"
    log ""
    
    local tests_passed=0
    local total_tests=5
    
    # Run all tests
    if test_socket_permissions; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_jack_connectivity; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_process_stability; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_ardour_integration; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_dbus_isolation; then
        tests_passed=$((tests_passed + 1))
    fi
    
    # Test summary
    log ""
    log "=== TEST SUMMARY ==="
    log "Test passed: $tests_passed/$total_tests"
    
    if [ $tests_passed -eq $total_tests ]; then
        log "✅ ALL TESTS PASSED - System stable"
        return 0
    else
        warn "⚠️  SOME TESTS FAILED - Check issues"
        return 1
    fi
}

# Main function
main() {
    # Set environment variables
    export JACK_DEFAULT_SERVER="olms"
    export TARGET_USER="${TARGET_USER:-$(whoami)}"
    
    # Run tests
    run_all_tests
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
