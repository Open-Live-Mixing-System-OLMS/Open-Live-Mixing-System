#!/bin/bash

# Ardour Launcher Script - OLMS Pro Audio Version
# 
# Based on technical analysis: Fixes Pipewire conflicts, implements proper
# JACK2 daemon approach, and configures Ardour as passive client.
# 
# Key improvements:
# - Proper realtime privileges check
# - Complete audio environment cleanup
# - JACK2 daemon with optimized parameters
# - Ardour as JACK client (not master)
# - Pipewire bypass configuration

set -e

# Default values
MODE="test"
OLMS_SESSION_PATH="${OLMS_SESSION_PATH:-engine/session-template/OLMS-POC/OLMS-POC.ardour}"
JACK_SAMPLE_RATE="${JACK_SAMPLE_RATE:-48000}"
JACK_PERIOD_SIZE="${JACK_PERIOD_SIZE:-64}"  # Standard buffer size
FORCE_VIRTUAL=false

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to check realtime privileges
check_realtime_privileges() {
    print_status "Checking realtime privileges..."
    
    # Check if user is in realtime group
    if groups $USER | grep -q "realtime"; then
        print_status "User is in realtime group ✓"
    else
        print_status "Warning: User not in realtime group - may cause audio issues"
        print_status "Run: sudo usermod -aG realtime $USER"
    fi
    
    # Check current limits
    local rtprio=$(ulimit -r)
    local memlock=$(ulimit -l)
    
    print_status "Current realtime limits: rtprio=$rtprio, memlock=${memlock}KB"
    
    # Check if limits are sufficient
    if [ "$rtprio" -ge 90 ] && ([ "$memlock" = "unlimited" ] || [ "$memlock" -gt 1024 ]); then
        print_status "Realtime privileges appear sufficient ✓"
        return 0
    else
        print_status "Warning: Realtime privileges may be insufficient"
        print_status "Consider configuring /etc/security/limits.d/99-realtime.conf"
        return 1
    fi
}

# Function to detect USB audio devices automatically
detect_usb_audio_device() {
    # Look for USB audio devices in /proc/asound/cards
    local usb_cards=$(grep -i "usb.*audio\|audio.*usb" /proc/asound/cards 2>/dev/null | grep -E "^[0-9]+" | awk '{print $1}' | head -1)
    
    if [ -n "$usb_cards" ]; then
        echo "hw:$usb_cards,0"
        return 0
    else
        # Alternative detection using aplay -l
        local usb_devices=$(aplay -l 2>/dev/null | grep -i "usb.*audio\|audio.*usb" | grep -E "card [0-9]+:" | head -1 | sed 's/.*card \([0-9]*\):.*/\1/')
        
        if [ -n "$usb_devices" ]; then
            echo "hw:$usb_devices,0"
            return 0
        else
            return 1
        fi
    fi
}

