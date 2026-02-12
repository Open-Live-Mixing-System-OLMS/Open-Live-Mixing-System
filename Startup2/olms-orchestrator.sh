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

# OLMS Startup Orchestrator
# Manages the entire audio real-time startup process
# Version: 2.0

set -euo pipefail

# Basic configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Smart management of home path and log file to handle sudo execution
if [[ "$EUID" -eq 0 ]]; then
    # If we are root, we need to determine the actual user
    if [[ -n "${SUDO_USER:-}" ]]; then
        # Executed with sudo, use original user
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

OLMS_HOME="$ACTUAL_HOME/.olms"
mkdir -p "$OLMS_HOME"

# Smart log file management
LOG_FILE="$OLMS_HOME/olms-orchestrator.log"

# If the file in /tmp exists and belongs to another user, use a unique name
if [[ -f "/tmp/olms-orchestrator.log" ]]; then
    LOG_FILE="/tmp/olms-orchestrator-${ACTUAL_USER}-$(date +%s).log"
fi

# Ensure log file is writable
if [[ ! -f "$LOG_FILE" ]]; then
    # Create log file if it doesn't exist
    touch "$LOG_FILE" 2>/dev/null || {
        # If we can't create the file in home, use an alternative path
        LOG_FILE="/tmp/olms-orchestrator-${ACTUAL_USER}-$(date +%s).log"
        warn "Unable to create log file in home directory, using: $LOG_FILE"
    }
elif [[ ! -w "$LOG_FILE" ]]; then
    # If file exists but is not writable, create a new one with unique timestamp
    LOG_FILE="/tmp/olms-orchestrator-${ACTUAL_USER}-$(date +%s).log"
    warn "Existing log file is not writable, using: $LOG_FILE"
fi

LOCK_FILE="$OLMS_HOME/olms-startup.lock"
PID_FILE="$OLMS_HOME/olms-startup.pid"

# Argument parsing
MODE="headless"  # default
if [[ "${1:-}" == "--test" ]]; then
    MODE="test"
    shift
fi

# Environment variables for "all as same user" approach
# Use ACTUAL_USER and ACTUAL_HOME to properly handle sudo execution
export TARGET_USER="$ACTUAL_USER"
export TARGET_UID=$(id -u "$ACTUAL_USER" 2>/dev/null || echo "$(id -u)")
export ACTUAL_UID="$TARGET_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
export DISPLAY=":0"
export XAUTHORITY="$ACTUAL_HOME/.Xauthority"

# JACK variables for consistency across all scripts
export JACK_DEFAULT_SERVER="olms"
export JACK_NO_AUDIO_RESERVATION=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_NO_START_SERVER=1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
    error "Startup process aborted due to warning: $1"
    exit 1
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check if a command is available
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Command '$1' not found. Install before proceeding."
        exit 1
    fi
}

# Cleanup on interruption
cleanup() {
    log "Cleanup in progress..."
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    if [[ -f "$PID_FILE" ]]; then
        rm -f "$PID_FILE" 2>/dev/null || true
    fi
    exit 1
}

trap cleanup EXIT INT TERM

# Check lock file
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log "Startup process already running (PID: $lock_pid), forced termination in progress..."
            # Terminate existing process
            kill -TERM "$lock_pid" 2>/dev/null || true
            sleep 2
            # If process is still active, force termination
            if kill -0 "$lock_pid" 2>/dev/null; then
                log "Process still active, forced termination with kill -9..."
                kill -9 "$lock_pid" 2>/dev/null || true
                sleep 1
            fi
            # Forced cleanup of lock files
            sudo rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
            log "Previous startup process terminated and lock files cleaned"
        else
            log "Lock file found but process not active, automatic cleanup in progress..."
            # Forced automatic cleanup
            sudo rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
            # Verify cleanup occurred
            if [[ -f "$LOCK_FILE" ]]; then
                warn "Unable to remove lock file, attempting with kill -9..."
                sudo kill -9 "$lock_pid" 2>/dev/null || true
                sleep 1
                sudo rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
            fi
        fi
    fi
    
    # Create lock file
    echo $$ > "$LOCK_FILE"
    echo $$ > "$PID_FILE"
    log "Lock file created: $LOCK_FILE"
}

# Cleanup lock file to avoid conflicts with phase0-lock-management.sh
cleanup_lock_for_phase0() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ "$lock_pid" == "$$" ]]; then
            # This is our lock file, remove it temporarily for phase0
            rm -f "$LOCK_FILE" "$PID_FILE"
            log "Lock file temporarily removed for phase0-lock-management.sh"
        fi
    fi
}

