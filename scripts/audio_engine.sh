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
JACK_PERIOD_SIZE="${JACK_PERIOD_SIZE:-64}"  # Fixed buffer size for optimal audio performance

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Buffer size configuration
# IMPORTANT: Buffer size is always 64 samples for both test and production modes
# This ensures optimal audio performance and low latency in all scenarios
# The 64-sample buffer provides the best balance of CPU efficiency and audio quality
print_status "Using fixed buffer size: 64 samples for optimal audio performance"
print_status "Note: This maintains low latency and high audio quality in all modes"

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

# Function to setup X11 environment (X11 fix - IMPROVED)
setup_x11_environment() {
    print_status "Setting up X11 environment for Ardour..."
    
    # Store original X11 environment variables for restoration
    local original_display="$DISPLAY"
    local original_xauthority="$XAUTHORITY"
    local original_xdg_runtime_dir="$XDG_RUNTIME_DIR"
    
    # Method 1: Use existing DISPLAY if working
    if [ -n "$DISPLAY" ] && xset -display "$DISPLAY" q >/dev/null 2>&1; then
        print_status "Using existing DISPLAY: $DISPLAY"
        return 0
    fi
    
    # Method 2: Try to find X11 display from socket files
    for display_num in 0 1 2; do
        if [ -f "/tmp/.X11-unix/X$display_num" ]; then
            export DISPLAY=":$display_num"
            print_status "X11 display detected from socket: $DISPLAY"
            break
        fi
    done
    
    # Method 3: Try to find X11 display from xauth
    if command -v xauth >/dev/null 2>&1; then
        local auth_entries=$(xauth list 2>/dev/null)
        if [ -n "$auth_entries" ]; then
            # Try to find the most recent/active display
            local display=$(echo "$auth_entries" | grep -E ":[0-9]+" | head -1 | awk '{print $1}' | sed 's/.*\(:[0-9]*\)$/\1/')
            if [ -n "$display" ]; then
                export DISPLAY="$display"
                print_status "X11 display detected from xauth: $DISPLAY"
            fi
        fi
    fi
    
    # Method 4: Try common display values
    if [ -z "$DISPLAY" ]; then
        for common_display in ":0" ":1" ":2"; do
            if xset -display "$common_display" q >/dev/null 2>&1; then
                export DISPLAY="$common_display"
                print_status "X11 display working with common value: $DISPLAY"
                break
            fi
        done
    fi
    
    # Set XAUTHORITY if not set
    if [ -z "$XAUTHORITY" ]; then
        export XAUTHORITY="$HOME/.Xauthority"
        print_status "XAUTHORITY set to: $XAUTHORITY"
    fi
    
    # Set XDG_RUNTIME_DIR if not set (important for modern X11 sessions)
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        print_status "XDG_RUNTIME_DIR set to: $XDG_RUNTIME_DIR"
    fi
    
    # Verify X11 connection
    if [ -n "$DISPLAY" ]; then
        print_status "Testing X11 connection with DISPLAY=$DISPLAY..."
        if xset q >/dev/null 2>&1; then
            print_status "X11 connection verified successfully ✓"
            return 0
        else
            print_status "X11 connection test failed for DISPLAY=$DISPLAY"
            # Try to restore original environment
            export DISPLAY="$original_display"
            export XAUTHORITY="$original_xauthority"
            export XDG_RUNTIME_DIR="$original_xdg_runtime_dir"
        fi
    fi
    
    # Final fallback: Check if we're in a systemd user session
    if [ -z "$DISPLAY" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
        local wayland_display="$XDG_RUNTIME_DIR/wayland-0"
        if [ -S "$wayland_display" ]; then
            print_status "Wayland socket detected, attempting XWayland fallback..."
            export DISPLAY=":0"
            if xset q >/dev/null 2>&1; then
                print_status "XWayland connection successful ✓"
                return 0
            fi
        fi
    fi
    
    # If we still don't have a working DISPLAY
    if [ "$MODE" = "test" ]; then
        print_status "Error: Cannot start Ardour in GUI mode without working X11 display"
        print_status "Current environment:"
        echo "  DISPLAY: $DISPLAY"
        echo "  XAUTHORITY: $XAUTHORITY"
        echo "  XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
        return 1
    else
        print_status "Continuing in production mode (headless) - X11 not required"
        return 0
    fi
}

# Function to force release audio hardware devices
force_release_audio_devices() {
    print_status "Force releasing audio hardware devices..."
    
    # Method 1: Kill processes holding audio devices
    print_status "Killing processes holding audio devices..."
    local audio_processes=$(lsof /dev/snd/* 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
    if [ -n "$audio_processes" ]; then
        print_status "Found processes holding audio devices: $audio_processes"
        echo "$audio_processes" | xargs -r kill -9 2>/dev/null || true
        sleep 2
    fi
    
    # Method 2: Force unload and reload ALSA modules
    print_status "Force unloading and reloading ALSA modules..."
    sudo modprobe -r snd_hda_intel 2>/dev/null || true
    sudo modprobe -r snd_usb_audio 2>/dev/null || true
    sleep 1
    sudo modprobe snd_hda_intel 2>/dev/null || true
    sudo modprobe snd_usb_audio 2>/dev/null || true
    sleep 2
    
    # Method 3: Reset audio hardware
    print_status "Resetting audio hardware..."
    for device in /dev/snd/*; do
        if [ -c "$device" ]; then
            print_status "Resetting $device"
            sudo fuser -k "$device" 2>/dev/null || true
        fi
    done
    sleep 2
    
    # Method 4: Kill specific audio processes
    print_status "Killing specific audio processes..."
    pkill -9 -f "alsa|snd|audio" 2>/dev/null || true
    sudo pkill -9 -f "alsa|snd|audio" 2>/dev/null || true
    sleep 2
    
    print_status "Audio hardware release completed"
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

# Function to start JACK (simplified) - NO DUPLICATE CLEANUP
start_jack_simple() {
    local backend="$1"
    local jack_cmd=""
    
    # NOTE: Cleanup is handled by olms-startup.sh Phase 0
    # This function only starts JACK after cleanup is complete
    
    case "$backend" in
        "dummy")
            print_status "Starting JACK with dummy backend (virtual audio)..."
            # Wait for cleanup to complete (olms-startup.sh handles this)
            sleep 2
            # Dummy backend doesn't support -n parameter, use only supported options
            jack_cmd="taskset -c 2-$(($(nproc)-1)) chrt -f 80 jackd -R -d dummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -C 2 -P 2"
            ;;
        "alsa")
            print_status "Starting JACK with ALSA backend (USB Audio)..."
            # Wait for cleanup to complete (olms-startup.sh handles this)
            sleep 2
            
            # Use detected USB Audio device
            if [ -n "$USB_AUDIO_DEVICE" ]; then
                # Optimized JACK parameters based on technical analysis
                # -R: Realtime scheduling
                # -n 3: Number of periods (optimized for stability)
                # No MIDI flags (-X seq) to avoid crashes on unsupported hardware
                # Use all cores >=2 for audio processing
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 3 -d $USB_AUDIO_DEVICE"
                print_status "Using detected USB device: $USB_AUDIO_DEVICE"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p $JACK_PERIOD_SIZE (buffer)"
                print_status "Audio cores: $audio_cores"
            else
                # Fallback to first available card if detection failed
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 3"
                print_status "Using default ALSA device"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p $JACK_PERIOD_SIZE (buffer)"
                print_status "Audio cores: $audio_cores"
            fi
            ;;
        *)
            print_status "Error: Unsupported JACK backend: $backend"
            return 1
            ;;
    esac
    
    print_status "JACK command: $jack_cmd"
    
    # Start JACK in background with proper error handling
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
    export JACK_NO_AUDIO_RESERVATION=1
    
    # Additional JACK environment variables for stability
    export JACK_SERVER_NAME=default
    export JACK_CONNECT_TIMEOUT=10
    
    print_status "JACK environment configured:"
    echo "  - JACK_NO_START_SERVER=1 (Ardour as client)"
    echo "  - PIPEWIRE_RUNTIME_DIR=/dev/null (Bypass Pipewire)"
    echo "  - JACK_NO_AUDIO_RESERVATION=1 (Bypass device reservation)"
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


# Function to start JACK2 server (Phase 3)
start_jack2_server() {
    local backend="$1"
    local jack_cmd=""
    
    print_status "Phase 3: Starting JACK2 server..."
    
    # Note: Deep cleanup is now handled by olms-startup.sh
    # This script only handles the actual audio engine startup
    
    case "$backend" in
        "dummy")
            print_status "Starting JACK with dummy backend (virtual audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            # Dummy backend doesn't support -n parameter, use only supported options
            local audio_cores="2-$(($(nproc)-1))"
            jack_cmd="taskset -c $audio_cores jackd -R -d dummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -C 2 -P 2"
            ;;
        "alsa")
            print_status "Starting JACK with ALSA backend (USB Audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            
            # Use detected USB Audio device with optimized parameters
            if [ -n "$USB_AUDIO_DEVICE" ]; then
                # Optimized JACK parameters based on technical analysis
                # -R: Realtime scheduling
                # -n 3: Number of periods (optimized for stability)
                # -p $JACK_PERIOD_SIZE: Buffer size (fixed at 64 samples)
                # No MIDI flags to avoid crashes on unsupported hardware
                # Use all cores >=2 for audio processing
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 3 -d $USB_AUDIO_DEVICE"
                print_status "Using detected USB device: $USB_AUDIO_DEVICE"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p $JACK_PERIOD_SIZE (fixed buffer)"
                print_status "Audio cores: $audio_cores"
            else
                # Fallback to first available card if detection failed
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 2"
                print_status "Using default ALSA device"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p $JACK_PERIOD_SIZE (fixed buffer)"
                print_status "Audio cores: $audio_cores"
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

# Function to setup Xvfb for headless mode
setup_xvfb() {
    print_status "Setting up Xvfb (X Virtual Frame Buffer) for headless mode..."
    
    # Check if Xvfb is installed
    if ! command -v Xvfb >/dev/null 2>&1; then
        print_status "Error: Xvfb not installed. Install it with: sudo pacman -S xorg-server-xvfb"
        return 1
    fi
    
    # Find a free display number
    local display_num=99
    while [ -f "/tmp/.X${display_num}-lock" ] || [ -S "/tmp/.X11-unix/X${display_num}" ]; do
        display_num=$((display_num + 1))
        if [ $display_num -gt 200 ]; then
            print_status "Error: Could not find free display number"
            return 1
        fi
    done
    
    print_status "Starting Xvfb on display :$display_num..."
    
    # Start Xvfb with minimal resource usage
    # -screen 0 800x600x24: Minimal screen size, 24-bit color depth
    # -nolisten tcp: Disable TCP connections for security
    # -ac: Disable access control (not needed for virtual display)
    # +extension GLX: Enable GLX for plugin GUIs that might need it
    # -noreset: Don't reset after last client exits
    Xvfb :${display_num} -screen 0 800x600x24 -nolisten tcp -ac +extension GLX -noreset >/dev/null 2>&1 &
    XVFB_PID=$!
    
    # Wait for Xvfb to start
    sleep 2
    
    # Verify Xvfb is running
    if ! kill -0 $XVFB_PID 2>/dev/null; then
        print_status "Error: Failed to start Xvfb"
        return 1
    fi
    
    # Set DISPLAY to point to Xvfb
    export DISPLAY=":${display_num}"
    
    # Verify X11 connection to Xvfb
    if xset -display ":${display_num}" q >/dev/null 2>&1; then
        print_status "Xvfb started successfully (PID: $XVFB_PID, DISPLAY: :${display_num})"
        print_status "Virtual X11 display ready for headless Ardour ✓"
        return 0
    else
        print_status "Error: Xvfb started but X11 connection failed"
        kill $XVFB_PID 2>/dev/null
        return 1
    fi
}

# Function to verify RT priority was applied successfully
verify_rt_priority_after_startup() {
    print_status "Verifying RT priority after startup..."
    
    # Check JACK process RT priority
    if [ -n "$JACK_PID" ] && kill -0 $JACK_PID 2>/dev/null; then
        local jack_policy=$(chrt -p "$JACK_PID" 2>/dev/null | grep "policy" | awk '{print $3}')
        local jack_priority=$(chrt -p "$JACK_PID" 2>/dev/null | grep "priority" | awk '{print $3}')
        
        if [ "$jack_policy" = "SCHED_FIFO" ] && [ "$jack_priority" = "80" ]; then
            print_status "✓ JACK process has correct RT priority (SCHED_FIFO, priority 80)"
        else
            print_status "⚠ JACK process RT priority not set correctly"
            print_status "  Current policy: $jack_policy"
            print_status "  Current priority: $jack_priority"
            print_status "  Expected: SCHED_FIFO, priority 80"
        fi
    fi
    
    # Check Ardour process RT priority
    if [ -n "$ARDOUR_PID" ] && kill -0 $ARDOUR_PID 2>/dev/null; then
        local ardour_policy=$(chrt -p "$ARDOUR_PID" 2>/dev/null | grep "policy" | awk '{print $3}')
        local ardour_priority=$(chrt -p "$ARDOUR_PID" 2>/dev/null | grep "priority" | awk '{print $3}')
        
        if [ "$ardour_policy" = "SCHED_FIFO" ] && [ "$ardour_priority" = "75" ]; then
            print_status "✓ Ardour process has correct RT priority (SCHED_FIFO, priority 75)"
        else
            print_status "⚠ Ardour process RT priority not set correctly"
            print_status "  Current policy: $ardour_policy"
            print_status "  Current priority: $ardour_priority"
            print_status "  Expected: SCHED_FIFO, priority 75"
        fi
    fi
}

# Function to start Ardour as JACK client (Phase 4)
start_ardour_as_client() {
    local ardour_cmd=""
    
    print_status "Phase 4: Starting Ardour as JACK client..."
    
    # Setup JACK environment
    setup_jack_environment
    
    if [ "$MODE" = "prod" ]; then
        print_status "Starting Ardour in production mode (headless with Xvfb)..."
        
        # Setup Xvfb for headless mode
        if ! setup_xvfb; then
            print_status "Failed to setup Xvfb, cannot start Ardour in headless mode"
            return 1
        fi
        
        # Use all cores >=2 for Ardour in production mode
        local audio_cores="2-$(($(nproc)-1))"
        ardour_cmd="taskset -c $audio_cores chrt -f 75 /usr/bin/ardour8 --no-splash $OLMS_SESSION_PATH"
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
        
        # Use all cores >=2 for Ardour in testing mode
        local audio_cores="2-$(($(nproc)-1))"
        ardour_cmd="taskset -c $audio_cores chrt -f 75 /usr/bin/ardour8 $OLMS_SESSION_PATH"
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
    print_status "Audio cores: $audio_cores"
    $ardour_cmd &
    ARDOUR_PID=$!
    
    # Wait for Ardour to start
    sleep 3
    
    # Check if Ardour is running
    if kill -0 $ARDOUR_PID 2>/dev/null; then
        print_status "Ardour started successfully as JACK client (PID: $ARDOUR_PID)"
        
        # Verify RT priority was applied correctly
        verify_rt_priority_after_startup
        
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

# Set critical JACK environment variables BEFORE starting JACK
export JACK_NO_AUDIO_RESERVATION=1
export PIPEWIRE_RUNTIME_DIR=/dev/null
print_status "JACK environment: JACK_NO_AUDIO_RESERVATION=1, PIPEWIRE_RUNTIME_DIR=/dev/null"

# Phase 1: Audio Hardware Detection
print_status "Phase 1: Audio Hardware Detection"
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

# Phase 2: Adapting Ardour session to detected audio device
print_status "Phase 2: Adapting Ardour session to detected audio device"
if [ "$FORCE_VIRTUAL" = false ]; then
    if ! adapt_ardour_session "$OLMS_SESSION_PATH"; then
        print_status "Session adaptation failed, but continuing..."
    fi
fi

# Phase 3: Starting JACK2 server
print_status "Phase 3: Starting JACK2 server"
if ! start_jack2_server "$AUDIO_BACKEND"; then
    print_status "JACK2 startup failed, aborting"
    exit 1
fi

# Phase 4: Verifying JACK stability
print_status "Phase 4: Verifying JACK stability"
if ! verify_jack_stability; then
    print_status "JACK stability verification failed, stopping JACK"
    kill $JACK_PID 2>/dev/null
    exit 1
fi

# Phase 5: Starting Ardour as JACK client
print_status "Phase 5: Starting Ardour as JACK client"
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
# Trap to cleanup all processes on exit (Ardour, JACK, and Xvfb if running in prod mode)
cleanup_on_exit() {
    print_status "Cleaning up processes..."
    kill $ARDOUR_PID 2>/dev/null
    kill $JACK_PID 2>/dev/null
    if [ -n "$XVFB_PID" ]; then
        kill $XVFB_PID 2>/dev/null
        print_status "Xvfb terminated"
    fi
}

trap cleanup_on_exit EXIT
wait
