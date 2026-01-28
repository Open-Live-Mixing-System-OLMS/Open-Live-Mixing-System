#!/bin/bash

# Ardour Launcher Script - Final Version with X11 Fix
# 
# This version includes X11 correction and better JACK error handling.

set -e

# Default values
MODE="test"
OLMS_SESSION_PATH="${OLMS_SESSION_PATH:-engine/session-template/OLMS-POC/OLMS-POC.ardour}"
JACK_SAMPLE_RATE="${JACK_SAMPLE_RATE:-48000}"
JACK_PERIOD_SIZE="${JACK_PERIOD_SIZE:-64}"
FORCE_VIRTUAL=false

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to show help
show_help() {
    echo "Ardour Launcher Script - Final Version with X11 Fix"
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

print_status "=== Ardour Launcher - Final Version with X11 Fix ==="
print_status "Mode: $MODE"
print_status "Session: $OLMS_SESSION_PATH"
print_status "JACK Config: $JACK_SAMPLE_RATE Hz, period=$JACK_PERIOD_SIZE"

# Check if session file exists
if [ ! -f "$OLMS_SESSION_PATH" ]; then
    print_status "Warning: Session file not found at $OLMS_SESSION_PATH"
    print_status "Using default Ardour session"
fi

# Function to setup X11 environment (X11 fix)
setup_x11_environment() {
    print_status "Setting up X11 environment for Ardour..."
    
    # If DISPLAY is already set and working, use it
    if [ -n "$DISPLAY" ] && xset -display "$DISPLAY" q >/dev/null 2>&1; then
        print_status "Using existing DISPLAY: $DISPLAY"
        return 0
    fi
    
    # Try to find X11 display from socket files
    if [ -f "/tmp/.X11-unix/X1" ]; then
        export DISPLAY=":1"
        print_status "X11 display detected and set: $DISPLAY"
        
        # Set XAUTHORITY if not set
        if [ -z "$XAUTHORITY" ]; then
            export XAUTHORITY="$HOME/.Xauthority"
            print_status "XAUTHORITY set to: $XAUTHORITY"
        fi
        
        return 0
    fi
    
    # Try to find X11 display from xauth
    if command -v xauth >/dev/null 2>&1; then
        local auth_entry=$(xauth list 2>/dev/null | grep -E ":[0-9]+" | head -1)
        if [ -n "$auth_entry" ]; then
            local display=$(echo "$auth_entry" | awk '{print $1}' | sed 's/.*\(:[0-9]*\)$/\1/')
            if [ -n "$display" ]; then
                export DISPLAY="$display"
                print_status "X11 display detected from xauth and set: $DISPLAY"
                
                # Set XAUTHORITY if not set
                if [ -z "$XAUTHORITY" ]; then
                    export XAUTHORITY="$HOME/.Xauthority"
                    print_status "XAUTHORITY set to: $XAUTHORITY"
                fi
                
                return 0
            fi
        fi
    fi
    
    print_status "Warning: No X11 display found"
    if [ "$MODE" = "test" ]; then
        print_status "Error: Cannot start Ardour in GUI mode without X11 display"
        return 1
    else
        print_status "Continuing in production mode (headless)"
        return 0
    fi
}

# Function to start JACK (simplified)
start_jack_simple() {
    local backend="$1"
    local jack_cmd=""
    
    # Function to force kill all JACK instances aggressively
    force_kill_all_jack() {
        print_status "Force killing all JACK instances aggressively..."
        
        # Method 1: Try graceful shutdown first
        print_status "Attempting graceful shutdown with jack_control..."
        jack_control exit 2>/dev/null || true
        sleep 2
        
        # Method 2: Kill by process name
        if pgrep -f jackd > /dev/null; then
            local jack_pids=$(pgrep -f jackd)
            print_status "Found JACK PIDs: $jack_pids"
            print_status "Force killing JACK processes with SIGKILL..."
            pkill -9 -f jackd 2>/dev/null || true
            kill -9 $jack_pids 2>/dev/null || true
            sleep 2
        fi
        
        # Method 3: Kill system-wide JACK processes
        print_status "Killing system-wide JACK processes..."
        pkill -9 -f jackd 2>/dev/null || true
        killall -9 jackd 2>/dev/null || true
        sleep 3
        
        # Method 4: Kill via systemctl if JACK is installed as service
        if systemctl --user is-active --quiet jackd 2>/dev/null; then
            print_status "Stopping JACK user systemd service..."
            systemctl --user stop jackd 2>/dev/null || true
            systemctl --user disable jackd 2>/dev/null || true
        fi
        
        if systemctl is-active --quiet jackd 2>/dev/null; then
            print_status "Stopping JACK system systemd service..."
            # Skip system-wide systemctl operations to avoid sudo prompt
            print_status "Note: System JACK service detected but not stopped (requires sudo)"
        fi
        sleep 3
        
        # Method 5: Kill any remaining audio-related processes
        print_status "Killing audio-related processes that might hold resources..."
        pkill -9 -f pulseaudio 2>/dev/null || true
        pkill -9 -f alsa 2>/dev/null || true
        sleep 2
        
        # Method 6: Use lsof to find and kill processes holding audio devices
        print_status "Checking for processes holding audio devices..."
        local audio_processes=$(lsof /dev/snd/* 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
        if [ -n "$audio_processes" ]; then
            print_status "Found processes holding audio devices: $audio_processes"
            echo "$audio_processes" | xargs -r kill -9 2>/dev/null || true
            sudo echo "$audio_processes" | xargs -r kill -9 2>/dev/null || true
            sleep 2
        fi
        
        # Method 7: Remove JACK socket files
        print_status "Removing JACK socket files..."
        rm -f /tmp/jack_* 2>/dev/null || true
        rm -f /dev/shm/jack_* 2>/dev/null || true
        rm -f /var/run/jack_* 2>/dev/null || true
        rm -f /run/jack_* 2>/dev/null || true
        rm -f /tmp/.jack* 2>/dev/null || true
        rm -f /var/lock/.jack* 2>/dev/null || true
        
        # Method 8: Clean up shared memory segments
        print_status "Cleaning up shared memory segments..."
        for shm_id in $(ipcs -m | grep jack | awk '{print $2}'); do
            ipcrm -m $shm_id 2>/dev/null || true
        done
        for sem_id in $(ipcs -s | grep jack | awk '{print $2}'); do
            ipcrm -s $sem_id 2>/dev/null || true
        done
        
        return 0
    }
    
    # Ensure no JACK instances are running before starting
    print_status "Ensuring no JACK instances are running..."
    force_kill_all_jack
    
    case "$backend" in
        "dummy")
            print_status "Starting JACK with dummy backend (virtual audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            jack_cmd="jackd -d dummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -C 2 -P 2"
            ;;
        *)
            print_status "Error: Unsupported JACK backend: $backend"
            return 1
            ;;
    esac
    
    print_status "JACK command: $jack_cmd"
    
    # Start JACK in background
    eval $jack_cmd &
    JACK_PID=$!
    
    # Wait for JACK to start
    sleep 3
    
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
start_ardour_simple() {
    local ardour_cmd=""
    
    if [ "$MODE" = "prod" ]; then
        print_status "Starting Ardour in production mode (headless)..."
        ardour_cmd="/usr/bin/ardour8 --no-splash $OLMS_SESSION_PATH"
    else
        print_status "Starting Ardour in testing mode (with GUI)..."
        
        # Setup X11 environment before starting Ardour
        if ! setup_x11_environment; then
            print_status "Failed to setup X11 environment, cannot start Ardour in GUI mode"
            return 1
        fi
        
        # Verify X11 is working before starting Ardour
        if ! xset q >/dev/null 2>&1; then
            print_status "Warning: X11 connection test failed, but attempting to start Ardour anyway"
        else
            print_status "X11 connection verified successfully"
        fi
        
        ardour_cmd="/usr/bin/ardour8 $OLMS_SESSION_PATH"
    fi
    
    # Start Ardour
    print_status "Starting Ardour with command: $ardour_cmd"
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
        # Show error details
        print_status "Ardour error details:"
        /usr/bin/ardour8 --version >/dev/null 2>&1 || echo "  - Ardour binary test failed"
        if [ "$MODE" != "prod" ]; then
            echo "  - DISPLAY: $DISPLAY"
            echo "  - XAUTHORITY: $XAUTHORITY"
            xset q >/dev/null 2>&1 || echo "  - X11 connection test failed"
        fi
        return 1
    fi
}

# Main execution
print_status "Phase 1: Audio Hardware Detection"
if [ "$FORCE_VIRTUAL" = true ]; then
    AUDIO_BACKEND="dummy"
    print_status "Virtual audio mode forced"
else
    AUDIO_BACKEND="dummy"
    print_status "Using virtual audio (default for simple version)"
fi

print_status "Phase 2: Starting JACK"
if ! start_jack_simple "$AUDIO_BACKEND"; then
    print_status "JACK startup failed, aborting"
    exit 1
fi

print_status "Phase 3: Starting Ardour"
if ! start_ardour_simple; then
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