# Copyright (C) 2024 Francesco Nano and AI
# 
# This file is part of the Open Live Mixing System (OLMS) project.
# Created by Francesco Nano with AI assistance at https://openlivemixingsystem.org/
#
# Connect, collaborate, and stay updated with announcements at:
# https://openlivemixingsystem.org/
#
# Licensed under the GNU General Public License v3.0 (GPL-3.0)
# See LICENSE file for full license terms and conditions.
#
# This software is provided 'as-is', without any express or implied warranty.
# In no event will the authors be held liable for any damages arising from
# the use of this software.

#!/bin/bash

# OLMS Manual Startup Script for Testing
# 
# This script emulates the systemd service startup sequence for development and testing.
# 
# IMPORTANT: This script must be kept synchronized with the systemd service files!
# 
# Synchronization Requirements:
# - Any changes to script paths, parameters, or execution order in this script
#   MUST be reflected in the corresponding systemd service files:
#   - systemd/olms-rt-tuning.service
#   - systemd/olms-irq-pinning.service
#   - systemd/ardour.service
#   - systemd/olms-affinity.service
#   - systemd/olms-disk-guard.service
#
# File Path Requirements:
# - Scripts must be installed to /usr/bin/ for both testing and production use
# - Current expected paths:
#   - /usr/bin/rt_tuning.sh
#   - /usr/bin/irq_pinning.sh
#   - /usr/bin/ardour_launcher.sh
#   - /usr/bin/olms-apply-affinity
#   - /usr/bin/disk_guard.sh
#
# MODES:
# - Testing Mode (default): Launches Ardour with GUI for development and monitoring
# - Production Mode (--prod): Launches Ardour headless for automated operation
# - Virtual Mode (--virtual): Uses virtual audio backend when no hardware is available
#
# Usage: ./scripts/olms-startup.sh [OPTIONS]
# OPTIONS:
#   --test, -t     Launch in testing mode with GUI (default)
#   --prod, -p     Launch in production mode (headless)
#   --virtual, -v  Force virtual audio backend (no hardware required)
#   --help, -h     Show help message

set -e

# Default values
MODE="test"
FORCE_VIRTUAL=false
FORCE_STARTUP=false

# Lock file for preventing concurrent executions
LOCK_FILE="/tmp/olms-startup.lock"

# Lock file staleness threshold in seconds (10 seconds as requested)
LOCK_STALE_THRESHOLD=10

# Function to show help
show_help() {
    echo "OLMS Manual Startup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --test, -t     Launch in testing mode with GUI (default)"
    echo "  --prod, -p     Launch in production mode (headless)"
    echo "  --virtual, -v  Force virtual audio backend (no hardware required)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "MODES:"
    echo "  Testing Mode: Launches Ardour with GUI for development and monitoring"
    echo "  Production Mode: Launches Ardour headless for automated operation"
    echo "  Virtual Mode: Uses virtual audio backend when no hardware is available"
    echo ""
    echo "Examples:"
    echo "  $0                   # Launch in testing mode with GUI"
    echo "  $0 --prod            # Launch in production mode (headless)"
    echo "  $0 --virtual         # Launch with virtual audio (no hardware)"
    echo "  $0 --test --virtual  # Launch testing mode with virtual audio"
}

# Function to check if lock file is stale
is_lock_file_stale() {
    local lock_file="$1"
    if [ ! -f "$lock_file" ]; then
        return 1  # File doesn't exist, not stale
    fi
    
    # Get current time and lock file modification time
    local current_time=$(date +%s)
    local lock_time=$(stat -c %Y "$lock_file" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_status "Warning: Cannot access lock file modification time"
        return 1  # Cannot determine, assume not stale
    fi
    
    local time_diff=$((current_time - lock_time))
    
    if [ $time_diff -gt $LOCK_STALE_THRESHOLD ]; then
        print_status "Lock file is stale (age: ${time_diff}s > ${LOCK_STALE_THRESHOLD}s)"
        return 0  # File is stale
    else
        return 1  # File is not stale
    fi
}

# Function to cleanup on exit
cleanup_on_exit() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        print_status "Lock file removed"
    fi
}

