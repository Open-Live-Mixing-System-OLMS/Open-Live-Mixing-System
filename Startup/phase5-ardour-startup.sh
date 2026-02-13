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

# Phase 5: Ardour Startup - FIX PARSING prlimit
set -euo pipefail

# Logging configuration
LOG_FILE="/tmp/olms-ardour-startup.log"
# FIX: Ensure log file is writable by all to avoid Permission Denied
touch "$LOG_FILE"
chmod 666 "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Universal variables for dynamic CPU architecture
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))
SYSTEM_CORE="0"
IRQ_CORE="1"
AUDIO_CORES="2-$LAST_CORE"

# JACK/D-Bus/X11 variables
JACK_SERVER_NAME="olms"
JACK_SESSION_DIR="/dev/shm/jack_olms_0"
JACK_SOCKET_DIR="/dev/shm/jack_olms_0"
DBUS_SOCKET_ABSTRACT="olms_bus_$(id -u)"
XAUTHORITY_PATH="/home/$(whoami)/.Xauthority"
DISPLAY=":0"
CPU_CORES="$AUDIO_CORES"
RT_PRIORITY=70

# Logging functions (consistent with other scripts)
log() { echo -e "\e[32m[$(date '+%Y-%m-%d %H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%Y-%m-%d %H:%M:%S')] WARN:\e[0m $1"; }
error() { echo -e "\e[31m[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:\e[0m $1"; }

# Universal configuration variables
# Detect the effective user (the one who launched sudo) with robust logic
# 1. Try with SUDO_USER (if available)
if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    EFFECTIVE_USER="$SUDO_USER"
    EFFECTIVE_HOME=$(eval echo ~$SUDO_USER)
    log "User detected from SUDO_USER: $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
# 2. Try with TARGET_USER (passed from orchestrator)
elif [[ -n "${TARGET_USER:-}" ]] && [[ "$TARGET_USER" != "root" ]]; then
    EFFECTIVE_USER="$TARGET_USER"
    EFFECTIVE_HOME=$(eval echo ~$TARGET_USER)
    log "User detected from TARGET_USER: $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
# 3. Try with loginuid (robust method for processes launched with sudo)
elif [[ -f "/proc/$PPID/loginuid" ]]; then
    LOGINUID=$(cat "/proc/$PPID/loginuid" 2>/dev/null)
    if [[ -n "$LOGINUID" ]] && [[ "$LOGINUID" != "4294967295" ]] && [[ "$LOGINUID" != "0" ]]; then
        EFFECTIVE_USER=$(getent passwd "$LOGINUID" | cut -d: -f1)
        if [[ -n "$EFFECTIVE_USER" ]] && [[ "$EFFECTIVE_USER" != "root" ]]; then
            EFFECTIVE_HOME=$(eval echo ~$EFFECTIVE_USER)
            log "User detected from loginuid: $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
        else
            EFFECTIVE_USER="$(whoami)"
            EFFECTIVE_HOME="$HOME"
            log "User detected from whoami (fallback): $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
        fi
    else
        EFFECTIVE_USER="$(whoami)"
        EFFECTIVE_HOME="$HOME"
        log "User detected from whoami (fallback): $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
    fi
# 4. Final fallback
else
    EFFECTIVE_USER="$(whoami)"
    EFFECTIVE_HOME="$HOME"
    log "User detected from whoami (fallback): $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
fi

# Verify that the effective user is not root (unless intentional)
if [[ "$EFFECTIVE_USER" == "root" ]] && [[ "${OLMS_MODE:-}" != "headless" ]]; then
    warn "⚠️ Effective user is root - verify that this is intentional"
    warn "💡 If running with sudo, verify that SUDO_USER is set correctly"
fi

# Configuration variables - use new relative path system
ARD_SESSION_PATH="$EFFECTIVE_HOME/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"
ARD_SESSION_DIR="$EFFECTIVE_HOME/Progetti/OLMS-Core/engine/session-template/OLMS-POC"

# Try to detect if we're running from within OLMS-Core
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$script_dir" == */Startup2 ]]; then
    # We're running from within OLMS-Core, use the parent directory
    olms_core_root="$(dirname "$script_dir")"
    ARD_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
    ARD_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
fi

