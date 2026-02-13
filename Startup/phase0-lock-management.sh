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

# Phase 0.1: Lock File Management & Process Cleanup
# Version: 2.0

set -euo pipefail

# Configuration
OLMS_HOME="$HOME/.olms"
mkdir -p "$OLMS_HOME"
LOCK_FILE="$OLMS_HOME/olms-startup.lock"
PID_FILE="$OLMS_HOME/olms-startup.pid"
LOG_FILE="$OLMS_HOME/olms-orchestrator.log"
STALE_TIMEOUT=10  # seconds

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    # Check if we can write to the log file
    if [[ -w "$LOG_FILE" ]] || [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
    else
        # If we can't write to the log file, write only to stdout
        echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
        warn "Unable to write to log file $LOG_FILE (permission denied)"
    fi
}

warn() {
    # Check if we can write to the log file
    if [[ -w "$LOG_FILE" ]] || [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
    else
        # If we can't write to the log file, write only to stdout
        echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
    fi
}

error() {
    # Check if we can write to the log file
    if [[ -w "$LOG_FILE" ]] || [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
    else
        # If we can't write to the log file, write only to stdout
        echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    fi
}

# Verify lock file staleness
check_lock_staleness() {
    if [[ ! -f "$LOCK_FILE" ]]; then
        log "No existing lock file"
        return 0
    fi
    
    local lock_mtime=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local age=$((current_time - lock_mtime))
    
    log "Existing lock file, age: ${age}s (timeout: ${STALE_TIMEOUT}s)"
    
    if [[ $age -gt $STALE_TIMEOUT ]]; then
        warn "Lock file considered stale (> ${STALE_TIMEOUT}s)"
        # Remove the stale lock file
        rm -f "$LOCK_FILE"
        return 0  # Proceed with cleanup
    fi
    
    # Verify if the PID is still active
    local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        warn "Lock file with PID $lock_pid still active, forced removal"
        # Force removal of the lock file even if the PID is active
        # This can happen if the process is zombie or if there's a bug
        rm -f "$LOCK_FILE"
        return 0
    fi
    
    # If the PID is not active, remove the "dead" lock file
    if [[ -n "$lock_pid" ]]; then
        warn "Lock file with PID $lock_pid no longer active, removing lock file"
        rm -f "$LOCK_FILE"
    fi
    
    return 0
}

# Terminate startup script processes
terminate_startup_processes() {
    log "Terminating existing startup script processes..."
    
    # Find all bash processes containing "olms-startup"
    local startup_pids=$(pgrep -f "olms-startup" 2>/dev/null || true)
    
    if [[ -z "$startup_pids" ]]; then
        log "No startup process found"
        return 0
    fi
    
    log "Startup processes found: $startup_pids"
    
    # Phase 1: SIGTERM (graceful)
    log "Sending SIGTERM to startup processes..."
    for pid in $startup_pids; do
        if kill -TERM "$pid" 2>/dev/null; then
            log "SIGTERM sent to PID $pid"
        else
            warn "Unable to send SIGTERM to PID $pid"
        fi
    done
    
    sleep 2
    
    # Phase 2: SIGKILL (forced)
    log "Sending SIGKILL to remaining processes..."
    local remaining_pids=$(pgrep -f "olms-startup" 2>/dev/null || true)
    for pid in $remaining_pids; do
        if kill -KILL "$pid" 2>/dev/null; then
            log "SIGKILL sent to PID $pid"
        else
            warn "Unable to send SIGKILL to PID $pid"
        fi
    done
    
    sleep 1
    
    # Final verification
    local final_pids=$(pgrep -f "olms-startup" 2>/dev/null || true)
    if [[ -n "$final_pids" ]]; then
        warn "Some startup processes were not terminated: $final_pids"
    else
        log "All startup processes have been terminated"
    fi
}

# Cleanup Ardour sessions
cleanup_ardour_sessions() {
    log "Cleaning up existing Ardour sessions..."
    
    # Use pgrep -x to avoid false positives (e.g., text editor opening files with "ardour" in the name)
    local ardour_pids=$(pgrep -x "ardour" 2>/dev/null || true)
    
    if [[ -z "$ardour_pids" ]]; then
        log "No Ardour session running"
        return 0
    fi
    
    log "Ardour sessions found: $ardour_pids"
    
    # Verify if Ardour is already running and if it's the same session we're about to start
    local current_session=$(ps -o pid,cmd -p $(pgrep -x ardour) 2>/dev/null | grep -v grep || true)
    if [[ -n "$current_session" ]]; then
        log "Ardour is already running with an active session"
        # Check if it's the same session we're about to start
        local session_path="$HOME/.olms/sessions/OLMS-POC"
        if [[ -f "$session_path/OLMS-POC.pending" ]]; then
            log "OLMS-POC session already running - skipping cleanup"
            return 0
        fi
    fi
    
    # Proceed with cleanup only if it's not the same session
    # Attempt to save sessions (if possible)
    log "Attempting to save Ardour sessions..."
    for pid in $ardour_pids; do
        # Verify that the PID exists before sending the signal
        if kill -0 "$pid" 2>/dev/null; then
            # Send SIGUSR1 for saving (if supported)
            if kill -USR1 "$pid" 2>/dev/null; then
                log "Save request sent to Ardour PID $pid"
            else
                warn "Unable to send save signal to Ardour PID $pid"
            fi
        else
            log "Ardour PID $pid no longer active (terminated between detection and saving)"
        fi
    done
    
    sleep 3
    
    # Forced termination with status verification
    log "Forced termination of Ardour sessions..."
    for pid in $ardour_pids; do
        # Verify that the PID exists before attempting termination
        if kill -0 "$pid" 2>/dev/null; then
            if kill -9 "$pid" 2>/dev/null; then
                log "Ardour PID $pid terminated"
            else
                warn "Error during kill of Ardour PID $pid"
            fi
        else
            log "Ardour PID $pid already terminated (no action needed)"
        fi
    done
    
    sleep 2
    
    # Final verification with timeout
    local max_attempts=5
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local remaining_ardour=$(pgrep -x "ardour" 2>/dev/null || true)
        if [[ -z "$remaining_ardour" ]]; then
            log "All Ardour sessions have been terminated"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            warn "Timeout: some Ardour sessions were not terminated after $max_attempts attempts: $remaining_ardour"
            warn "Startup procedure will continue but there might be conflicts"
            return 1
        fi
        
        log "Attempt $attempt/$max_attempts: remaining Ardour sessions: $remaining_ardour"
        sleep 1
        ((attempt++))
    done
}

# Clean temporary files
cleanup_temp_files() {
    log "Cleaning temporary files..."
    
    # Remove existing lock files
    rm -f "$LOCK_FILE" "$PID_FILE"
    
    # Remove specific temporary files
    rm -f /tmp/olms-*.tmp
    rm -f /tmp/jack-*.tmp
    
    log "Temporary files cleaned"
}

# Main function
main() {
    log "=== PHASE 0.1: LOCK FILE MANAGEMENT & PROCESS CLEANUP ==="
    
    # Verify staleness
    check_lock_staleness
    
    # Process termination
    terminate_startup_processes
    
    # Ardour cleanup
    cleanup_ardour_sessions
    
    # File cleanup
    cleanup_temp_files
    
    # Create the lock file for this execution (after cleanup)
    echo $$ > "$LOCK_FILE"
    
    log "Lock file management completed"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