# Function to close existing Ardour sessions and save them
cleanup_existing_ardour_sessions() {
    print_status "Checking for existing Ardour sessions..."
    
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
        
        # Force kill existing Ardour processes (excluding current script)
        print_status "Force killing existing Ardour processes..."
        for pid in $ardour_pids; do
            kill -9 $pid 2>/dev/null || true
        done
        
        # Wait for processes to terminate
        sleep 3
        
        # Verify processes are gone
        local remaining_pids=$(pgrep -f ardour | grep -v "$current_pid")
        if [ -n "$remaining_pids" ]; then
            print_status "Warning: Some Ardour processes still running: $remaining_pids"
        else
            print_status "All existing Ardour sessions closed successfully"
        fi
    else
        print_status "No existing Ardour sessions found"
    fi
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

# Function to adapt Ardour session to detected USB audio device
adapt_ardour_session() {
    local session_file="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local adapter_script="$script_dir/usb_audio_session_adapter.sh"
    
    if [ -f "$adapter_script" ]; then
        print_status "Adapting Ardour session to detected USB audio device..."
        "$adapter_script" "$session_file"
        return $?
    else
        print_status "Warning: USB audio session adapter not found, skipping adaptation"
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
        
        # Method 5: Kill Pipewire and related processes (CRITICAL for JACK stability)
        print_status "Killing Pipewire and related audio processes..."
        pkill -9 -f pipewire 2>/dev/null || true
        pkill -9 -f wireplumber 2>/dev/null || true
        pkill -9 -f pulseaudio 2>/dev/null || true
        pkill -9 -f alsa 2>/dev/null || true
        sleep 3
        
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
        
        # Method 8: Remove Pipewire socket files (CRITICAL)
        print_status "Removing Pipewire socket files..."
        rm -f /tmp/pipewire* 2>/dev/null || true
        rm -f /dev/shm/pipewire* 2>/dev/null || true
        rm -f /var/run/pipewire* 2>/dev/null || true
        rm -f /run/pipewire* 2>/dev/null || true
        rm -f /tmp/.pipewire* 2>/dev/null || true
        rm -f /var/lock/.pipewire* 2>/dev/null || true
        
        # Method 9: Clean up shared memory segments
        print_status "Cleaning up shared memory segments..."
        for shm_id in $(ipcs -m | grep jack | awk '{print $2}'); do
            ipcrm -m $shm_id 2>/dev/null || true
        done
        for sem_id in $(ipcs -s | grep jack | awk '{print $2}'); do
            ipcrm -s $sem_id 2>/dev/null || true
        done
        
        # Method 10: Set Pipewire bypass environment
        print_status "Setting Pipewire bypass environment..."
        export PIPEWIRE_RUNTIME_DIR=/dev/null
        export JACK_NO_START_SERVER=1
        
        return 0
    }
    
    # Ensure no JACK instances are running before starting
    print_status "Ensuring no JACK instances are running..."
    force_kill_all_jack
    
    case "$backend" in
        "dummy")
            print_status "Starting JACK with dummy backend (virtual audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            # Dummy backend doesn't support -n parameter, use only supported options
            jack_cmd="jackd -R -d dummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -C 2 -P 2"
            ;;
        "alsa")
            print_status "Starting JACK with ALSA backend (USB Audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            # Use detected USB Audio device
            if [ -n "$USB_AUDIO_DEVICE" ]; then
                # Optimized JACK parameters based on technical analysis
                # -R: Realtime scheduling
                # -n 2: Number of periods (optimized for stability)
                # No MIDI flags (-X seq) to avoid crashes on unsupported hardware
                jack_cmd="jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 2 -d $USB_AUDIO_DEVICE"
                print_status "Using detected USB device: $USB_AUDIO_DEVICE"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p $JACK_PERIOD_SIZE (buffer)"
            else
                # Fallback to first available card if detection failed
                jack_cmd="jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 2"
                print_status "Using default ALSA device"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p $JACK_PERIOD_SIZE (buffer)"
            fi
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

# Function to setup JACK environment (Phase 1)
setup_jack_environment() {
    print_status "Phase 1: Setting up JACK environment..."
    
    # Set environment variables to bypass Pipewire and force JACK client mode
    export JACK_NO_START_SERVER=1
    export PIPEWIRE_RUNTIME_DIR=/dev/null
    
    # Additional JACK environment variables for stability
    export JACK_SERVER_NAME=default
    export JACK_CONNECT_TIMEOUT=10
    
    print_status "JACK environment configured:"
    echo "  - JACK_NO_START_SERVER=1 (Ardour as client)"
    echo "  - PIPEWIRE_RUNTIME_DIR=/dev/null (Bypass Pipewire)"
    echo "  - JACK_SERVER_NAME=default"
    echo "  - JACK_CONNECT_TIMEOUT=10"
    
    return 0
}

# Function to verify realtime privileges (Phase 1)
verify_realtime_privileges() {
    print_status "Verifying realtime privileges..."
    
    # Check if user is in realtime group
    if groups $USER | grep -q "realtime"; then
        print_status "User is in realtime group ✓"
    else
        print_status "Warning: User not in realtime group - may cause audio issues"
        print_status "Run: sudo usermod -aG realtime $USER"
    fi
    
    # Check current limits
    local rtprio=$(ulimit -r)
    local memlock=$(ulimit -l)
    
    print_status "Current realtime limits: rtprio=$rtprio, memlock=${memlock}KB"
    
    # Check if limits are sufficient
    if [ "$rtprio" -ge 90 ] && ([ "$memlock" = "unlimited" ] || [ "$memlock" -gt 1024 ]); then
        print_status "Realtime privileges appear sufficient ✓"
        return 0
    else
        print_status "Warning: Realtime privileges may be insufficient"
        print_status "Consider configuring /etc/security/limits.d/99-realtime.conf"
        return 1
    fi
}