ARD_USER="$EFFECTIVE_USER"
ARD_UID=$(id -u "$EFFECTIVE_USER" 2>/dev/null || echo "$(id -u)")
ACTUAL_UID=$(id -u "$EFFECTIVE_USER" 2>/dev/null || echo "$(id -u)")
ARD_HOME="$EFFECTIVE_HOME"

# Variables for session adaptation
JACK_SERVER_NAME="olms"
SESSION_BACKUP_PATH="${ARD_SESSION_PATH}.backup"
SESSION_TEMP_PATH="${ARD_SESSION_PATH}.temp"

# Logging functions (consistent with other scripts)
log() { echo -e "\e[32m[$(date '+%Y-%m-%d %H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%Y-%m-%d %H:%M:%S')] WARN:\e[0m $1"; }
error() { echo -e "\e[31m[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:\e[0m $1"; }

# Ardour session adaptation functions

# --- LEVEL 3: BRIEF THREAD MONITORING ---
monitor_anti_migration_brief() {
    local target_pid=$1
    log "🛰️ Brief monitoring of Ardour threads on Core $AUDIO_CORES (PID: $target_pid)"
    
    # Brief monitoring for 10 seconds during critical startup
    (
        for i in {1..10}; do
            # Apply pinning to ALL current threads
            if [ -d "/proc/$target_pid/task" ]; then
                ls "/proc/$target_pid/task" 2>/dev/null | xargs -I {} taskset -pc "$AUDIO_CORES" {} >/dev/null 2>&1
            fi
            sleep 1
        done
        log "✅ Brief monitoring completed."
    ) &
}

detect_jack_ports() {
    log "🔍 Detecting available JACK ports for server '$JACK_SERVER_NAME'..."
    
    # Complete environment configuration (like in latency test)
    local base_env="PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1"
    
    # First attempt: detect available JACK ports with complete environment
    local available_ports
    available_ports=$(sudo -u "$ARD_USER" env $base_env jack_lsp 2>/dev/null | grep "^system:" | sort)
    
    if [ -z "$available_ports" ]; then
        warn "⚠️ No JACK ports found for server '$JACK_SERVER_NAME' with jack_lsp"
        warn "💡 JACK is stable but jack_lsp cannot see ports (common issue with budget cards)"
        
        # Second attempt: try with simplified environment
        log "🔧 Attempt with simplified environment..."
        available_ports=$(sudo -u "$ARD_USER" env JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1 jack_lsp 2>/dev/null | grep "^system:" | sort)
        
        if [ -z "$available_ports" ]; then
            warn "⚠️ Still no ports found with simplified environment"
            
            # Third attempt: try without JACK_NO_START_SERVER
            log "🔧 Attempt without JACK_NO_START_SERVER..."
            available_ports=$(sudo -u "$ARD_USER" env JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_PROMISCUOUS_SERVER=1 jack_lsp 2>/dev/null | grep "^system:" | sort)
            
            if [ -z "$available_ports" ]; then
                warn "⚠️ No JACK ports found with any method"
                warn "🔧 Using default ports for standard audio card..."
                
                # Fallback: default ports for standard audio cards
                export JACK_CAPTURE_PORTS="system:capture_1"
                export JACK_PLAYBACK_PORTS="system:playback_1
system:playback_2"
                export CAPTURE_COUNT=1
                export PLAYBACK_COUNT=2
                
                log "✅ Default ports set:"
                log "  - Capture: system:capture_1"
                log "  - Playback 1: system:playback_1"
                log "  - Playback 2: system:playback_2"
                
                return 0
            fi
        fi
    fi
    
    log "✅ Available JACK ports found:"
    echo "$available_ports" | while read -r port; do
        log "  - $port"
    done
    
    # Save available ports in global variables
    export JACK_CAPTURE_PORTS=$(echo "$available_ports" | grep "capture" | head -10)
    export JACK_PLAYBACK_PORTS=$(echo "$available_ports" | grep "playback" | head -10)
    
    # Count available ports
    export CAPTURE_COUNT=$(echo "$JACK_CAPTURE_PORTS" | wc -l)
    export PLAYBACK_COUNT=$(echo "$JACK_PLAYBACK_PORTS" | wc -l)
    
    log "Available ports: $CAPTURE_COUNT capture, $PLAYBACK_COUNT playback"
    
    return 0
}

