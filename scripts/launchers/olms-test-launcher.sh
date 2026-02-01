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

# Function to check if variable is set and not empty
check_variable() {
    local var_name="$1"
    local var_value="$2"
    
    if [ -z "$var_value" ]; then
        print_error "Variable $var_name is not set or empty"
        return 1
    else
        print_status "Variable $var_name is set: $var_value"
        return 0
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

# Function to check if user has necessary privileges without sudo
check_user_privileges() {
    print_status "Checking user privileges for audio operations..."
    
    # Check if user is in required groups
    local required_groups="realtime audio"
    local missing_groups=""
    
    for group in $required_groups; do
        if ! groups $USER | grep -q "$group"; then
            missing_groups="$missing_groups $group"
        fi
    done
    
    if [ -n "$missing_groups" ]; then
        print_status "User not in groups: $missing_groups"
        return 1
    fi
    
    # Check realtime limits
    local rtprio=$(ulimit -r)
    local memlock=$(ulimit -l)
    
    if [ "$rtprio" -lt 90 ] || ([ "$memlock" != "unlimited" ] && [ "$memlock" -lt 1024 ]); then
        print_status "Realtime limits insufficient: rtprio=$rtprio, memlock=${memlock}KB"
        return 1
    fi
    
    print_status "User privileges verified ✓"
    return 0
}

# Function to detect and preserve X11 environment
detect_x11_environment() {
    print_status "Detecting X11 environment for GUI mode..."
    
    # Preserve current DISPLAY if available
    if [ -n "$DISPLAY" ]; then
        export DISPLAY="$DISPLAY"
        print_status "DISPLAY preserved: $DISPLAY"
    fi
    
    # Detect DISPLAY automatically if not present
    if [ -z "$DISPLAY" ]; then
        for display_num in 0 1 2 3; do
            if [ -f "/tmp/.X11-unix/X$display_num" ]; then
                export DISPLAY=":$display_num"
                print_status "DISPLAY detected: $DISPLAY"
                break
            fi
        done
    fi
    
    # Configure XAUTHORITY
    if [ -z "$XAUTHORITY" ]; then
        export XAUTHORITY="$HOME/.Xauthority"
        print_status "XAUTHORITY set: $XAUTHORITY"
    fi
    
    # Configure XDG_RUNTIME_DIR
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        print_status "XDG_RUNTIME_DIR set: $XDG_RUNTIME_DIR"
    fi
    
    # Verify X11 access
    if [ -n "$DISPLAY" ]; then
        if xset q >/dev/null 2>&1; then
            print_status "X11 access verified ✓"
        else
            print_status "Warning: X11 access not verified"
        fi
    fi
}

# Function to setup X11 permissions for root access
setup_x11_permissions() {
    print_status "Setting up X11 permissions for root access..."
    
    # Grant root access to X server
    if command -v xhost >/dev/null 2>&1; then
        if xhost +si:localuser:root 2>/dev/null; then
            print_status "Root X11 access granted ✓"
        else
            print_status "Warning: Could not grant root X11 access"
        fi
    fi
    
    # Copy XAUTHORITY for root if needed
    if [ -n "$SUDO_USER" ] && [ -f "/home/$SUDO_USER/.Xauthority" ]; then
        sudo cp "/home/$SUDO_USER/.Xauthority" /root/.Xauthority 2>/dev/null || true
        print_status "XAUTHORITY copied for root"
    fi
}

# Determine if sudo is needed
if [ "$(id -u)" -ne 0 ]; then
    if check_user_privileges; then
        print_status "User has sufficient privileges, launching without sudo..."
        # For testing mode, preserve X11 environment
        detect_x11_environment
        setup_x11_permissions
        ./scripts/olms-startup.sh --test --preserve-x11
    else
        print_status "Insufficient privileges, requesting sudo..."
        detect_x11_environment
        setup_x11_permissions
        sudo -E ./scripts/olms-startup.sh --test --preserve-x11
    fi
else
    # Already running as root, preserve X11 environment
    detect_x11_environment
    setup_x11_permissions
    ./scripts/olms-startup.sh --test --preserve-x11
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
ARDOUR_COUNT=$(echo "$ARDOUR_COUNT" | tr -d '[:space:]')
if [ "$ARDOUR_COUNT" -gt 0 ] 2>/dev/null; then
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
echo "  - JACK server: $([ "${JACK_COUNT:-0}" -gt 0 ] && echo "Active" || echo "Inactive")"
echo "  - Ardour processes: $([ "${ARDOUR_COUNT:-0}" -gt 0 ] && echo "Running ($ARDOUR_COUNT)" || echo "Not running")"
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

# LOGGING: Explain Ardour startup process and why there might be a delay
print_status "LOGGING: Ardour startup process explanation"
print_status "  - Ardour is launched as a JACK client after JACK server is ready"
print_status "  - There may be a brief delay (5-10 seconds) for Ardour to fully initialize"
print_status "  - This delay is normal and allows Ardour to properly connect to JACK"
print_status "  - Ardour GUI should appear shortly after this message"
echo

# Phase 6: Quick Ardour Status Check (Non-blocking)
print_status "Phase 6: Quick Ardour Status Check"
print_status "Checking if Ardour has started..."

# Function to check if Ardour is running
check_ardour_status() {
    local ardour_pids=$(pgrep -f ardour 2>/dev/null || echo "")
    if [ -n "$ardour_pids" ]; then
        echo "Ardour processes found: $ardour_pids"
        for pid in $ardour_pids; do
            local process_info=$(ps -p "$pid" -o pid,cmd 2>/dev/null | tail -n 1 || echo "")
            if [ -n "$process_info" ]; then
                echo "  PID $pid: $process_info"
            fi
        done
        return 0
    else
        return 1
    fi
}

# Quick check for Ardour (no waiting loop)
if check_ardour_status; then
    print_success "Ardour is running and ready!"
else
    print_status "Ardour may still be starting up (this is normal)"
    print_status "Ardour GUI should appear within 10-15 seconds"
    print_status "If Ardour doesn't appear, check the system manually"
fi

echo
print_status "System Status Summary:"
echo "  - OLMS system: Running"
echo "  - JACK server: $([ "${JACK_COUNT:-0}" -gt 0 ] && echo "Active" || echo "Inactive")"
echo "  - Ardour: $([ "${ARDOUR_COUNT:-0}" -gt 0 ] && echo "Running" || echo "Starting...")"
echo "  - GUI: Available for development and testing"
echo
print_status "System Management Commands:"
echo "  - Check JACK status: jack_control status"
echo "  - List JACK ports: jack_lsp"
echo "  - Monitor logs: journalctl -f"
echo "  - Stop Ardour: pkill -f ardour"
echo "  - Stop JACK: pkill jackd"
echo
print_status "IMPORTANT: Ardour launches immediately after JACK is ready"
print_status "The brief delay allows Ardour to properly initialize and connect to JACK"
print_status "This is normal behavior for audio applications"
echo
print_success "OLMS Test Launcher completed successfully!"
print_status "Script is now exiting. Ardour should be running and visible."
print_status "Use the commands above to monitor and manage the system."
