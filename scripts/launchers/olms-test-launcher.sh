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

# OLMS Test Launcher
# 
# This script launches the OLMS system in testing mode with GUI for development and monitoring.
# It provides a complete startup sequence with visual feedback and error handling.
# 
# Usage: ./scripts/launchers/olms-test-launcher.sh
# 
# This script is designed for development and testing environments where visual feedback
# and debugging capabilities are essential.

set -e

# Script information
SCRIPT_NAME="OLMS Test Launcher"
SCRIPT_VERSION="1.0"
SCRIPT_DESCRIPTION="Launches OLMS system in testing mode with GUI"

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to print error messages
print_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

# Function to print success messages
print_success() {
    echo "[$(date '+%H:%M:%S')] SUCCESS: $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1 completed successfully"
    else
        print_error "$1 failed"
        echo "Test launcher aborted due to error in: $1"
        exit 1
    fi
}

# Function to show help
show_help() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "$SCRIPT_DESCRIPTION"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --help, -h     Show this help message"
    echo "  --verbose, -v  Enable verbose output"
    echo ""
    echo "This script launches the OLMS system in testing mode with GUI for"
    echo "development and monitoring. It provides comprehensive error handling"
    echo "and status reporting throughout the startup sequence."
    echo ""
    echo "Examples:"
    echo "  $0                    # Launch in testing mode with GUI"
    echo "  $0 --verbose          # Launch with verbose output"
    echo "  $0 --help             # Show help message"
}

# Parse command line arguments
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Print header
echo "=== $SCRIPT_NAME v$SCRIPT_VERSION ==="
echo "Description: $SCRIPT_DESCRIPTION"
echo "Mode: Testing (with GUI)"
echo "Timestamp: $(date)"
echo

# Check if we're in the correct directory
if [ ! -f "scripts/olms-startup.sh" ]; then
    print_error "OLMS-Core directory not found. Please run this script from the OLMS-Core root directory."
    exit 1
fi

print_status "Starting OLMS Test Launcher..."
echo

# Phase 1: System Check
print_status "Phase 1: System Prerequisites Check"
print_status "Verifying system requirements..."

# Check if running as root (required for some operations)
if [ "$EUID" -ne 0 ]; then
    print_status "Note: Some operations may require root privileges"
    print_status "The startup script will prompt for sudo when needed"
fi

# Check if JACK is available
if ! command -v jack_control &> /dev/null; then
    print_status "Warning: JACK control tools not found"
    print_status "Audio functionality may be limited"
else
    print_status "JACK control tools found"
fi

# Check if Ardour is available
if ! command -v ardour8 &> /dev/null; then
    print_status "Warning: Ardour not found"
    print_status "Audio engine functionality may be limited"
else
    print_status "Ardour found"
fi

print_status "System check completed"
echo

# Phase 2: Launch OLMS Startup Script
print_status "Phase 2: Launching OLMS Startup Sequence"
print_status "Executing: ./scripts/olms-startup.sh --test"

# Launch the main startup script in testing mode
if [ "$VERBOSE" = true ]; then
    ./scripts/olms-startup.sh --test --verbose
else
    ./scripts/olms-startup.sh --test
fi

check_status "OLMS startup sequence"
echo

# Phase 3: Post-Startup Verification
print_status "Phase 3: Post-Startup System Verification"
print_status "Verifying system status..."

# Check JACK status
print_status "Checking JACK status..."
if command -v jack_control &> /dev/null; then
    if jack_control status | grep -q "server is active"; then
        print_success "JACK server is active"
    else
        print_status "JACK server status: inactive or not running"
    fi
else
    print_status "JACK control tools not available for status check"
fi

# Check Ardour processes
print_status "Checking Ardour processes..."
ARDOUR_COUNT=$(pgrep -c ardour 2>/dev/null || echo "0")
if [ "$ARDOUR_COUNT" -gt 0 ]; then
    print_success "Ardour processes found: $ARDOUR_COUNT"
    if [ "$VERBOSE" = true ]; then
        pgrep -l ardour
    fi
else
    print_status "No Ardour processes found"
fi

# Check JACK processes
print_status "Checking JACK processes..."
JACK_COUNT=$(pgrep -c jackd 2>/dev/null || echo "0")
if [ "$JACK_COUNT" -gt 0 ]; then
    print_success "JACK processes found: $JACK_COUNT"
    if [ "$VERBOSE" = true ]; then
        pgrep -l jackd
    fi
else
    print_status "No JACK processes found"
fi

print_status "Post-startup verification completed"
echo