# Restore lock file after phase0
restore_lock_after_phase0() {
    if [[ ! -f "$LOCK_FILE" ]]; then
        echo $$ > "$LOCK_FILE"
        echo $$ > "$PID_FILE"
        log "Lock file restored after phase0"
    fi
}

# Graceful Ardour session closing function
close_ardour_sessions_gracefully() {
    log "=== GRACEFUL ARDOUR SESSION CLOSING ==="
    
    # Smart user detection (consistent with other scripts)
    local ardour_user="$ACTUAL_USER"
    local ardour_uid=$(id -u "$ardour_user" 2>/dev/null || echo "$(id -u)")
    local ardour_home="$ACTUAL_HOME"
    
    # Session paths
    local session_path="$ardour_home/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"
    local session_dir="$ardour_home/Progetti/OLMS-Core/engine/session-template/OLMS-POC"
    
    # Find Ardour processes
    local ardour_pids=$(pgrep -x "ardour\|ardour8" 2>/dev/null || true)
    
    if [[ -z "$ardour_pids" ]]; then
        log "No Ardour sessions running - skipping session closing"
        return 0
    fi
    
    log "Found Ardour processes: $ardour_pids"
    
    # Function to check if Ardour is responsive
    is_ardour_responsive() {
        local pid=$1
        # Check if process is still responding
        if kill -0 "$pid" 2>/dev/null; then
            # Try to send a simple signal to test responsiveness
            if kill -CONT "$pid" 2>/dev/null; then
                return 0
            fi
        fi
        return 1
    }
    
    # Function to save Ardour session
    save_ardour_session() {
        local pid=$1
        log "Attempting to save Ardour session (PID: $pid)..."
        
        # Method 1: Try SIGUSR1 (Ardour save signal)
        if kill -USR1 "$pid" 2>/dev/null; then
            log "Save signal (SIGUSR1) sent to Ardour PID $pid"
            # Wait for save to complete
            sleep 3
            
            # Verify the process is still alive after save attempt
            if is_ardour_responsive "$pid"; then
                log "Ardour PID $pid responded to save signal"
                return 0
            else
                log "Ardour PID $pid became unresponsive after save signal"
                return 1
            fi
        else
            log "Unable to send save signal to Ardour PID $pid"
            return 1
        fi
    }
    
    # Function to gracefully terminate Ardour
    terminate_ardour_gracefully() {
        local pid=$1
        log "Attempting graceful termination of Ardour (PID: $pid)..."
        
        # Method 1: SIGTERM (graceful shutdown)
        if kill -TERM "$pid" 2>/dev/null; then
            log "SIGTERM sent to Ardour PID $pid"
            
            # Wait for graceful shutdown
            local wait_time=0
            local max_wait=10
            while kill -0 "$pid" 2>/dev/null && [[ $wait_time -lt $max_wait ]]; do
                sleep 1
                ((wait_time++))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                log "Ardour PID $pid did not respond to SIGTERM after ${max_wait}s"
                return 1
            else
                log "Ardour PID $pid terminated gracefully"
                return 0
            fi
        else
            log "Unable to send SIGTERM to Ardour PID $pid"
            return 1
        fi
    }
    
    # Function to force terminate Ardour (last resort)
    force_terminate_ardour() {
        local pid=$1
        log "Force terminating Ardour (PID: $pid)..."
        
        # Method 3: SIGKILL (force termination)
        if kill -KILL "$pid" 2>/dev/null; then
            log "SIGKILL sent to Ardour PID $pid"
            sleep 1
            
            # Verify termination
            if kill -0 "$pid" 2>/dev/null; then
                log "WARNING: Ardour PID $pid still active after SIGKILL"
                return 1
            else
                log "Ardour PID $pid force terminated"
                return 0
            fi
        else
            log "Unable to send SIGKILL to Ardour PID $pid"
            return 1
        fi
    }
    
    # Process each Ardour instance
    for pid in $ardour_pids; do
        log "Processing Ardour instance (PID: $pid)"
        
        # Check if process is responsive
        if ! is_ardour_responsive "$pid"; then
            log "Ardour PID $pid is not responsive, attempting force termination"
            force_terminate_ardour "$pid"
            continue
        fi
        
        # Attempt to save the session
        if save_ardour_session "$pid"; then
            log "Session save successful for PID $pid"
        else
            log "Session save failed for PID $pid, proceeding with termination"
        fi
        
        # Attempt graceful termination
        if terminate_ardour_gracefully "$pid"; then
            log "Graceful termination successful for PID $pid"
        else
            log "Graceful termination failed for PID $pid, attempting force termination"
            force_terminate_ardour "$pid"
        fi
        
        # Verify session files are intact after termination
        if [[ -f "$session_path" ]]; then
            local file_size=$(stat -c%s "$session_path" 2>/dev/null || echo "0")
            if [[ $file_size -gt 1000 ]]; then
                log "Session file verified: $session_path (${file_size} bytes)"
            else
                warn "Session file appears corrupted or empty: $session_path (${file_size} bytes)"
            fi
        fi
    done
    
    # Final verification
    local remaining_ardour=$(pgrep -x "ardour\|ardour8" 2>/dev/null || true)
    if [[ -n "$remaining_ardour" ]]; then
        warn "Some Ardour processes remain active: $remaining_ardour"
        # Attempt one final cleanup
        for pid in $remaining_ardour; do
            force_terminate_ardour "$pid"
        done
    else
        log "All Ardour sessions closed successfully"
    fi
    
    return 0
}