backup_session() {
    log "📁 Creating Ardour session backup..."
    
    if [ -f "$ARD_SESSION_PATH" ]; then
        sudo -u $(whoami) cp "$ARD_SESSION_PATH" "$SESSION_BACKUP_PATH"
        if [ $? -eq 0 ]; then
            log "✅ Session backup created: $SESSION_BACKUP_PATH"
            return 0
        else
            error "Unable to create session backup"
            return 1
        fi
    else
        error "Session file not found: $ARD_SESSION_PATH"
        return 1
    fi
}

validate_port_mapping() {
    log "✅ Validating port mapping..."
    
    # Check that there are enough ports for the session
    local required_capture=1  # Audio 1 requires 1 capture port
    local required_playback=2 # Master and Click require 2 playback ports
    
    if [ "$CAPTURE_COUNT" -lt "$required_capture" ]; then
        error "Insufficient capture ports: required $required_capture, available $CAPTURE_COUNT"
        return 1
    fi
    
    if [ "$PLAYBACK_COUNT" -lt "$required_playback" ]; then
        error "Insufficient playback ports: required $required_playback, available $PLAYBACK_COUNT"
        return 1
    fi
    
    log "✅ Validation passed: sufficient ports for session"
    return 0
}

adapt_session_to_ports() {
    log "🔧 Adapting Ardour session to available ports..."
    
    if ! validate_port_mapping; then
        return 1
    fi
    
    # Extract first available capture port
    local capture_port=$(echo "$JACK_CAPTURE_PORTS" | head -1)
    # Extract first 2 available playback ports
    local playback_port_1=$(echo "$JACK_PLAYBACK_PORTS" | head -1)
    local playback_port_2=$(echo "$JACK_PLAYBACK_PORTS" | sed -n '2p')
    
    log "Port mapping:"
    log "  Capture: system:capture_1 → $capture_port"
    log "  Playback 1: system:playback_1 → $playback_port_1"
    log "  Playback 2: system:playback_2 → $playback_port_2"
    
    # Create temporary file with substitutions as user $(whoami)
    sudo -u $(whoami) cp "$ARD_SESSION_PATH" "$SESSION_TEMP_PATH"
    
    # Substitute JACK connections in XML file as user $(whoami)
    # Use sed to replace specific patterns
    sudo -u $(whoami) sed -i "s/other=\"system:capture_1\"/other=\"$capture_port\"/g" "$SESSION_TEMP_PATH"
    sudo -u $(whoami) sed -i "s/other=\"system:playback_1\"/other=\"$playback_port_1\"/g" "$SESSION_TEMP_PATH"
    sudo -u $(whoami) sed -i "s/other=\"system:playback_2\"/other=\"$playback_port_2\"/g" "$SESSION_TEMP_PATH"
    
    # Verify substitutions were made correctly
    local capture_subs=$(grep -c "$capture_port" "$SESSION_TEMP_PATH")
    local playback1_subs=$(grep -c "$playback_port_1" "$SESSION_TEMP_PATH")
    local playback2_subs=$(grep -c "$playback_port_2" "$SESSION_TEMP_PATH")
    
    log "Substitutions made:"
    log "  Capture: $capture_subs occurrences"
    log "  Playback 1: $playback1_subs occurrences"
    log "  Playback 2: $playback2_subs occurrences"
    
    if [ "$capture_subs" -gt 0 ] && [ "$playback1_subs" -gt 0 ] && [ "$playback2_subs" -gt 0 ]; then
        log "✅ Session successfully adapted to available ports"
        return 0
    else
        error "Port substitution failed or incomplete"
        return 1
    fi
}