# Phase 4: System Status Summary
print_status "Phase 4: System Status Summary"
echo "=== System Status ==="
echo "  - OLMS startup sequence: Completed"
echo "  - JACK server: $([ "$JACK_COUNT" -gt 0 ] && echo "Active" || echo "Inactive")"
echo "  - Ardour processes: $([ "$ARDOUR_COUNT" -gt 0 ] && echo "Running ($ARDOUR_COUNT)" || echo "Not running")"
echo "  - Testing mode: Enabled (GUI available)"
echo "  - Verbose output: $([ "$VERBOSE" = true ] && echo "Enabled" || echo "Disabled")"
echo

# Phase 5: User Instructions
print_status "Phase 5: User Instructions"
echo "=== Test Environment Instructions ==="
echo "  - Ardour GUI should be visible (if not running headless)"
echo "  - JACK server is running for audio processing"
echo "  - System is ready for development and testing"
echo "  - Monitor system logs for any issues:"
echo "    - Check JACK status: jack_control status"
echo "    - List JACK ports: jack_lsp"
echo "    - Monitor logs: journalctl -f"
echo "  - To stop the system:"
echo "    - Stop Ardour: pkill -f ardour"
echo "    - Stop JACK: pkill jackd"
echo

# Phase 6: Launch Monitoring (Optional)
if [ "$VERBOSE" = true ]; then
    print_status "Phase 6: Launching System Monitor"
    echo "=== System Monitor ==="
    echo "Monitoring system processes (press Ctrl+C to exit):"
    echo
    
    # Show system processes
    echo "Active audio processes:"
    ps aux | grep -E "(ardour|jack)" | grep -v grep || echo "No audio processes found"
    echo
    
    # Show JACK connections (if available)
    if command -v jack_lsp &> /dev/null; then
        echo "JACK ports:"
        jack_lsp || echo "JACK not running or no ports available"
        echo
    fi
    
    # Show system resources
    echo "System resources:"
    echo "CPU usage:"
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1"%"}'
    echo "Memory usage:"
    free -h | grep "Mem:" | awk '{print "Memory Usage: " $3 "/" $2 " (" $5 " available)"}'
    echo
fi

print_status "=== OLMS Test Launcher Complete ==="
print_success "OLMS system is now running in testing mode"
print_status "GUI is available for development and monitoring"
echo
print_status "Monitoring Ardour startup (this will keep the terminal open)..."
echo

# Phase 6: Monitor Ardour Startup
print_status "Phase 6: Monitoring Ardour Startup"
print_status "Waiting for Ardour GUI to become available..."

# Function to check if Ardour is running
check_ardour_status() {
    local ardour_pids=$(pgrep -f ardour 2>/dev/null)
    if [ -n "$ardour_pids" ]; then
        echo "Ardour processes found: $ardour_pids"
        for pid in $ardour_pids; do
            local process_info=$(ps -p $pid -o pid,cmd 2>/dev/null | tail -n 1)
            if [ -n "$process_info" ]; then
                echo "  PID $pid: $process_info"
            fi
        done
        return 0
    else
        return 1
    fi
}

# Wait for Ardour to start with timeout
MAX_WAIT_TIME=60
WAIT_INTERVAL=3
elapsed_time=0

while [ $elapsed_time -lt $MAX_WAIT_TIME ]; do
    if check_ardour_status; then
        print_success "Ardour is now running and ready!"
        break
    else
        print_status "Ardour not yet ready (waited ${elapsed_time}s/${MAX_WAIT_TIME}s)"
        sleep $WAIT_INTERVAL
        elapsed_time=$((elapsed_time + WAIT_INTERVAL))
    fi
done

# Final check
if ! check_ardour_status; then
    print_status "Warning: Ardour may still be starting up"
    print_status "Check the system manually if needed"
fi

echo
print_status "To monitor the system:"
echo "  - Check JACK status: jack_control status"
echo "  - Monitor logs: journalctl -f -u ardour.service"
echo "  - Check system resources: top, htop"
echo
print_status "To stop the system:"
echo "  - Stop Ardour: pkill -f ardour"
echo "  - Stop JACK: pkill jackd"
echo "  - Stop any background processes from this script"
echo
print_status "Test launcher completed successfully!"
print_status "Terminal will remain open for monitoring. Press Ctrl+C to exit."

# Keep the script running to maintain the processes and allow monitoring
trap "print_status 'Test launcher script completed'" EXIT

# Wait for user to press Ctrl+C or for Ardour to be stopped
while true; do
    # Check if Ardour is still running
    if ! pgrep -f ardour > /dev/null 2>&1; then
        print_status "Ardour process has stopped. Exiting monitor..."
        break
    fi
    
    # Show current status every 10 seconds
    sleep 10
    print_status "Monitoring... Ardour is still running"
done