# Phase 0: Pre-startup and process management
phase0_pre_startup() {
    log "=== PHASE 0: PRE-STARTUP AND PROCESS MANAGEMENT ==="
    
    # Close existing Ardour sessions gracefully before cleanup
    close_ardour_sessions_gracefully
    
    # Execute audio cleanup
    log "Executing audio environment cleanup..."
    if [[ -f "$SCRIPT_DIR/phase0-audio-cleanup.sh" ]]; then
        bash "$SCRIPT_DIR/phase0-audio-cleanup.sh"
    else
        error "Script phase0-audio-cleanup.sh not found"
        exit 1
    fi
    
    # Execute lock file management
    log "Lock file and process management..."
    cleanup_lock_for_phase0
    if [[ -f "$SCRIPT_DIR/phase0-lock-management.sh" ]]; then
        bash "$SCRIPT_DIR/phase0-lock-management.sh"
    else
        error "Script phase0-lock-management.sh not found"
        exit 1
    fi
    restore_lock_after_phase0
}

# Phase 1: Real-time system optimization
phase1_rt_optimization() {
    log "=== PHASE 1: REAL-TIME SYSTEM OPTIMIZATION ==="
    
    if [[ -f "$SCRIPT_DIR/phase1-rt-optimization.sh" ]]; then
        bash "$SCRIPT_DIR/phase1-rt-optimization.sh"
    else
        error "Script phase1-rt-optimization.sh not found"
        exit 1
    fi
}

# Phase 2: JACK server initialization
phase2_jack_init() {
    log "=== PHASE 2: JACK SERVER INITIALIZATION ==="
    
    if [[ -f "$SCRIPT_DIR/phase2-hardware-config.sh" ]]; then
        # Execute with 60 second timeout to avoid blocking
        timeout 60 bash "$SCRIPT_DIR/phase2-hardware-config.sh" || {
            error "Phase 2 failed or timeout exceeded"
            exit 1
        }
    else
        error "Script phase2-hardware-config.sh not found"
        exit 1
    fi
}

# Phase 3: JACK server initialization (FIXED VERSION)
phase3_jack_init_fixed() {
    log "=== PHASE 3: JACK SERVER INITIALIZATION (FIXED) ==="
    
    if [[ -f "$SCRIPT_DIR/phase3-jack-init-fixed.sh" ]]; then
        # Execute with 120 second timeout to avoid blocking
        timeout 120 bash "$SCRIPT_DIR/phase3-jack-init-fixed.sh" || {
            error "Phase 3 failed or timeout exceeded"
            exit 1
        }
    else
        error "Script phase3-jack-init-fixed.sh not found"
        exit 1
    fi
}

# Phase 4: X11 environment setup
phase4_x11_setup() {
    log "=== PHASE 4: X11 ENVIRONMENT & DISPLAY MANAGEMENT ==="
    
    if [[ -f "$SCRIPT_DIR/phase4-x11-setup.sh" ]]; then
        bash "$SCRIPT_DIR/phase4-x11-setup.sh"
    else
        error "Script phase4-x11-setup.sh not found"
        exit 1
    fi
}