reload_ardour_session() {
    log "🔄 Reloading Ardour session..."
    
    # Find Ardour PID
    local ardour_pid
    ardour_pid=$(pgrep -f "ardour8.*--no-splash")
    
    if [ -z "$ardour_pid" ]; then
        error "Unable to find Ardour process"
        return 1
    fi
    
    log "Ardour running (PID: $ardour_pid)"
    
    # Send reload signal to session
    # Ardour doesn't support direct reload via signal, so we need to restart it
    log "Restarting Ardour with updated session..."
    
    # Terminate Ardour cleanly
    kill -TERM "$ardour_pid" 2>/dev/null || true
    sleep 2
    
    # Verify Ardour has terminated
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        log "Ardour did not close properly, forcing termination..."
        kill -KILL "$ardour_pid" 2>/dev/null || true
        sleep 1
    fi
    
    # Move temporary file to original location as user $(whoami)
    sudo -u $(whoami) mv "$SESSION_TEMP_PATH" "$ARD_SESSION_PATH"
    
    # Restart Ardour with updated session
    log "Restarting Ardour with adapted session..."
    
    sudo -u "$ARD_USER" env \
        HOME=$EFFECTIVE_HOME \
        DISPLAY=:0 \
        XAUTHORITY=$EFFECTIVE_HOME/.Xauthority \
        XDG_RUNTIME_DIR=/run/user/$ARD_UID \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH" &
    
    # Wait for Ardour to restart
    sleep 3
    
    # Verify Ardour is running again
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        local new_ardour_pid=$(pgrep -f "ardour8.*--no-splash")
        log "✅ Ardour restarted with adapted session (PID: $new_ardour_pid)"
        return 0
    else
        error "Ardour restart failed"
        return 1
    fi
}

# Headless mode check
if [[ "${OLMS_MODE:-}" == "headless" ]]; then
    log "🚀 CONFIGURAZIONE MODALITÀ HEADLESS (Display :99)"

    # 1. Pulizia e Setup Xvfb
    sudo rm -f /tmp/.X99-lock
    
    # Generazione Xauthority per l'utente target
    XAUTH_FILE="/tmp/.Xauth-ardour"
    sudo -u "$ARD_USER" touch "$XAUTH_FILE"
    mcookie=$(mcookie)
    sudo -u "$ARD_USER" xauth -f "$XAUTH_FILE" add :99 . "$mcookie"
    log "✅ File Xauthority generato in $XAUTH_FILE"

    # 2. Avvio Xvfb
    sudo -u "$ARD_USER" Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
    XVFB_PID=$!
    
    # Attesa che il display sia pronto
    timeout=10
    while ! sudo -u "$ARD_USER" DISPLAY=:99 xset q > /dev/null 2>&1; do
        sleep 0.5
        ((timeout--))
        if [ $timeout -le 0 ]; then error "Xvfb timeout"; exit 1; fi
    done
    log "✅ Display virtuale :99 pronto."

    # 3. Avvio Ardour con parametri specifici
    # NOTA: Rimosso JACK_NO_START_SERVER per permettere il retry della connessione
    log "🎼 Avvio Ardour Headless..."
    
    sudo -u "$ARD_USER" env \
        HOME="$EFFECTIVE_HOME" \
        DISPLAY=:99 \
        XAUTHORITY="$XAUTH_FILE" \
        XDG_RUNTIME_DIR="/run/user/$ARD_UID" \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH" &
    
    ARD_PID=$!
    sleep 5

    if ps -p $ARD_PID > /dev/null; then
        log "✅ Ardour Headless operativo (PID: $ARD_PID)"
        # Monitoraggio pin CPU
        monitor_anti_migration_brief "$ARD_PID"
        
        # Aggiungere verifica kernel
        sleep 3
        final_mask=$(taskset -p "$ARD_PID" | awk '{print $NF}')
        log "📊 FINAL KERNEL VERIFICATION: Mask=$final_mask (Target: 0xc)"
        
        if [[ "$final_mask" == "f" ]]; then
            error "❌ ERROR: The system continues to force mask 'f'. Possible systemd or cgroups override."
            exit 1
        fi
    else
        error "❌ Ardour Headless è fallito. Controlla /tmp/olms-ardour-startup.log"
        kill $XVFB_PID 2>/dev/null || true
        exit 1
    fi
fi

check_user_permissions() {
    log "Checking user permissions for $ARD_USER..."
    
    # Extract SOFT (third-to-last) and HARD (second-to-last) values to be sure
    local rtprio_limit=$(sudo -u "$ARD_USER" prlimit --rtprio --pid=$$ --noheadings --output=SOFT)
    local memlock_limit=$(sudo -u "$ARD_USER" prlimit --memlock --pid=$$ --noheadings --output=SOFT)

    log "Detected rtprio_limit: $rtprio_limit"
    log "Detected memlock_limit: $memlock_limit"

    if [[ "$rtprio_limit" != "unlimited" ]] && [ "$rtprio_limit" -lt 90 ]; then
        log "ERROR: rtprio too low ($rtprio_limit)"
        return 1
    fi
    return 0
}

