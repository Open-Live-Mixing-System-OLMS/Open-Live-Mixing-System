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

# Phase 4: X11 Environment & Display Management
# Version: 2.0

# Initialize OLMS paths for relative path support
init_olms_paths() {
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 1. Direct detection from Startup2 directory
    if [[ "$script_dir" == */Startup2 ]]; then
        olms_core_root="$(dirname "$script_dir")"
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

# If LOG_FILE is not passed by the orchestrator, use a safe fallback for the user
LOG_FILE="${LOG_FILE:-/tmp/olms-phase4-${USER}.log}"

XAUTH_FILE=""
XDG_RUNTIME_DIR=""
DISPLAY=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions (moved to the beginning to avoid "command not found")
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

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Environment variables for the "all as same user" approach
# Use variables set by the orchestrator
export TARGET_USER="${TARGET_USER:-$(whoami)}"
export TARGET_UID="${TARGET_UID:-$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
export DISPLAY=":0"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export JACK_DEFAULT_SERVER="olms"
export JACK_NO_START_SERVER=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_SESSION_DIR="/dev/shm/jack-olms-0"

# Explicit addition to solve X11 problems
log "Explicit configuration of DISPLAY and XAUTHORITY to solve X11 problems..."
export DISPLAY=":0"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
log "DISPLAY set to: $DISPLAY"
log "XAUTHORITY set to: $XAUTHORITY"

# Advanced display detection
detect_display() {
    log "Advanced display detection..."
    
    # Method 1: Socket files
    log "Method 1: Searching X11 socket files..."
    for i in {0..9}; do
        local socket="/tmp/.X11-unix/X$i"
        if [[ -S "$socket" ]]; then
            DISPLAY=":$i"
            log "X11 socket found: $socket -> DISPLAY=$DISPLAY"
            return 0
        fi
    done
    
    # Method 2: xauth entries
    log "Method 2: Detecting xauth entries..."
    if command -v xauth >/dev/null 2>&1; then
        local xauth_entries=$(xauth list 2>/dev/null || true)
        if [[ -n "$xauth_entries" ]]; then
            log "Xauth entries found:"
            echo "$xauth_entries" | while read -r entry; do
                log "  $entry"
            done
            
            # Extract display number
            local display_from_xauth=$(echo "$xauth_entries" | head -1 | awk '{print $1}' | grep -oE ':[0-9]+' || true)
            if [[ -n "$display_from_xauth" ]]; then
                DISPLAY="$display_from_xauth"
                log "DISPLAY extracted from xauth: $DISPLAY"
                return 0
            fi
        fi
    fi
    
    # Method 3: Common values
    log "Method 3: Trying common values..."
    local common_displays=(":0" ":1" ":2" ":3")
    for display in "${common_displays[@]}"; do
        if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
            DISPLAY="$display"
            log "DISPLAY found: $DISPLAY"
            return 0
        fi
    done
    
    # Method 4: Wayland/XWayland
    log "Method 4: Detecting Wayland/XWayland..."
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
        log "Wayland session detected"
        
        # Fallback XWayland
        local xwayland_displays=(":0" ":1" ":2")
        for display in "${xwayland_displays[@]}"; do
            if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
                DISPLAY="$display"
                log "XWayland DISPLAY found: $DISPLAY"
                return 0
            fi
        done
    fi
    
    # Method 5: Nested environments (VNC, X2Go, etc.)
    log "Method 5: Detecting nested environments..."
    local nested_displays=(":10" ":11" ":12" ":20" ":21")
    for display in "${nested_displays[@]}"; do
        if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
            DISPLAY="$display"
            log "Nested environment found: $DISPLAY"
            return 0
        fi
    done
    
    # Method 6: Detection from active processes
    if detect_display_from_processes; then
        return 0
    fi
    
    warn "No X11 display detected"
    return 1
}

# Method 6: Detection display from active processes
detect_display_from_processes() {
    log "Method 6: Detection display from active processes..."
    
    # Search for active X11 processes
    local x_processes=$(ps aux | grep -E "(Xorg|X11|Xwayland)" | grep -v grep || true)
    if [[ -n "$x_processes" ]]; then
        log "X11 processes found:"
        echo "$x_processes" | while read -r line; do
            log "  $line"
        done
        
        # Extract display from processes
        local display_from_proc=$(echo "$x_processes" | grep -oE ':[0-9]+' | head -1 || true)
        if [[ -n "$display_from_proc" ]]; then
            DISPLAY="$display_from_proc"
            log "DISPLAY extracted from processes: $DISPLAY"
            return 0
        fi
    fi
    
    # Search for desktop/window manager processes
    local wm_processes=$(ps aux | grep -E "(gnome|kde|xfce|mate|cinnamon|lxde|openbox|i3|fluxbox)" | grep -v grep || true)
    if [[ -n "$wm_processes" ]]; then
        log "Window manager processes found:"
        echo "$wm_processes" | while read -r line; do
            log "  $line"
        done
        
        # Try common displays for desktop environments
        local desktop_displays=(":0" ":1")
        for display in "${desktop_displays[@]}"; do
            if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
                DISPLAY="$display"
                log "DISPLAY found for desktop environment: $DISPLAY"
                return 0
            fi
        done
    fi
    
    return 1
}

# XAUTHORITY configuration
setup_xauthority() {
    log "XAUTHORITY configuration..."
    
    local current_user="${TARGET_USER:-$(whoami)}"
    local home_dir="${HOME}"
    
    # Find .Xauthority file
    if [[ -f "$home_dir/.Xauthority" ]]; then
        XAUTH_FILE="$home_dir/.Xauthority"
        log "XAUTHORITY found: $XAUTH_FILE"
    elif [[ -f "/root/.Xauthority" ]] && [[ "$EUID" -eq 0 ]]; then
        XAUTH_FILE="/root/.Xauthority"
        log "Root XAUTHORITY found: $XAUTH_FILE"
    else
        warn "No .Xauthority file found"
        return 1
    fi
    
    # NOTE: DO NOT overwrite XAUTHORITY because it is already correct from the orchestrator
    # The XAUTHORITY variable has already been set correctly by the orchestrator
    log "XAUTHORITY already set correctly by orchestrator: $XAUTHORITY"
    
    # Grant root access to user file (if necessary)
    if [[ "$EUID" -eq 0 ]] && [[ "$current_user" != "root" ]]; then
        log "Granting root access to user .Xauthority file..."
        if command -v xhost >/dev/null 2>&1; then
            xhost +si:localuser:root 2>/dev/null || warn "Unable to grant xhost access"
        fi
    fi
    
    return 0
}

# XDG_RUNTIME_DIR and D-Bus configuration
setup_xdg_runtime_dir() {
    log "XDG_RUNTIME_DIR and D-Bus configuration..."
    
    local current_user="${TARGET_USER:-$(whoami)}"
    local user_id="${TARGET_UID:-$(id -u)}"
    
    XDG_RUNTIME_DIR="/run/user/$user_id"
    
    # Verify directory existence
    if [[ -d "$XDG_RUNTIME_DIR" ]]; then
        export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
        log "XDG_RUNTIME_DIR set: $XDG_RUNTIME_DIR"
    else
        log "XDG_RUNTIME_DIR does not exist: $XDG_RUNTIME_DIR"
        
        # Attempt creation (if root)
        if [[ "$EUID" -eq 0 ]]; then
            mkdir -p "$XDG_RUNTIME_DIR"
            chown "$current_user:$current_user" "$XDG_RUNTIME_DIR"
            export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
            log "XDG_RUNTIME_DIR created: $XDG_RUNTIME_DIR"
        fi
    fi
    
    # Setup D-Bus session per target user
    setup_dbus_session "$current_user" "$user_id"
}

# Setup D-Bus session per specific user
setup_dbus_session() {
    local target_user="$1"
    local user_id="$2"
    
    log "Setup D-Bus session per user: $target_user"
    rm -f /tmp/olms_dbus_vars.sh
    
    # Kill residuals to free the abstract socket
    sudo -u "$target_user" pkill -u "$target_user" -f "olms_bus_${user_id}" || true
    sleep 1
    
    local abstract_addr="unix:abstract=olms_bus_${user_id}"
    log "Starting dbus-daemon on: $abstract_addr"
    
    # Start and capture the real address
    sudo -u "$target_user" dbus-daemon --fork --session --address="$abstract_addr" --print-address > /dev/null
    
    # Verify PID
    local dbus_pid=$(sudo -u "$target_user" pgrep -u "$target_user" -f "olms_bus_${user_id}")
    
    if [[ -n "$dbus_pid" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="$abstract_addr"
        echo "export DBUS_SESSION_BUS_ADDRESS=\"$abstract_addr\"" > /tmp/olms_dbus_vars.sh
        log "✅ Private D-Bus started (PID: $dbus_pid)"
    else
        error "Unable to start dbus-daemon."
        exit 1
    fi
}

# X11 permissions configuration
setup_x11_permissions() {
    log "X11 permissions configuration..."
    
    local current_user="${TARGET_USER:-$(whoami)}"
    
    # Root-to-user transition
    if [[ "$EUID" -eq 0 ]]; then
        log "Root detected, user transition configuration..."
        
        # Preserve correct DISPLAY during sudo
        if [[ -n "$DISPLAY" ]]; then
            export DISPLAY="$DISPLAY"
            log "DISPLAY preserved: $DISPLAY"
        fi
        
    # XAUTHORITY management for root - DO NOT overwrite the correct variable
    if [[ -f "$HOME/.Xauthority" ]] && [[ "$EUID" -eq 0 ]]; then
        # Copy user's .Xauthority to root to allow access
        cp "$HOME/.Xauthority" "/root/.Xauthority" 2>/dev/null || true
        chown root:root "/root/.Xauthority" 2>/dev/null || true
        chmod 600 "/root/.Xauthority" 2>/dev/null || true
        log "Copied user .Xauthority to root for X11 access"
        # NOTE: DO NOT overwrite XAUTHORITY because it is already correct from the orchestrator
    fi
    
    # Grant X11 access to root (if possible) - BUT DO NOT OVERWRITE XAUTHORITY
    if command -v xhost >/dev/null 2>&1; then
        # Try to grant access as normal user, not as root
        if [[ -n "${SUDO_USER:-}" ]]; then
            su - "$SUDO_USER" -c "DISPLAY=$DISPLAY xhost +si:localuser:root" 2>/dev/null || warn "Unable to grant X11 access to root"
        else
            xhost +si:localuser:root 2>/dev/null || warn "Unable to grant X11 access to root"
        fi
    fi
    fi
    
    # Verify DISPLAY
    if [[ -n "$DISPLAY" ]]; then
        export DISPLAY="$DISPLAY"
        log "DISPLAY set: $DISPLAY"
    else
        warn "DISPLAY not set"
    fi
}

# Setup Xvfb for headless mode
setup_xvfb() {
    log "Setup Xvfb for headless mode..."
    
    if ! command -v Xvfb >/dev/null 2>&1; then
        warn "Xvfb not available"
        return 1
    fi
    
    # Find free display number
    local xvfb_display=""
    for i in {99..120}; do
        if ! [[ -S "/tmp/.X11-unix/X$i" ]]; then
            xvfb_display=":$i"
            break
        fi
    done
    
    if [[ -z "$xvfb_display" ]]; then
        warn "No free display number for Xvfb"
        return 1
    fi
    
    log "Starting Xvfb on display: $xvfb_display"
    
    # Start Xvfb with minimal parameters
    Xvfb "$xvfb_display" -screen 0 1024x768x24 -nolisten tcp -nolisten unix &
    local xvfb_pid=$!
    
    # Wait for startup
    sleep 2
    
    # Verify startup
    if kill -0 "$xvfb_pid" 2>/dev/null; then
        export DISPLAY="$xvfb_display"
        log "Xvfb started successfully (PID: $xvfb_pid, DISPLAY: $DISPLAY)"
        return 0
    else
        warn "Xvfb not started correctly"
        return 1
    fi
}

# X11 configuration verification
verify_x11_setup() {
    log "X11 configuration verification..."
    
    # Verify DISPLAY
    if [[ -n "${DISPLAY:-}" ]]; then
        log "DISPLAY: $DISPLAY"
    else
        warn "DISPLAY not set"
    fi
    
    # Verify XAUTHORITY
    if [[ -n "${XAUTHORITY:-}" ]]; then
        log "XAUTHORITY: $XAUTHORITY"
    else
        warn "XAUTHORITY not set"
    fi
    
    # Verify XDG_RUNTIME_DIR
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        log "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
    else
        warn "XDG_RUNTIME_DIR not set"
    fi
    
    # Test X11 connection (if not in headless mode)
    if [[ -n "${DISPLAY:-}" ]] && [[ "$DISPLAY" != *":99"* ]] && [[ "$DISPLAY" != *":100"* ]]; then
        if command -v xdpyinfo >/dev/null 2>&1; then
            if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
                log "X11 connection verified"
            else
                warn "X11 connection failed"
            fi
        fi
    fi
    
    # Debug X11 errors (added for troubleshooting)
    if [[ -f "/tmp/ardour_startup.log" ]]; then
        log "Checking X11 errors in /tmp/ardour_startup.log..."
        local x11_errors=$(grep -i "display\|x11\|xcb\|qt" /tmp/ardour_startup.log 2>/dev/null || true)
        if [[ -n "$x11_errors" ]]; then
            warn "X11 errors found in ardour_startup.log:"
            echo "$x11_errors" | while read -r line; do
                warn "  $line"
            done
        else
            log "No X11 errors detected in ardour_startup.log"
        fi
    fi
}

# Main function
main() {
    log "=== PHASE 4: X11 ENVIRONMENT & DISPLAY MANAGEMENT ==="
    
    # Use a flag to avoid set -e interrupting everything
    set +e
    detect_display
    DISPLAY_DETECTED=$?
    set -e
    
    if [ $DISPLAY_DETECTED -ne 0 ]; then
        warn "Physical display not detected, trying Xvfb..."
        setup_xvfb || warn "Xvfb also failed, proceeding in pure headless mode"
    fi
    
    # Continue with the rest, but make setup non-fatal if possible
    setup_xauthority || warn "Unable to configure Xauthority"
    setup_xdg_runtime_dir
    setup_x11_permissions
    
    verify_x11_setup
    
    log "X11 configuration completed (DISPLAY=${DISPLAY:-N/A})"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
