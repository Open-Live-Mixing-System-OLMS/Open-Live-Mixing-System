#!/bin/bash

# Ardour Launcher Script
# 
# This script launches JACK and Ardour with configurable options for both
# testing (with GUI) and production (headless) environments.
#
# Usage: ./ardour_launcher.sh [OPTIONS]
#
# OPTIONS:
#   --test, -t     Launch in testing mode with GUI (default)
#   --prod, -p     Launch in production mode (headless)
#   --virtual, -v  Force virtual audio backend (no hardware required)
#   --help, -h     Show this help message
#
# Environment Variables:
#   OLMS_SESSION_PATH    Path to Ardour session file (default: engine/session-template/OLMS-POC/OLMS-POC.ardour)
#   JACK_SAMPLE_RATE     Sample rate for JACK (default: 48000)
#   JACK_PERIOD_SIZE     Period size for JACK (default: 64)
#   JACK_PERIODS         Number of periods for JACK (default: 3)

set -e

# Default values
MODE="test"
OLMS_SESSION_PATH="${OLMS_SESSION_PATH:-engine/session-template/OLMS-POC/OLMS-POC.ardour}"
JACK_SAMPLE_RATE="${JACK_SAMPLE_RATE:-48000}"
JACK_PERIOD_SIZE="${JACK_PERIOD_SIZE:-64}"
JACK_PERIODS="${JACK_PERIODS:-3}"
FORCE_VIRTUAL=false

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo "    ✓ Success"
    else
        echo "    ✗ Failed"
        return 1
    fi
}

# Function to show help
show_help() {
    echo "Ardour Launcher Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --test, -t     Launch in testing mode with GUI (default)"
    echo "  --prod, -p     Launch in production mode (headless)"
    echo "  --virtual, -v  Force virtual audio backend (no hardware required)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  OLMS_SESSION_PATH    Path to Ardour session file"
    echo "  JACK_SAMPLE_RATE     Sample rate for JACK (default: 48000)"
    echo "  JACK_PERIOD_SIZE     Period size for JACK (default: 64)"
    echo "  JACK_PERIODS         Number of periods for JACK (default: 3)"
    echo ""
    echo "Examples:"
    echo "  $0                   # Launch in testing mode with GUI"
    echo "  $0 --prod            # Launch in production mode (headless)"
    echo "  $0 --virtual         # Launch with virtual audio (no hardware)"
    echo "  $0 --test --virtual  # Launch testing mode with virtual audio"
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

print_status "=== Ardour Launcher ==="
print_status "Mode: $MODE"
print_status "Session: $OLMS_SESSION_PATH"
print_status "JACK Config: $JACK_SAMPLE_RATE Hz, period=$JACK_PERIOD_SIZE, periods=$JACK_PERIODS"

# Check if session file exists
if [ ! -f "$OLMS_SESSION_PATH" ]; then
    print_status "Warning: Session file not found at $OLMS_SESSION_PATH"
    print_status "Using default Ardour session"
fi

# Function to detect audio hardware
detect_audio_hardware() {
    # Check for ALSA devices
    if aplay -l 2>/dev/null | grep -q "card.*device"; then
        echo "alsa"
        return 0
    fi
    
    # Check for PulseAudio
    if pactl info >/dev/null 2>&1; then
        echo "pulse"
        return 0
    fi
    
    # No hardware detected
    echo "none"
    return 1
}

# Function to start JACK
start_jack() {
    local backend="$1"
    local jack_cmd=""
    
    case "$backend" in
        "alsa")
            print_status "Starting JACK with ALSA backend..."
            jack_cmd="jackd -dalsa -dhw:0 -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n$JACK_PERIODS"
            ;;
        "pulse")
            print_status "Starting JACK with PulseAudio backend..."
            jack_cmd="jackd -dpulse -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n$JACK_PERIODS"
            ;;
        "dummy")
            print_status "Starting JACK with dummy backend (virtual audio)..."
            jack_cmd="jackd -ddummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n$JACK_PERIODS"
            ;;
        *)
            print_status "Error: Unknown JACK backend: $backend"
            return 1
            ;;
    esac
    
    # Start JACK in background
    eval $jack_cmd &
    JACK_PID=$!
    
    # Wait for JACK to start
    sleep 2
    
    # Check if JACK is running
    if kill -0 $JACK_PID 2>/dev/null; then
        print_status "JACK started successfully (PID: $JACK_PID)"
        return 0
    else
        print_status "Failed to start JACK"
        return 1
    fi
}

# Function to start Ardour
start_ardour() {
    local ardour_cmd=""
    
    if [ "$MODE" = "prod" ]; then
        print_status "Starting Ardour in production mode (headless)..."
        ardour_cmd="ardour --no-gui --session=$OLMS_SESSION_PATH"
    else
        print_status "Starting Ardour in testing mode (with GUI)..."
        ardour_cmd="ardour --session=$OLMS_SESSION_PATH"
    fi
    
    # Start Ardour
    $ardour_cmd &
    ARDOUR_PID=$!
    
    # Wait for Ardour to start
    sleep 3
    
    # Check if Ardour is running
    if kill -0 $ARDOUR_PID 2>/dev/null; then
        print_status "Ardour started successfully (PID: $ARDOUR_PID)"
        return 0
    else
        print_status "Failed to start Ardour"
        return 1
    fi
}

# Main execution
print_status "Phase 1: Audio Hardware Detection"

if [ "$FORCE_VIRTUAL" = true ]; then
    AUDIO_BACKEND="dummy"
    print_status "Virtual audio mode forced"
else
    AUDIO_BACKEND=$(detect_audio_hardware)
    if [ "$AUDIO_BACKEND" = "none" ]; then
        print_status "No audio hardware detected, falling back to virtual audio"
        AUDIO_BACKEND="dummy"
    else
        print_status "Audio hardware detected: $AUDIO_BACKEND"
    fi
fi

print_status "Phase 2: Starting JACK"
if ! start_jack "$AUDIO_BACKEND"; then
    print_status "JACK startup failed, aborting"
    exit 1
fi

print_status "Phase 3: Starting Ardour"
if ! start_ardour; then
    print_status "Ardour startup failed, stopping JACK"
    kill $JACK_PID 2>/dev/null
    exit 1
fi

print_status "=== Launch Complete ==="
print_status "System Status:"
echo "  - JACK running with $AUDIO_BACKEND backend"
echo "  - Ardour running in $MODE mode"
echo "  - Session: $OLMS_SESSION_PATH"
echo
print_status "To monitor the system:"
echo "  - Check JACK status: jack_control status"
echo "  - Monitor logs: journalctl -f"
echo
print_status "To stop the system:"
echo "  - Stop Ardour: kill $ARDOUR_PID"
echo "  - Stop JACK: kill $JACK_PID"
echo
print_status "Ardour launcher completed successfully!"

# Keep the script running to maintain the processes
trap "kill $ARDOUR_PID $JACK_PID 2>/dev/null" EXIT
wait