start_ardour_with_fallback() {
    log "=== ARDOUR STARTUP ==="
    
    # Clean environment for execution as target user
    local base_env="DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY_PATH XDG_RUNTIME_DIR=/run/user/$ARD_UID DBUS_SESSION_BUS_ADDRESS=unix:abstract=$DBUS_SOCKET_ABSTRACT JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_SESSION_DIR=$JACK_SESSION_DIR JACK_NO_START_SERVER=1 JACK_PROMISCUOUS_SERVER=1"

    log "Final command execution..."
    log "User transition: sudo -u $ARD_USER (UID: $ARD_UID)"
    log "Environment set: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY_PATH"
    log "Command: taskset -c $CPU_CORES chrt -f $RT_PRIORITY /usr/bin/ardour8 -Z olms -n $ARD_SESSION_PATH"
    
    # Explicitly add the -Z (or --jack-server) flag to Ardour
    sudo -u "$ARD_USER" -E env $base_env taskset -c "$CPU_CORES" chrt -f "$RT_PRIORITY" /usr/bin/ardour8 -Z olms -n "$ARD_SESSION_PATH"
}

# --- LEVEL 1: RADICAL CLEANUP AND SHM RESET ---
fix_shm_permissions_radical() {
    log "🧹 CLEANUP AND FIX SHM: Analysis of shared segments..."

    # 1. Identify if there is an active JACK server and who it belongs to
    local jack_pid=$(pgrep -x "jackd" || echo "")
    
    if [[ -n "$jack_pid" ]]; then
        local jack_user=$(ps -o user= -p "$jack_pid")
        log "ℹ️ JACK Server active (PID: $jack_pid, User: $jack_user)"
        
        # If JACK is root, we need to open everything
        if [[ "$jack_user" == "root" ]]; then
            warn "⚠️ JACK is running as ROOT. Applying aggressive permission patch..."
        fi
    else
        warn "⚠️ No JACK process found. Ardour might not start."
    fi

    # 2. Fix permissions for standard directories and files in /dev/shm
    # Look for everything that resembles JACK
    log "🔧 Applying chmod 777 to /dev/shm/jack*..."
    
    # This unlocks directories like /dev/shm/jack_olms_0
    find /dev/shm -name "jack*" -exec chmod 777 {} \; 2>/dev/null || true
    
    # Fix specific for semaphores (often causes Permission Denied)
    chmod 666 /dev/shm/sem.jack* 2>/dev/null || true
    
    # 3. CRITICAL FIX FOR POSIX SHM (/dev/shm/jack-*-*)
    # Linux kernel maps shm_open to /dev/shm.
    # If JACK is root (UID 0), it creates /dev/shm/jack-0-*.
    # Ardour (UID 1000) tries to open them.
    
    log "🔧 Searching for orphaned or blocked SHM segments..."
    for seg in /dev/shm/jack-*-*; do
        if [ -e "$seg" ]; then
            # Check if it's owned by root
            if [ "$(stat -c '%u' "$seg")" -eq 0 ]; then
                log "🔓 Unlocking ROOT segment: $seg"
                chown "$ARD_USER":audio "$seg" 2>/dev/null || true # Attempt owner change
                chmod 777 "$seg" # Force read/write for all
            else
                chmod 777 "$seg"
            fi
        fi
    done

    # 4. Ensure the registry directory exists and is accessible
    if [ ! -f "/dev/shm/jack-shm-registry" ]; then
        # Sometimes JACK creates pipes instead of files, or uses different directories
        warn "Standard registry file not found, checking alternative directories..."
    else
        chmod 666 "/dev/shm/jack-shm-registry"
    fi

    log "✅ Permissions fix completed."
}