# Phase 5: Ardour DAW startup
phase5_ardour_startup() {
    log "=== PHASE 5: ARDOUR DAW STARTUP ==="
    
    # Ensure environment variables are properly passed
    export JACK_DEFAULT_SERVER="olms"
    export JACK_PROMISCUOUS_SERVER=1
    export JACK_NO_START_SERVER=1
    export TARGET_USER="$ACTUAL_USER"
    export TARGET_UID="$ACTUAL_UID"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$ACTUAL_UID/bus"
    export XDG_RUNTIME_DIR="/run/user/$ACTUAL_UID"
    export DISPLAY=":0"
    export XAUTHORITY="$ACTUAL_HOME/.Xauthority"
    
    if [[ -f "$SCRIPT_DIR/phase5-ardour-startup.sh" ]]; then
        log "Starting phase5-ardour-startup.sh script..."
        log "Environment variables set for user transition: $ACTUAL_USER"
        log "JACK_DEFAULT_SERVER=$JACK_DEFAULT_SERVER"
        log "TARGET_USER=$TARGET_USER"
        log "TARGET_UID=$TARGET_UID"
        bash "$SCRIPT_DIR/phase5-ardour-startup.sh"
        log "Script phase5-ardour-startup.sh completed"
    else
        error "Script phase5-ardour-startup.sh not found"
        exit 1
    fi
}

# Phase 6: Final System Report
phase6_final_report() {
    log "=== PHASE 6: FINAL SYSTEM REPORT ==="
    
    if [[ -f "$SCRIPT_DIR/phase6-final-report.sh" ]]; then
        bash "$SCRIPT_DIR/phase6-final-report.sh"
    else
        error "Script phase6-final-report.sh not found"
        exit 1
    fi
}

# Phase 6: CPU affinity & resource allocation
phase6_cpu_affinity() {
    log "=== PHASE 6: CPU AFFINITY & RESOURCE ALLOCATION ==="
    
    if [[ -f "$SCRIPT_DIR/phase6-cpu-affinity.sh" ]]; then
        bash "$SCRIPT_DIR/phase6-cpu-affinity.sh"
    else
        error "Script phase6-cpu-affinity.sh not found"
        exit 1
    fi
}

# Phase 7: System verification & monitoring
phase7_verification() {
    log "=== PHASE 7: SYSTEM VERIFICATION & MONITORING ==="
    
    if [[ -f "$SCRIPT_DIR/phase7-verification.sh" ]]; then
        bash "$SCRIPT_DIR/phase7-verification.sh"
    else
        error "Script phase7-verification.sh not found"
        exit 1
    fi
}

# Phase 8: Final system state
phase8_final_state() {
    log "=== PHASE 8: FINAL SYSTEM STATE & OPERATIONAL READINESS ==="
    
    if [[ -f "$SCRIPT_DIR/phase8-final-state.sh" ]]; then
        bash "$SCRIPT_DIR/phase8-final-state.sh"
    else
        error "Script phase8-final-state.sh not found"
        exit 1
    fi
}

# Main function
main() {
    log "Starting OLMS Startup Orchestrator v2.0"
    log "Script directory: $SCRIPT_DIR"
    log "Log file: $LOG_FILE"
    log "Startup mode: $MODE"
    
    # Verify necessary commands
    check_command "pgrep"
    check_command "pkill"
    check_command "kill"
    check_command "taskset"
    check_command "chrt"
    check_command "sysctl"
    
    # Check lock file
    check_lock
    
    # Execute phases based on mode
    if [[ "$MODE" == "test" ]]; then
        log "=== TEST MODE: Complete startup with graphical interface ==="
        phase0_pre_startup
        phase1_rt_optimization
        phase2_jack_init
        phase3_jack_init_fixed
        phase4_x11_setup
        # Pass mode to phase 5
        export OLMS_MODE="test"
        phase5_ardour_startup
    else
        log "=== HEADLESS MODE: Startup without graphical interface ==="
        phase0_pre_startup
        phase1_rt_optimization
        phase2_jack_init
        phase3_jack_init_fixed
        # Start Ardour in headless mode (without graphical interface)
        export OLMS_MODE="headless"
        phase5_ardour_startup
    fi
    phase6_final_report
    
    log "=== STARTUP COMPLETED SUCCESSFULLY ==="
    if [[ "$MODE" == "test" ]]; then
        log "OLMS is ready for real-time audio use with graphical interface"
    else
        log "OLMS is ready for real-time audio use in headless mode"
    fi
    
    # Remove cleanup trap since execution completed successfully
    trap - EXIT INT TERM
    
    # Remove lock file
    rm -f "$LOCK_FILE" "$PID_FILE"
}

# Execute main if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