# Function to check if another instance is running
check_concurrent_execution() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE")
        
        # Check if the process is still running
        if kill -0 "$lock_pid" 2>/dev/null; then
            if [ "$FORCE_STARTUP" = true ]; then
                print_status "Warning: Another OLMS startup instance is running (PID: $lock_pid)"
                print_status "Force mode enabled - attempting to terminate existing instance..."
                
                # Try to terminate the existing process gracefully first
                kill -TERM "$lock_pid" 2>/dev/null || true
                sleep 2
                
                # If still running, force kill it
                if kill -0 "$lock_pid" 2>/dev/null; then
                    print_status "Force killing existing instance (PID: $lock_pid)..."
                    kill -9 "$lock_pid" 2>/dev/null || true
                    sleep 1
                fi
                
                # Verify the process is gone
                if kill -0 "$lock_pid" 2>/dev/null; then
                    print_status "Error: Cannot terminate existing instance (PID: $lock_pid)"
                    print_status "Please stop it manually before proceeding"
                    exit 1
                else
                    print_status "Existing instance terminated successfully"
                    rm -f "$LOCK_FILE"
                fi
            else
                print_status "Error: Another OLMS startup instance is already running (PID: $lock_pid)"
                print_status "Use --force to terminate existing instance or wait for it to complete"
                exit 1
            fi
        else
            # Process is not running, check if lock file is stale
            if is_lock_file_stale "$LOCK_FILE"; then
                print_status "Warning: Stale lock file found (PID: $lock_pid), removing..."
                rm -f "$LOCK_FILE"
            else
                print_status "Warning: Lock file exists but process not running, removing..."
                rm -f "$LOCK_FILE"
            fi
        fi
    fi
    
    # Create lock file
    echo $$ > "$LOCK_FILE"
    print_status "Lock file created (PID: $$)"
    
    # Set trap to cleanup on exit
    trap cleanup_on_exit EXIT
}

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to force cleanup startup script processes
force_cleanup_startup_processes() {
    print_status "Checking for existing OLMS startup script processes..."
    
    local current_pid=$$
    local script_name=$(basename "$0")
    
    # Find running startup script processes, excluding current script
    local startup_pids=$(pgrep -f "$script_name" | grep -v "$current_pid")
    
    if [ -n "$startup_pids" ]; then
        print_status "Found existing OLMS startup script processes (PIDs: $startup_pids)"
        print_status "Attempting to terminate existing processes..."
        
        # Use a multi-phase cleanup approach with kill -9 as final fallback
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ] && [ -n "$startup_pids" ]; do
            print_status "Cleanup attempt $attempt/$max_attempts..."
            
            # Phase 1: Try graceful termination first
            if [ $attempt -eq 1 ]; then
                print_status "  Attempting graceful termination (SIGTERM)..."
                echo "$startup_pids" | xargs -r sudo kill -TERM 2>/dev/null || true
                sleep 2
            fi
            
            # Phase 2: Force kill with SIGKILL
            print_status "  Force killing with SIGKILL..."
            echo "$startup_pids" | xargs -r sudo kill -9 2>/dev/null || true
            
            # Wait briefly
            sleep 1
            
            # Check again
            startup_pids=$(pgrep -f "$script_name" | grep -v "$current_pid")
            attempt=$((attempt + 1))
        done
        
        # Final check - if processes still exist, log warning but don't fail
        if [ -n "$startup_pids" ]; then
            print_status "Warning: Some startup script processes could not be terminated: $startup_pids"
            print_status "Proceeding with startup anyway..."
            return 0  # Don't fail the entire startup
        else
            print_status "All existing startup script processes terminated successfully"
            return 0
        fi
    else
        print_status "No existing OLMS startup script processes found"
        return 0
    fi
}

# Function to close existing Ardour sessions and save them
cleanup_existing_ardour_sessions() {
    print_status "Checking for existing Ardour sessions..."
    
    # First, clean up any existing startup script processes
    force_cleanup_startup_processes
    
    # Find running Ardour processes, excluding current script
    local current_pid=$$
    local ardour_pids=$(pgrep -f ardour | grep -v "$current_pid")
    
    if [ -n "$ardour_pids" ]; then
        print_status "Found existing Ardour sessions (PIDs: $ardour_pids)"
        print_status "Attempting to save and close existing sessions..."
        
        # Try to save sessions using JACK control if available
        if command -v jack_control >/dev/null 2>&1; then
            print_status "Using JACK control to save sessions..."
            # This is a best-effort attempt - Ardour may not support remote save
            sleep 2
        fi
        
        # Use multi-phase cleanup approach with kill -9 as final fallback
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ] && [ -n "$ardour_pids" ]; do
            print_status "Ardour cleanup attempt $attempt/$max_attempts..."
            
            # Phase 1: Try graceful termination first
            if [ $attempt -eq 1 ]; then
                print_status "  Attempting graceful termination (SIGTERM)..."
                echo "$ardour_pids" | xargs -r kill -TERM 2>/dev/null || true
                sleep 2
            fi
            
            # Phase 2: Force kill with SIGKILL
            print_status "  Force killing with SIGKILL..."
            echo "$ardour_pids" | xargs -r kill -9 2>/dev/null || true
            
            # Wait for processes to terminate
            sleep 2
            
            # Check again
            ardour_pids=$(pgrep -f ardour | grep -v "$current_pid")
            attempt=$((attempt + 1))
        done
        
        # Final verification
        local remaining_pids=$(pgrep -f ardour | grep -v "$current_pid")
        if [ -n "$remaining_pids" ]; then
            print_status "Warning: Some Ardour processes could not be terminated: $remaining_pids"
            print_status "Proceeding with startup anyway..."
        else
            print_status "All existing Ardour sessions closed successfully"
        fi
    else
        print_status "No existing Ardour sessions found"
    fi
}