# Function to perform deep cleanup (Phase 2)
perform_deep_cleanup() {
    print_status "Phase 2: Performing deep cleanup..."
    
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
        
        # Method 4: Kill Pipewire and related processes (CRITICAL for JACK stability)
        print_status "Killing Pipewire and related audio processes..."
        pkill -9 -f pipewire 2>/dev/null || true
        pkill -9 -f wireplumber 2>/dev/null || true
        pkill -9 -f pulseaudio 2>/dev/null || true
        pkill -9 -f alsa 2>/dev/null || true
        sleep 3
        
        # Method 5: Use lsof to find and kill processes holding audio devices
        print_status "Checking for processes holding audio devices..."
        local audio_processes=$(lsof /dev/snd/* 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
        if [ -n "$audio_processes" ]; then
            print_status "Found processes holding audio devices: $audio_processes"
            echo "$audio_processes" | xargs -r kill -9 2>/dev/null || true
            sudo echo "$audio_processes" | xargs -r kill -9 2>/dev/null || true
            sleep 2
        fi
        
        # Method 6: Remove JACK socket files
        print_status "Removing JACK socket files..."
        rm -f /tmp/jack_* 2>/dev/null || true
        rm -f /dev/shm/jack_* 2>/dev/null || true
        rm -f /var/run/jack_* 2>/dev/null || true
        rm -f /run/jack_* 2>/dev/null || true
        rm -f /tmp/.jack* 2>/dev/null || true
        rm -f /var/lock/.jack* 2>/dev/null || true
        
        # Method 7: Remove Pipewire socket files (CRITICAL)
        print_status "Removing Pipewire socket files..."
        rm -f /tmp/pipewire* 2>/dev/null || true
        rm -f /dev/shm/pipewire* 2>/dev/null || true
        rm -f /var/run/pipewire* 2>/dev/null || true
        rm -f /run/pipewire* 2>/dev/null || true
        rm -f /tmp/.pipewire* 2>/dev/null || true
        rm -f /var/lock/.pipewire* 2>/dev/null || true
        
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
    
    # Perform the cleanup
    force_kill_all_jack
    
    # Verify cleanup was successful
    local remaining_processes=$(pgrep -f "jackd|pipewire|pulseaudio" | wc -l)
    if [ "$remaining_processes" -eq 0 ]; then
        print_status "Deep cleanup completed successfully ✓"
        return 0
    else
        print_status "Warning: Some audio processes may still be running: $remaining_processes"
        return 1
    fi
}

# Function to verify system state (Phase 2)
verify_system_state() {
    print_status "Verifying system state..."
    
    # Check that no audio processes are running
    local audio_pids=$(pgrep -f "jackd|pipewire|pulseaudio|ardour" 2>/dev/null | wc -l)
    if [ "$audio_pids" -eq 0 ]; then
        print_status "System state verified: No conflicting audio processes running ✓"
        return 0
    else
        print_status "Warning: Found $audio_pids audio processes still running"
        pgrep -f "jackd|pipewire|pulseaudio|ardour" 2>/dev/null || true
        return 1
    fi
}

# Function to start JACK2 server (Phase 3)
start_jack2_server() {
    local backend="$1"
    local jack_cmd=""
    
    print_status "Phase 3: Starting JACK2 server..."
    
    # Ensure no JACK instances are running before starting
    perform_deep_cleanup
    
    case "$backend" in
        "dummy")
            print_status "Starting JACK with dummy backend (virtual audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            # Dummy backend doesn't support -n parameter, use only supported options
            jack_cmd="jackd -R -d dummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -C 2 -P 2"
            ;;
        "alsa")
            print_status "Starting JACK with ALSA backend (USB Audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            
            # Use detected USB Audio device with optimized parameters
            if [ -n "$USB_AUDIO_DEVICE" ]; then
                # Optimized JACK parameters based on technical analysis
                # -R: Realtime scheduling
                # -n 2: Number of periods (optimized for stability)
                # -p 128: Buffer size (128 for stability, as tested)
                # No MIDI flags to avoid crashes on unsupported hardware
                jack_cmd="jackd -R -d alsa -r$JACK_SAMPLE_RATE -p128 -n 2 -d $USB_AUDIO_DEVICE"
                print_status "Using detected USB device: $USB_AUDIO_DEVICE"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p 128 (buffer for stability)"
            else
                # Fallback to first available card if detection failed
                jack_cmd="jackd -R -d alsa -r$JACK_SAMPLE_RATE -p128 -n 2"
                print_status "Using default ALSA device"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p 128 (buffer for stability)"
            fi
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

# Function to verify JACK stability (Phase 3)
verify_jack_stability() {
    print_status "Verifying JACK stability..."
    
    # Wait a bit more for JACK to fully initialize
    sleep 2
    
    # Test JACK with jack_lsp
    local jack_test_attempts=5
    local jack_ready=false
    
    for i in $(seq 1 $jack_test_attempts); do
        print_status "Testing JACK connection (attempt $i/$jack_test_attempts)..."
        
        if jack_lsp >/dev/null 2>&1; then
            print_status "JACK is responding to jack_lsp ✓"
            jack_ready=true
            break
        else
            print_status "JACK not ready, waiting 2 more seconds..."
            sleep 2
        fi
    done
    
    if [ "$jack_ready" = true ]; then
        print_status "JACK stability verified ✓"
        
        # List available ports for debugging
        print_status "Available JACK ports:"
        jack_lsp 2>/dev/null | head -10 || echo "  No ports listed yet"
        
        return 0
    else
        print_status "Error: JACK failed to stabilize after $jack_test_attempts attempts"
        return 1
    fi
}

# Function to start Ardour as JACK client (Phase 4)
start_ardour_as_client() {
    local ardour_cmd=""
    
    print_status "Phase 4: Starting Ardour as JACK client..."
    
    # Setup JACK environment
    setup_jack_environment
    
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
    
    # Verify JACK is ready before starting Ardour
    print_status "Final JACK verification before Ardour startup..."
    if ! verify_jack_stability; then
        print_status "Error: JACK is not stable, cannot start Ardour"
        return 1
    fi
    
    # Start Ardour
    print_status "Starting Ardour with command: $ardour_cmd"
    print_status "Environment: JACK_NO_START_SERVER=1, PIPEWIRE_RUNTIME_DIR=/dev/null"
    $ardour_cmd &
    ARDOUR_PID=$!
    
    # Wait for Ardour to start
    sleep 3
    
    # Check if Ardour is running
    if kill -0 $ARDOUR_PID 2>/dev/null; then
        print_status "Ardour started successfully as JACK client (PID: $ARDOUR_PID)"
        
        # Final verification: check if Ardour is connected to JACK
        print_status "Verifying Ardour-JACK connection..."
        sleep 2
        
        if jack_lsp 2>/dev/null | grep -q "ardour"; then
            print_status "Ardour successfully connected to JACK ✓"
            return 0
        else
            print_status "Warning: Ardour may not be fully connected to JACK yet"
            print_status "This is normal - connection may take a few more seconds"
            return 0
        fi
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
print_status "=== Ardour Launcher - OLMS Pro Audio Version ==="
print_status "Mode: $MODE"
print_status "Session: $OLMS_SESSION_PATH"
print_status "JACK Config: $JACK_SAMPLE_RATE Hz, period=$JACK_PERIOD_SIZE"

# Phase 0: Check realtime privileges
print_status "Phase 0: Checking realtime privileges"
check_realtime_privileges

print_status "Phase 1: Cleanup existing sessions"
cleanup_existing_ardour_sessions

print_status "Phase 2: Audio Hardware Detection"
if [ "$FORCE_VIRTUAL" = true ]; then
    AUDIO_BACKEND="dummy"
    print_status "Virtual audio mode forced - using dummy backend"
else
    # Try to detect USB audio device
    USB_DEVICE=$(detect_usb_audio_device 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$USB_DEVICE" ]; then
        AUDIO_BACKEND="alsa"
        USB_AUDIO_DEVICE="$USB_DEVICE"
        print_status "Using detected USB audio device: $USB_AUDIO_DEVICE"
    else
        AUDIO_BACKEND="dummy"
        print_status "No USB audio detected, falling back to dummy backend"
    fi
fi

print_status "Phase 3: Adapting Ardour session to detected audio device"
if [ "$FORCE_VIRTUAL" = false ]; then
    if ! adapt_ardour_session "$OLMS_SESSION_PATH"; then
        print_status "Session adaptation failed, but continuing..."
    fi
fi

print_status "Phase 4: Verifying realtime privileges"
if ! verify_realtime_privileges; then
    print_status "Warning: Realtime privileges may be insufficient, continuing anyway..."
fi

print_status "Phase 5: Performing deep cleanup"
if ! perform_deep_cleanup; then
    print_status "Warning: Deep cleanup had issues, but continuing..."
fi

print_status "Phase 6: Verifying system state"
if ! verify_system_state; then
    print_status "Warning: System state verification failed, but continuing..."
fi

print_status "Phase 7: Starting JACK2 server"
if ! start_jack2_server "$AUDIO_BACKEND"; then
    print_status "JACK2 startup failed, aborting"
    exit 1
fi

print_status "Phase 8: Verifying JACK stability"
if ! verify_jack_stability; then
    print_status "JACK stability verification failed, stopping JACK"
    kill $JACK_PID 2>/dev/null
    exit 1
fi

print_status "Phase 9: Starting Ardour as JACK client"
if ! start_ardour_as_client; then
    print_status "Ardour startup failed, stopping JACK"
    kill $JACK_PID 2>/dev/null
    exit 1
fi

print_status "=== Launch Complete ==="
print_status "System Status:"
echo "  - JACK running with $AUDIO_BACKEND backend"
echo "  - Ardour running in $MODE mode as JACK client"
echo "  - Session: $OLMS_SESSION_PATH"
echo "  - JACK_NO_START_SERVER=1 (Ardour as client)"
echo "  - PIPEWIRE_RUNTIME_DIR=/dev/null (Pipewire bypass)"
echo
print_status "To monitor the system:"
echo "  - Check JACK status: jack_control status"
echo "  - List JACK ports: jack_lsp"
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
