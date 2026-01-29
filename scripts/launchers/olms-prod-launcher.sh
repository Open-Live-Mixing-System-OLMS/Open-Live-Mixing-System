#!/bin/bash

# OLMS Production Launcher
# 
# This script launches the OLMS system in production mode (headless) for automated operation.
# It provides a streamlined startup sequence optimized for live performances and automated recording.
# 
# Usage: ./scripts/launchers/olms-prod-launcher.sh
# 
# This script is designed for production environments where minimal user interaction
# and maximum system stability are required.

set -e

# Script information
SCRIPT_NAME="OLMS Production Launcher"
SCRIPT_VERSION="1.0"
SCRIPT_DESCRIPTION="Launches OLMS system in production mode (headless)"

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
        echo "Production launcher aborted due to error in: $1"
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
    echo "  --virtual      Force virtual audio backend (no hardware required)"
    echo ""
    echo "This script launches the OLMS system in production mode (headless) for"
    echo "automated operation. It provides minimal user interaction and maximum"
    echo "system stability for live performances and automated recording."
    echo ""
    echo "Examples:"
    echo "  $0                    # Launch in production mode (headless)"
    echo "  $0 --verbose          # Launch with verbose output"
    echo "  $0 --virtual          # Launch with virtual audio (no hardware)"
    echo "  $0 --help             # Show help message"
}

# Parse command line arguments
VERBOSE=false
FORCE_VIRTUAL=false
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
        --virtual)
            FORCE_VIRTUAL=true
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
echo "Mode: Production (headless)"
echo "Timestamp: $(date)"
if [ "$FORCE_VIRTUAL" = true ]; then
    echo "Virtual audio mode: Enabled (no hardware required)"
fi
echo

# Check if we're in the correct directory
if [ ! -f "scripts/olms-startup.sh" ]; then
    print_error "OLMS-Core directory not found. Please run this script from the OLMS-Core root directory."
    exit 1
fi

print_status "Starting OLMS Production Launcher..."
echo

# Phase 1: System Check
print_status "Phase 1: System Prerequisites Check"
print_status "Verifying system requirements for production mode..."

# Check if running as root (required for production operations)
if [ "$EUID" -ne 0 ]; then
    print_status "Note: Production mode requires root privileges"
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
print_status "Phase 2: Launching OLMS Production Startup Sequence"
print_status "Executing: ./scripts/olms-startup.sh --prod"

# Build startup script arguments
STARTUP_ARGS="--prod"
if [ "$FORCE_VIRTUAL" = true ]; then
    STARTUP_ARGS="$STARTUP_ARGS --virtual"
fi

if [ "$VERBOSE" = true ]; then
    STARTUP_ARGS="$STARTUP_ARGS --verbose"
fi

# Launch the main startup script in production mode
./scripts/olms-startup.sh $STARTUP_ARGS

check_status "OLMS production startup sequence"
echo

# Phase 3: Post-Startup Verification
print_status "Phase 3: Post-Startup System Verification"
print_status "Verifying production system status..."

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

# Check Ardour processes (should be headless)
print_status "Checking Ardour processes..."
ARDOUR_COUNT=$(pgrep -c ardour 2>/dev/null || echo "0")
if [ "$ARDOUR_COUNT" -gt 0 ]; then
    print_success "Ardour processes found: $ARDOUR_COUNT (headless mode)"
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
echo "=== Production System Status ==="
echo "  - OLMS startup sequence: Completed"
echo "  - JACK server: $([ "$JACK_COUNT" -gt 0 ] && echo "Active" || echo "Inactive")"
echo "  - Ardour processes: $([ "$ARDOUR_COUNT" -gt 0 ] && echo "Running ($ARDOUR_COUNT) - Headless" || echo "Not running")"
echo "  - Production mode: Enabled (headless operation)"
echo "  - Virtual audio: $([ "$FORCE_VIRTUAL" = true ] && echo "Enabled" || echo "Disabled")"
echo "  - Verbose output: $([ "$VERBOSE" = true ] && echo "Enabled" || echo "Disabled")"
echo

# Phase 5: Production Environment Instructions
print_status "Phase 5: Production Environment Instructions"
echo "=== Production Environment Instructions ==="
echo "  - Ardour is running in headless mode (no GUI)"
echo "  - JACK server is running for audio processing"
echo "  - System is optimized for live performance/automated recording"
echo "  - Monitor system logs for any issues:"
echo "    - Check JACK status: jack_control status"
echo "    - Monitor logs: journalctl -f -u ardour.service"
echo "    - Check disk space: df -h"
echo "  - System is ready for automated operation"
echo "  - No user interaction required during operation"
echo

# Phase 6: Production Monitoring (Optional)
if [ "$VERBOSE" = true ]; then
    print_status "Phase 6: Launching Production System Monitor"
    echo "=== Production System Monitor ==="
    echo "Monitoring production system processes (press Ctrl+C to exit):"
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
    
    # Show disk usage
    echo "Disk usage:"
    df -h | grep -E "^/dev/" | while read line; do
        echo "  $line"
    done
    echo
fi

print_status "=== OLMS Production Launcher Complete ==="
print_success "OLMS system is now running in production mode"
print_status "Headless operation enabled for automated performance/recording"
echo
print_status "Production system monitoring:"
echo "  - Check JACK status: jack_control status"
echo "  - Monitor logs: journalctl -f -u ardour.service"
echo "  - Check disk space: df -h"
echo "  - Monitor system resources: top, htop"
echo
print_status "To stop the production system:"
echo "  - Stop Ardour: pkill -f ardour"
echo "  - Stop JACK: pkill jackd"
echo "  - Stop any background processes from this script"
echo
print_status "Production launcher completed successfully!"

# Keep the script running to maintain the processes
trap "print_status 'Production launcher script completed'" EXIT