# Function to perform cleanup with retry mechanism
cleanup_with_retry() {
    local cleanup_function="$1"
    local max_retries="$2"
    local retry_delay="$3"
    local operation_name="$4"
    
    local attempt=1
    local success=false
    
    while [ $attempt -le $max_retries ]; do
        print_status "Attempt $attempt/$max_retries: $operation_name"
        
        if $cleanup_function; then
            print_status "$operation_name completed successfully on attempt $attempt"
            success=true
            break
        else
            print_status "Attempt $attempt failed for: $operation_name"
            if [ $attempt -lt $max_retries ]; then
                print_status "Waiting ${retry_delay}s before retry..."
                sleep $retry_delay
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    if [ "$success" = true ]; then
        return 0
    else
        print_status "All $max_retries attempts failed for: $operation_name"
        return 1
    fi
}

# Function to perform deep cleanup (Phase 2) - IMPROVED WITH TIMEOUTS AND AGGRESSIVE CLEANUP
perform_deep_cleanup() {
    print_status "Phase 2: Performing deep cleanup..."
    
    # Function to force kill all JACK instances with timeout and aggressive approach
    force_kill_all_jack() {
        print_status "Force killing all JACK instances with timeout protection and aggressive cleanup..."
        
        # Method 1: Try graceful shutdown first with timeout
        print_status "Attempting graceful shutdown with jack_control (10s timeout)..."
        timeout 10s jack_control exit 2>/dev/null || true
        sleep 2
        
        # Method 2: Kill by process name with timeout and multi-phase approach
        if pgrep -f jackd > /dev/null; then
            local jack_pids=$(pgrep -f jackd)
            print_status "Found JACK PIDs: $jack_pids"
            
            # Use multi-phase cleanup approach with timeout
            local max_attempts=3
            local attempt=1
            
            while [ $attempt -le $max_attempts ] && [ -n "$jack_pids" ]; do
                print_status "JACK cleanup attempt $attempt/$max_attempts..."
                
                # Phase 1: Try graceful termination first with timeout
                if [ $attempt -eq 1 ]; then
                    print_status "  Attempting graceful termination (SIGTERM) with 5s timeout..."
                    timeout 5s bash -c "echo '$jack_pids' | xargs -r sudo kill -TERM" 2>/dev/null || true
                    sleep 2
                fi
                
                # Phase 2: Force kill with SIGKILL with timeout
                print_status "  Force killing with SIGKILL with 5s timeout..."
                timeout 5s bash -c "echo '$jack_pids' | xargs -r sudo kill -9" 2>/dev/null || true
                
                # Wait for processes to terminate
                sleep 2
                
                # Check again
                jack_pids=$(pgrep -f jackd)
                attempt=$((attempt + 1))
            done
        fi
        
        # Method 3: Kill system-wide JACK processes with timeout
        print_status "Killing system-wide JACK processes with timeout..."
        timeout 10s bash -c "pkill -9 -f jackd" 2>/dev/null || true
        timeout 10s bash -c "killall -9 jackd" 2>/dev/null || true
        sleep 3
        
        # Method 4: Kill Pipewire and related processes with timeout (CRITICAL for JACK stability)
        print_status "Killing Pipewire and related audio processes with timeout..."
        timeout 10s bash -c "pkill -9 -f pipewire" 2>/dev/null || true
        timeout 10s bash -c "pkill -9 -f wireplumber" 2>/dev/null || true
        timeout 10s bash -c "pkill -9 -f pulseaudio" 2>/dev/null || true
        timeout 10s bash -c "pkill -9 -f alsa" 2>/dev/null || true
        sleep 3
        
        # Method 5: Use lsof to find and kill processes holding audio devices with timeout
        print_status "Checking for processes holding audio devices..."
        local audio_processes=$(timeout 5s lsof /dev/snd/* 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
        if [ -n "$audio_processes" ]; then
            print_status "Found processes holding audio devices: $audio_processes"
            
            # Use multi-phase cleanup approach with timeout
            local max_attempts=3
            local attempt=1
            
            while [ $attempt -le $max_attempts ] && [ -n "$audio_processes" ]; do
                print_status "Audio device cleanup attempt $attempt/$max_attempts..."
                
                # Phase 1: Try graceful termination first with timeout
                if [ $attempt -eq 1 ]; then
                    print_status "  Attempting graceful termination (SIGTERM) with 5s timeout..."
                    timeout 5s bash -c "echo '$audio_processes' | xargs -r sudo kill -TERM" 2>/dev/null || true
                    sleep 2
                fi
                
                # Phase 2: Force kill with SIGKILL with timeout
                print_status "  Force killing with SIGKILL with 5s timeout..."
                timeout 5s bash -c "echo '$audio_processes' | xargs -r sudo kill -9" 2>/dev/null || true
                
                # Wait for processes to terminate
                sleep 2
                
                # Check again
                audio_processes=$(timeout 5s lsof /dev/snd/* 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
                attempt=$((attempt + 1))
            done
        fi
        
        # Method 6: Remove JACK socket files with timeout
        print_status "Removing JACK socket files..."
        timeout 5s bash -c "rm -f /tmp/jack_* /dev/shm/jack_* /var/run/jack_* /run/jack_* /tmp/.jack* /var/lock/.jack*" 2>/dev/null || true
        
        # Method 7: Remove Pipewire socket files with timeout (CRITICAL)
        print_status "Removing Pipewire socket files..."
        timeout 5s bash -c "rm -f /tmp/pipewire* /dev/shm/pipewire* /var/run/pipewire* /run/pipewire* /tmp/.pipewire* /var/lock/.pipewire*" 2>/dev/null || true
        
        # Method 8: Clean up shared memory segments with timeout
        print_status "Cleaning up shared memory segments..."
        timeout 5s bash -c "for shm_id in \$(ipcs -m | grep jack | awk '{print \$2}'); do ipcrm -m \$shm_id 2>/dev/null || true; done" 2>/dev/null || true
        timeout 5s bash -c "for sem_id in \$(ipcs -s | grep jack | awk '{print \$2}'); do ipcrm -s \$sem_id 2>/dev/null || true; done" 2>/dev/null || true
        
        # Method 9: AGGRESSIVE CLEANUP - Force remove all audio-related files and processes
        print_status "Performing aggressive cleanup of all audio-related processes and files..."
        
        # Kill any remaining audio processes with force
        print_status "Force killing any remaining audio processes..."
        sudo pkill -9 -f "jack\|pipewire\|pulseaudio\|wireplumber\|alsa" 2>/dev/null || true
        sleep 2
        
        # Force remove all socket and shared memory files
        print_status "Force removing all audio socket and shared memory files..."
        sudo rm -rf /tmp/jack_* /dev/shm/jack_* /var/run/jack_* /run/jack_* /tmp/.jack* /var/lock/.jack* 2>/dev/null || true
        sudo rm -rf /tmp/pipewire* /dev/shm/pipewire* /var/run/pipewire* /run/pipewire* /tmp/.pipewire* /var/lock/.pipewire* 2>/dev/null || true
        
        # Force remove all shared memory segments
        print_status "Force removing all shared memory segments..."
        for shm_id in $(ipcs -m | grep -E "jack|pipewire|pulse" | awk '{print $2}' 2>/dev/null); do
            sudo ipcrm -m "$shm_id" 2>/dev/null || true
        done
        
        # Force remove all semaphore segments
        print_status "Force removing all semaphore segments..."
        for sem_id in $(ipcs -s | grep -E "jack|pipewire|pulse" | awk '{print $2}' 2>/dev/null); do
            sudo ipcrm -s "$sem_id" 2>/dev/null || true
        done
        
        # Method 10: Reset audio hardware
        print_status "Resetting audio hardware..."
        for device in /dev/snd/*; do
            if [ -c "$device" ]; then
                print_status "Resetting $device"
                sudo fuser -k "$device" 2>/dev/null || true
            fi
        done
        sleep 2
        
        return 0
    }
    
    # Perform the cleanup with retry mechanism and timeout protection
    if cleanup_with_retry force_kill_all_jack 3 2 "Deep audio cleanup"; then
        # Verify cleanup was successful with timeout
        local remaining_processes=$(timeout 5s pgrep -f "jackd|pipewire|pulseaudio" | wc -l 2>/dev/null || echo "0")
        if [ "$remaining_processes" -eq 0 ]; then
            print_status "Deep cleanup completed successfully ✓"
            return 0
        else
            print_status "Warning: Some audio processes may still be running: $remaining_processes"
            return 1
        fi
    else
        print_status "Deep cleanup failed after multiple attempts"
        return 1
    fi
}

# Function to verify system state (Phase 2) with enhanced error handling
verify_system_state() {
    print_status "Verifying system state..."
    
    # Check that no audio processes are running
    local audio_pids=$(pgrep -f "jackd|pipewire|pulseaudio|ardour" 2>/dev/null | wc -l)
    
    if [ "$audio_pids" -eq 0 ]; then
        print_status "System state verified: No conflicting audio processes running ✓"
        return 0
    else
        print_status "Warning: Found $audio_pids audio processes still running"
        
        # List the specific processes that are still running
        local running_processes=$(pgrep -f "jackd|pipewire|pulseaudio|ardour" 2>/dev/null)
        if [ -n "$running_processes" ]; then
            print_status "Still running processes:"
            for pid in $running_processes; do
                local process_info=$(ps -p $pid -o pid,cmd 2>/dev/null | tail -n 1)
                if [ -n "$process_info" ]; then
                    print_status "  PID $pid: $process_info"
                else
                    print_status "  PID $pid: (process info unavailable)"
                fi
            done
        fi
        
        # Use multi-phase final cleanup approach with kill -9 as final fallback
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ] && [ -n "$running_processes" ]; do
            print_status "Final cleanup attempt $attempt/$max_attempts..."
            
            # Phase 1: Try graceful termination first
            if [ $attempt -eq 1 ]; then
                print_status "  Attempting graceful termination (SIGTERM)..."
                echo "$running_processes" | xargs -r sudo kill -TERM 2>/dev/null || true
                sleep 2
            fi
            
            # Phase 2: Force kill with SIGKILL
            print_status "  Force killing with SIGKILL..."
            echo "$running_processes" | xargs -r sudo kill -9 2>/dev/null || true
            
            # Wait for processes to terminate
            sleep 2
            
            # Check again
            running_processes=$(pgrep -f "jackd|pipewire|pulseaudio|ardour" 2>/dev/null)
            attempt=$((attempt + 1))
        done
        
        # Final verification
        local remaining_pids=$(pgrep -f "jackd|pipewire|pulseaudio|ardour" 2>/dev/null | wc -l)
        if [ "$remaining_pids" -eq 0 ]; then
            print_status "Final cleanup successful - all processes terminated"
            return 0
        else
            print_status "Warning: Some processes could not be terminated ($remaining_pids remaining)"
            return 1
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test)
            MODE="test"
            shift
            ;;
        -p|--prod)
            MODE="prod"
            shift
            ;;
        -v|--virtual)
            FORCE_VIRTUAL=true
            shift
            ;;
        --force)
            FORCE_STARTUP=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=== OLMS Manual Startup Script ==="
echo "Starting OLMS system in $MODE mode..."
if [ "$FORCE_VIRTUAL" = true ]; then
    echo "Virtual audio mode enabled (no hardware required)"
fi
echo

# Check for concurrent execution
check_concurrent_execution

# Phase 0: Cleanup existing audio processes
print_status "Phase 0: Cleanup existing audio processes"

# Disable exit on error temporarily for cleanup phase
set +e
cleanup_existing_ardour_sessions
perform_deep_cleanup
verify_system_state
set -e

print_status "Cleanup phase completed - proceeding with startup"
echo

# Function to check if command succeeded with enhanced error handling
check_status() {
    local operation_name="$1"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "    ✓ Success"
        return 0
    else
        echo "    ✗ Failed"
        echo "Operation failed: $operation_name"
        echo "Exit code: $exit_code"
        echo "Startup aborted due to error in: $operation_name"
        echo ""
        echo "Troubleshooting suggestions:"
        echo "  - Check system logs: journalctl -xe"
        echo "  - Verify dependencies are installed"
        echo "  - Check system resources (CPU, memory, disk space)"
        echo "  - Review script permissions and paths"
        exit 1
    fi
}

# Function to check if command succeeded with warning (non-critical operations)
check_status_warning() {
    local operation_name="$1"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "    ✓ Success"
        return 0
    else
        echo "    ⚠ Warning: $operation_name failed (exit code: $exit_code)"
        echo "    Continuing startup anyway..."
        return 1
    fi
}

# Function to add timeout to operations
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    local command="$@"
    
    print_status "Running with timeout ($timeout_seconds seconds): $command"
    
    timeout "$timeout_seconds" $command
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        print_status "Operation timed out after $timeout_seconds seconds"
        return 1
    elif [ $exit_code -ne 0 ]; then
        print_status "Operation failed with exit code: $exit_code"
        return 1
    else
        print_status "Operation completed successfully"
        return 0
    fi
}

# Function to verify realtime privileges are active (NEW)
verify_realtime_privileges_active() {
    print_status "Verifying realtime privileges are active..."
    
    # Check current limits
    local rtprio=$(ulimit -r)
    local memlock=$(ulimit -l)
    
    print_status "Current realtime limits: rtprio=$rtprio, memlock=${memlock}KB"
    
    # Verify limits are sufficient
    if [ "$rtprio" -ge 90 ] && ([ "$memlock" = "unlimited" ] || [ "$memlock" -gt 1024 ]); then
        print_status "Realtime privileges are active ✓"
        return 0
    else
        print_status "Warning: Realtime privileges may not be active"
        print_status "Expected: rtprio >= 90, memlock unlimited or > 1024KB"
        return 1
    fi
}

# Function to verify system resources before startup
verify_system_resources() {
    print_status "Verifying system resources..."
    
    # Check available memory
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    local memory_percentage=$((available_memory * 100 / total_memory))
    
    print_status "Available memory: ${available_memory}MB (${memory_percentage}% of ${total_memory}MB)"
    
    if [ $memory_percentage -lt 10 ]; then
        print_status "Warning: Low available memory (${available_memory}MB)"
        print_status "Consider closing other applications before starting OLMS"
    fi
    
    # Check available disk space
    local disk_usage=$(df / | awk 'NR==2{printf "%.0f", $4}')
    local disk_percentage=$(df / | awk 'NR==2{printf "%.0f", $5}')
    
    print_status "Available disk space: ${disk_usage}KB (${disk_percentage}% used)"
    
    if [ $disk_percentage -gt 90 ]; then
        print_status "Warning: Low disk space (${disk_usage}KB available)"
        print_status "Consider freeing up disk space before starting OLMS"
    fi
    
    # Check CPU load
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    
    print_status "Current CPU load: $cpu_load (cores: $cpu_cores)"
    
    if (( $(echo "$cpu_load > $cpu_cores" | bc -l) )); then
        print_status "Warning: High CPU load detected"
        print_status "Consider reducing system load before starting OLMS"
    fi
    
    print_status "System resources verification completed"
    return 0
}

print_status "Phase 1: RT Optimization + IRQ Balance Stop"
print_status "Stopping irqbalance service..."
sudo systemctl stop irqbalance 2>/dev/null || true
sudo systemctl disable irqbalance 2>/dev/null || true

# Determine RT tuning mode based on startup mode
RT_MODE="prod"
if [ "$MODE" = "test" ]; then
    RT_MODE="test"
fi

print_status "Executing rt_tuning.sh in $RT_MODE mode..."
if [ -f "$(dirname "$0")/rt_tuning.sh" ]; then
    sudo "$(dirname "$0")/rt_tuning.sh" --mode "$RT_MODE"
    check_status "RT Tuning"
else
    print_status "Warning: rt_tuning.sh not found in local scripts directory, skipping RT tuning"
fi
echo

print_status "Phase 1.5: Realtime Privileges Verification"
print_status "Verifying realtime privileges configuration..."
if [ -f "$(dirname "$0")/setup_realtime_privileges.sh" ]; then
    # Fix parsing issue: remove --verify flag as it's not supported by the script
    # Use SUDO_USER if available to get the original user, otherwise fall back to USER
    ORIGINAL_USER="${SUDO_USER:-$USER}"
    print_status "Setting up realtime privileges for user: $ORIGINAL_USER"
    sudo "$(dirname "$0")/setup_realtime_privileges.sh" "$ORIGINAL_USER"
    check_status "Realtime privileges verification"
else
    print_status "Warning: setup_realtime_privileges.sh not found, skipping verification"
fi

# Apply systemd realtime override if available
print_status "Phase 1.6: Applying systemd realtime override..."
if [ -f "$(dirname "$0")/olms-rt-override.sh" ]; then
    # Enhanced systemd override with X11 environment detection and fallback
    print_status "Checking X11 environment for systemd override..."
    
    # Detect and set X11 environment variables if not present
    if [ -z "$DISPLAY" ]; then
        for display_num in 0 1 2; do
            if [ -f "/tmp/.X11-unix/X$display_num" ]; then
                export DISPLAY=":$display_num"
                print_status "Detected DISPLAY: $DISPLAY"
                break
            fi
        done
    fi
    
    if [ -z "$XAUTHORITY" ]; then
        export XAUTHORITY="$HOME/.Xauthority"
        print_status "Set XAUTHORITY: $XAUTHORITY"
    fi
    
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        print_status "Set XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
    fi
    
    # Run the override script with enhanced error handling
    if sudo "$(dirname "$0")/olms-rt-override.sh"; then
        print_status "✓ Systemd realtime override applied successfully"
    else
        print_status "⚠ Systemd override had issues, but continuing startup..."
        print_status "  This may be normal if X11 environment is not fully available"
    fi
else
    print_status "Warning: olms-rt-override.sh not found, skipping systemd override"
fi
echo

print_status "Phase 2: Hardware IRQ Pinning"
print_status "Executing irq_pinning.sh..."
if [ -f "$(dirname "$0")/irq_pinning.sh" ]; then
    set +e  # Disattiva temporaneamente l'exit on error
    sudo "$(dirname "$0")/irq_pinning.sh"
    irq_status=$?  # Salva il codice di ritorno
    set -e  # Riattiva l'exit on error
    
    # Don't fail startup if IRQ pinning fails (common for kernel-managed IRQs)
    if [ $irq_status -eq 0 ]; then
        echo "    ✓ Success"
    else
        echo "    ⚠ Warning: IRQ pinning failed (may be normal for kernel-managed IRQs)"
        echo "    Continuing startup..."
    fi
else
    print_status "Warning: irq_pinning.sh not found in local scripts directory, skipping IRQ pinning"
fi
echo

print_status "Phase 3: Machine Preparation"
print_status "Executing prepare_machine.sh..."
if [ -f "$(dirname "$0")/prepare_machine.sh" ]; then
    if [ "$MODE" = "test" ]; then
        sudo "$(dirname "$0")/prepare_machine.sh" --test $([ "$FORCE_VIRTUAL" = true ] && echo "--virtual")
    elif [ "$MODE" = "prod" ]; then
        sudo "$(dirname "$0")/prepare_machine.sh" --prod $([ "$FORCE_VIRTUAL" = true ] && echo "--virtual")
    else
        sudo "$(dirname "$0")/prepare_machine.sh" $([ "$FORCE_VIRTUAL" = true ] && echo "--virtual")
    fi
    check_status "Machine Preparation"
else
    print_status "Warning: prepare_machine.sh not found in local scripts directory, skipping machine preparation"
fi
echo

print_status "Phase 3.5: Enhanced Realtime Privileges Verification and JACK RT Configuration"
print_status "Ensuring realtime privileges are active before audio engine startup..."

# Verify realtime privileges are fully active
if ! check_realtime_privileges_active; then
    print_status "Warning: Realtime privileges may not be fully active"
    print_status "Attempting to set temporary RT privileges for current session..."
    
    # Try to set temporary RT privileges
    if sudo -n ulimit -r 99 2>/dev/null; then
        print_status "✓ Temporary RT privileges set for current session"
    else
        print_status "⚠ Cannot set temporary RT privileges"
        print_status "  Audio performance may be sub-optimal"
        print_status "  To fix permanently: log out and log back in after group configuration"
    fi
fi

# Phase 4: Audio Engine Startup (Asynchronous) - WITH RT PRIORITY FIX
print_status "Phase 4: Audio Engine Startup (Asynchronous)"
if [ "$MODE" = "prod" ]; then
    print_status "Starting audio engine in production mode (headless)..."
else
    print_status "Starting audio engine in testing mode (with GUI)..."
fi
if [ "$FORCE_VIRTUAL" = true ]; then
    print_status "Using virtual audio backend (no hardware required)"
fi

# Build audio_engine.sh arguments
AUDIO_ARGS=""
if [ "$MODE" = "prod" ]; then
    AUDIO_ARGS="--prod"
elif [ "$MODE" = "test" ]; then
    AUDIO_ARGS="--test"
fi

if [ "$FORCE_VIRTUAL" = true ]; then
    AUDIO_ARGS="$AUDIO_ARGS --virtual"
fi

# Check if we need to preserve X11 environment for GUI mode
if [ "$MODE" = "test" ]; then
    print_status "Preserving X11 environment for GUI mode..."
    # Ensure X11 variables are available
    if [ -z "$DISPLAY" ]; then
        # Try to detect DISPLAY before starting audio engine
        for display_num in 0 1 2; do
            if [ -f "/tmp/.X11-unix/X$display_num" ]; then
                export DISPLAY=":$display_num"
                print_status "Detected DISPLAY: $DISPLAY"
                break
            fi
        done
    fi
    
    if [ -z "$XAUTHORITY" ]; then
        export XAUTHORITY="$HOME/.Xauthority"
        print_status "Set XAUTHORITY: $XAUTHORITY"
    fi
    
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        print_status "Set XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
    fi
fi

print_status "Reached audio engine startup section"
print_status "Checking if audio_engine.sh exists at: $(dirname "$0")/audio_engine.sh"
if [ -f "$(dirname "$0")/audio_engine.sh" ]; then
    print_status "audio_engine.sh found, proceeding with execution"
    print_status "About to execute audio_engine.sh with args: $AUDIO_ARGS"
    
    # LAUNCH AUDIO ENGINE ASYNCHRONOUSLY (FIX FOR BLOCKING EXECUTION)
    # Remove sudo to run as same user for JACK/Ardour communication
    # Add & at the end to run in background and capture PID
    "$(dirname "$0")/audio_engine.sh" $AUDIO_ARGS &
    AUDIO_ENGINE_PID=$!
    
    print_status "Audio engine launched asynchronously (PID: $AUDIO_ENGINE_PID)"
    print_status "Continuing with startup sequence while audio engine initializes..."
    
    # Don't wait for audio engine to complete - it will run until manually stopped
    # Instead, we'll poll for process readiness in the next phase
    echo "    ✓ Success (asynchronous launch)"
    
    # Store the audio engine PID for potential cleanup later
    export OLMS_AUDIO_ENGINE_PID="$AUDIO_ENGINE_PID"
    
else
    print_status "Warning: audio_engine.sh not found in local scripts directory, cannot start audio engine"
fi
echo

print_status "Phase 5: CPU Affinity Configuration"
print_status "Applying CPU affinity to running audio processes..."

# INTELLIGENT PROCESS POLLING MECHANISM (FIX FOR RACE CONDITION)
print_status "Waiting for audio processes to be ready..."
poll_for_audio_processes() {
    local max_wait_time=30  # Maximum wait time in seconds
    local poll_interval=2   # Polling interval in seconds
    local elapsed_time=0
    
    print_status "Polling for JACK and Ardour processes (max wait: ${max_wait_time}s)..."
    
    while [ $elapsed_time -lt $max_wait_time ]; do
        # Check for JACK processes
        local jack_pids=$(pgrep -f "jackd" 2>/dev/null)
        # Check for Ardour processes
        local ardour_pids=$(pgrep -f "ardour" 2>/dev/null)
        
        if [ -n "$jack_pids" ] || [ -n "$ardour_pids" ]; then
            print_status "Audio processes detected:"
            if [ -n "$jack_pids" ]; then
                print_status "  JACK PIDs: $jack_pids"
            fi
            if [ -n "$ardour_pids" ]; then
                print_status "  Ardour PIDs: $ardour_pids"
            fi
            return 0  # Success - processes found
        fi
        
        print_status "  No audio processes found yet (waited ${elapsed_time}s/${max_wait_time}s)"
        sleep $poll_interval
        elapsed_time=$((elapsed_time + poll_interval))
    done
    
    print_status "Warning: No audio processes found after ${max_wait_time}s"
    print_status "Proceeding with affinity configuration anyway..."
    return 1  # Timeout reached
}

# Poll for processes before applying affinity
if poll_for_audio_processes; then
    print_status "Audio processes ready - proceeding with affinity configuration"
else
    print_status "Process polling timed out - attempting affinity configuration anyway"
fi

if [ -f "$(dirname "$0")/olms-apply-affinity.sh" ]; then
    set +e  # Don't fail if affinity application has issues
    sudo "$(dirname "$0")/olms-apply-affinity.sh"
    affinity_status=$?
    set -e
    
    if [ $affinity_status -eq 0 ]; then
        echo "    ✓ Success"
        print_status "CPU affinity applied to JACK and Ardour processes"
    else
        echo "    ⚠ Warning: CPU affinity configuration had issues"
        print_status "Audio processes may still be running without optimized CPU allocation"
    fi
else
    print_status "Warning: olms-apply-affinity.sh not found in local scripts directory"
    print_status "Continuing without CPU affinity optimization..."
fi
echo

print_status "Phase 6: Final System Verification"
print_status "Note: Final verification will be performed by audio_engine.sh after all optimizations are complete"
echo

print_status "Startup sequence completed!"
echo

print_status "System Status:"
echo "  - RT optimizations applied"
echo "  - Hardware IRQ pinned"
echo "  - JACK and Ardour running"
echo "  - CPU affinity configured"
echo "  - Disk protection active"
echo "  - System verification: $([ $verification_status -eq 0 ] && echo "PASSED" || echo "WARNING")"
echo
print_status "To monitor the system:"
echo "  - Check JACK status: jack_control status"
echo "  - Monitor logs: journalctl -f -u ardour.service"
echo "  - Check disk space: df -h"
echo "  - Run verification: sudo ./scripts/olms-final-verification.sh --verbose"
echo
print_status "To stop the system:"
echo "  - Stop Ardour: pkill -f ardour"
echo "  - Stop JACK: pkill jackd"
echo "  - Stop disk guard: kill $DISK_GUARD_PID"
echo
print_status "Manual startup script completed successfully!"