# --- LEVEL 2: WRAPPER IN USER HOME (Fix Permission Denied) ---
create_ardour_wrapper() {
    local wrapper_path="$EFFECTIVE_HOME/.olms_ardour_launcher.sh"
    mkdir -p "$(dirname "$wrapper_path")"
    
    log "🏗️ Creating wrapper script (NO-START MODE) in $wrapper_path..." >&2
    
    cat << EOF > "$wrapper_path"
#!/bin/bash
# OLMS Ardour Launcher - Forced Connection Mode

# 1. Environment variables to force JACK libraries not to start a server
export JACK_DEFAULT_SERVER="$JACK_SERVER_NAME"
export JACK_NO_START_SERVER=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_SESSION_DIR="/dev/shm/jack_olms_0"

# 2. Graphics Variables
export DISPLAY=:0
export XAUTHORITY=$EFFECTIVE_HOME/.Xauthority

# 3. Verify Socket existence before starting
if [ ! -S "/dev/shm/jack_olms_0" ]; then
    echo "ERROR: JACK socket not found. Server '$JACK_SERVER_NAME' is not running."
    exit 1
fi

# 4. RT Limits
ulimit -r 99
ulimit -l unlimited

# 5. ATOMIC Launch
exec taskset -c $CPU_CORES chrt -f $RT_PRIORITY /usr/bin/ardour8 \\
    --no-splash \\
    "$ARD_SESSION_PATH"
EOF

    chown "$ARD_USER":"$(id -gn "$ARD_USER")" "$wrapper_path"
    chmod +x "$wrapper_path"
    echo "$wrapper_path"
}

# --- LEVEL 3: BRIEF THREAD MONITORING ---
monitor_anti_migration_brief() {
    local target_pid=$1
    log "🛰️ Brief monitoring of Ardour threads on Core $AUDIO_CORES (PID: $target_pid)"
    
    # Brief monitoring for 10 seconds during critical startup
    (
        for i in {1..10}; do
            # Apply pinning to ALL current threads
            if [ -d "/proc/$target_pid/task" ]; then
                ls "/proc/$target_pid/task" 2>/dev/null | xargs -I {} taskset -pc "$AUDIO_CORES" {} >/dev/null 2>&1
            fi
            sleep 1
        done
        log "✅ Brief monitoring completed."
    ) &
}

main() {
    log "=== PHASE 5: ARDOUR STARTUP (Triple-Lock Mode) ==="
    
    # Check if we're already in headless mode and Ardour is already running
    if [[ "${OLMS_MODE:-}" == "headless" ]]; then
        log "✅ Headless mode detected - Ardour already started in headless mode, skipping main function"
        return 0
    fi
    
    # 1. SHM Preparation
    fix_shm_permissions_radical

    # 2. Wrapper Creation (Now in Home)
    local WRAPPER_SCRIPT=$(create_ardour_wrapper)

    # Verify that the wrapper was created correctly
    if [ ! -f "$WRAPPER_SCRIPT" ]; then
        error "❌ ERROR: Wrapper script not created correctly: $WRAPPER_SCRIPT"
        exit 1
    fi

    # Add a small delay to ensure the file is completely written
    sleep 0.5

    # Verify execution permissions
    if [ ! -x "$WRAPPER_SCRIPT" ]; then
        warn "⚠️ Wrapper not executable, fixing permissions..."
        chmod +x "$WRAPPER_SCRIPT"
    fi

    # 3. ATOMIC Launch
    log "🚀 Atomic launch via wrapper..."
    # Remove the -E from sudo to avoid variable conflicts, pass them in the wrapper
    sudo -u "$ARD_USER" /bin/bash "$WRAPPER_SCRIPT" &
    local ARD_PID=$!

    # Small check to see if the wrapper at least started bash
    sleep 0.2
    if ! ps -p $ARD_PID > /dev/null; then
        error "❌ The bash wrapper did not start correctly."
        exit 1
    fi
    
    # 4. Immediate Monitoring (Brief)
    monitor_anti_migration_brief "$ARD_PID"

    # 5. Kernel Verification
    sleep 3
    local final_mask=$(taskset -p "$ARD_PID" | awk '{print $NF}')
    log "📊 FINAL KERNEL VERIFICATION: Mask=$final_mask (Target: 0xc)"

    if [[ "$final_mask" == "f" ]]; then
        error "❌ ERROR: The system continues to force mask 'f'. Possible systemd or cgroups override."
        exit 1
    fi

    log "✅ ADAPTATION AND STARTUP COMPLETED."
}

main "$@"
