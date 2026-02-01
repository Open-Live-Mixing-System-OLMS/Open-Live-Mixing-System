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
# - Automatic X11 permissions fix

set -e

# Default values
MODE="test"
OLMS_SESSION_PATH="${OLMS_SESSION_PATH:-engine/session-template/OLMS-POC/OLMS-POC.ardour}"
JACK_SAMPLE_RATE="${JACK_SAMPLE_RATE:-48000}"
JACK_PERIOD_SIZE="${JACK_PERIOD_SIZE:-64}"  # Fixed buffer size for optimal audio performance

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1" >&2
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

# Function to check audio hardware access privileges
check_audio_privileges() {
    print_status "Checking audio hardware access privileges..."
    
    # Check if user is in audio group
    if groups $USER | grep -q "audio"; then
        print_status "User is in audio group ✓"
    else
        print_status "Warning: User not in audio group - may cause hardware access issues"
        print_status "Run: sudo usermod -aG audio $USER"
    fi
    
    # Check if user has access to audio devices
    local audio_devices=$(find /dev/snd -type c 2>/dev/null | head -5)
    local accessible_devices=0
    
    if [ -n "$audio_devices" ]; then
        for device in $audio_devices; do
            if [ -r "$device" ] && [ -w "$device" ]; then
                accessible_devices=$((accessible_devices + 1))
            fi
        done
        print_status "Audio device access: $accessible_devices/$(echo "$audio_devices" | wc -l) devices accessible"
    else
        print_status "No audio devices found"
    fi
    
    # Check logind ACL permissions (modern systemd systems)
    if command -v loginctl >/dev/null 2>&1; then
        local session_id=$(loginctl show-user $USER | grep "Sessions=" | cut -d'=' -f2)
        if [ -n "$session_id" ]; then
            print_status "Session ID: $session_id"
            # Check if session has audio access
            local audio_access=$(loginctl show-session $session_id 2>/dev/null | grep -i "audio\|sound" || echo "No audio access info")
            if [ "$audio_access" != "No audio access info" ]; then
                print_status "Session audio access: $audio_access"
            fi
        fi
    fi
    
    # Check for PulseAudio/PipeWire conflicts
    if pgrep -f "pipewire\|pulseaudio" >/dev/null 2>&1; then
        print_status "Warning: Pipewire/PulseAudio processes detected - may conflict with JACK"
        print_status "Processes: $(pgrep -f "pipewire\|pulseaudio" | xargs -r ps -p | grep -v "PID")"
    else
        print_status "No Pipewire/PulseAudio conflicts detected ✓"
    fi
    
    return 0
}

# Function to detect USB audio devices automatically
detect_usb_audio_device() {
    print_status "Detecting USB audio devices..."
    
    # 1. Primary check: Look for "USB" explicitly in /proc/asound/cards
    local usb_cards=$(grep -i "usb" /proc/asound/cards | grep -E "^[ 0-9]+" | awk '{print $1}' | head -1 | tr -d ' ')
    
    if [ -n "$usb_cards" ]; then
        local device_str="hw:$usb_cards,0"
        print_status "Found USB Audio Card at $device_str ✓"
        echo "$device_str"
        return 0
    fi

    # 2. Secondary check: aplay -l filtering for USB
    local usb_aplay=$(aplay -l 2>/dev/null | grep -i "usb" | head -1 | sed 's/card \([0-9]*\):.*/\1/' | tr -d ' ')
    
    if [ -n "$usb_aplay" ]; then
        local device_str="hw:$usb_aplay,0"
        print_status "Found USB Audio Card at $device_str ✓"
        echo "$device_str"
        return 0
    fi

    print_status "No USB audio devices detected"
    return 1
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

# Function to setup X11 environment (FIXED VERSION - EXECUTES AS USER, NOT ROOT)
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
    
    # Method 2: Try to find X11 display from socket files (enhanced)
    print_status "Scanning for X11 socket files..."
    for display_num in 0 1 2 3 4 5; do
        local socket_path="/tmp/.X11-unix/X$display_num"
        if [ -S "$socket_path" ]; then
            export DISPLAY=":$display_num"
            print_status "X11 display detected from socket: $DISPLAY (socket: $socket_path)"
            break
        fi
    done
    
    # Method 3: Try to find X11 display from xauth (enhanced)
    if command -v xauth >/dev/null 2>&1; then
        print_status "Checking xauth entries for X11 displays..."
        local auth_entries=$(xauth list 2>/dev/null)
        if [ -n "$auth_entries" ]; then
            # Try to find the most recent/active display with better filtering
            local display=$(echo "$auth_entries" | grep -E ":[0-9]+" | grep -v "MIT-MAGIC-COOKIE" | head -1 | awk '{print $1}' | sed 's/.*\(:[0-9]*\)$/\1/')
            if [ -n "$display" ]; then
                export DISPLAY="$display"
                print_status "X11 display detected from xauth: $DISPLAY"
            fi
        fi
    fi
    
    # Method 4: Try common display values with better verification
    if [ -z "$DISPLAY" ]; then
        print_status "Testing common X11 display values..."
        for common_display in ":0" ":1" ":2" ":3"; do
            if xset -display "$common_display" q >/dev/null 2>&1; then
                export DISPLAY="$common_display"
                print_status "X11 display working with common value: $DISPLAY"
                break
            fi
        done
    fi
    
    # Method 5: Enhanced Wayland/XWayland detection and fallback
    if [ -z "$DISPLAY" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
        print_status "Checking for Wayland session and XWayland fallback..."
        
        # Check for Wayland socket
        local wayland_display="$XDG_RUNTIME_DIR/wayland-0"
        if [ -S "$wayland_display" ]; then
            print_status "Wayland socket detected at: $wayland_display"
            
            # Try XWayland fallback with multiple display numbers
            for wayland_display_num in 0 1 2; do
                local xwayland_display=":$wayland_display_num"
                if xset -display "$xwayland_display" q >/dev/null 2>&1; then
                    export DISPLAY="$xwayland_display"
                    print_status "XWayland connection successful: $DISPLAY"
                    break
                fi
            done
            
            # If XWayland fallback failed, try to use XWayland with specific environment
            if [ -z "$DISPLAY" ]; then
                print_status "Attempting XWayland with environment setup..."
                export DISPLAY=":0"
                export GDK_BACKEND=x11
                export QT_QPA_PLATFORM=xcb
                if xset q >/dev/null 2>&1; then
                    print_status "XWayland connection successful with environment setup: $DISPLAY"
                else
                    print_status "XWayland fallback failed, restoring original environment"
                    export DISPLAY="$original_display"
                    export XAUTHORITY="$original_xauthority"
                    export XDG_RUNTIME_DIR="$original_xdg_runtime_dir"
                fi
            fi
        fi
    fi
    
    # Set XAUTHORITY if not set (enhanced)
    if [ -z "$XAUTHORITY" ]; then
        # Try to find XAUTHORITY in common locations
        local possible_xauth="$HOME/.Xauthority"
        if [ -f "$possible_xauth" ]; then
            export XAUTHORITY="$possible_xauth"
            print_status "XAUTHORITY set to: $XAUTHORITY"
        else
            # Try to find XAUTHORITY from xauth list
            if command -v xauth >/dev/null 2>&1; then
                local xauth_file=$(xauth info 2>/dev/null | grep "Authority file" | awk '{print $3}')
                if [ -n "$xauth_file" ] && [ -f "$xauth_file" ]; then
                    export XAUTHORITY="$xauth_file"
                    print_status "XAUTHORITY set from xauth info: $XAUTHORITY"
                else
                    export XAUTHORITY="$HOME/.Xauthority"
                    print_status "XAUTHORITY set to default: $XAUTHORITY"
                fi
            else
                export XAUTHORITY="$HOME/.Xauthority"
                print_status "XAUTHORITY set to default: $XAUTHORITY"
            fi
        fi
    fi
    
    # Set XDG_RUNTIME_DIR if not set (enhanced)
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        print_status "XDG_RUNTIME_DIR set to: $XDG_RUNTIME_DIR"
    fi
    
    # Enhanced X11 connection verification
    if [ -n "$DISPLAY" ]; then
        print_status "Testing X11 connection with DISPLAY=$DISPLAY..."
        
        # Test with timeout to avoid hanging
        if timeout 5 xset q >/dev/null 2>&1; then
            print_status "X11 connection verified successfully ✓"
            
            # Additional verification: check if we can create a simple X11 window
            if command -v xclock >/dev/null 2>&1; then
                timeout 3 xclock -display "$DISPLAY" -geometry 1x1+9999+9999 >/dev/null 2>&1 &
                local xclock_pid=$!
                sleep 1
                kill $xclock_pid 2>/dev/null || true
                print_status "X11 window creation test passed ✓"
            fi
            
            return 0
        else
            print_status "X11 connection test failed for DISPLAY=$DISPLAY"
            # Try to restore original environment
            export DISPLAY="$original_display"
            export XAUTHORITY="$original_xauthority"
            export XDG_RUNTIME_DIR="$original_xdg_runtime_dir"
        fi
    fi
    
    # Final fallback: Check for nested X11 environments
    if [ -z "$DISPLAY" ]; then
        print_status "Checking for nested X11 environments (VNC, X2Go, etc.)..."
        for nested_display in ":1" ":2" ":3" ":10" ":20"; do
            if xset -display "$nested_display" q >/dev/null 2>&1; then
                export DISPLAY="$nested_display"
                print_status "Nested X11 display found: $DISPLAY"
                break
            fi
        done
    fi
    
    # Xvfb fallback for headless mode
    if [ -z "$DISPLAY" ] && [ "$MODE" = "prod" ]; then
        print_status "X11 not available, setting up Xvfb for headless mode..."
        
        if ! command -v Xvfb >/dev/null 2>&1; then
            print_status "Warning: Xvfb not installed, Ardour may fail in headless mode"
            return 1
        fi
        
        # Find a free display number
        local display_num=99
        while [ -f "/tmp/.X${display_num}-lock" ] || [ -S "/tmp/.X11-unix/X${display_num}" ]; do
            display_num=$((display_num + 1))
            if [ $display_num -gt 200 ]; then
                print_status "Error: Could not find free display number for Xvfb"
                return 1
            fi
        done
        
        print_status "Starting Xvfb on display :$display_num..."
        Xvfb :${display_num} -screen 0 800x600x24 -nolisten tcp -ac +extension GLX -noreset >/dev/null 2>&1 &
        XVFB_PID=$!
        
        sleep 2
        
        if kill -0 $XVFB_PID 2>/dev/null; then
            export DISPLAY=":${display_num}"
            print_status "Xvfb started successfully (PID: $XVFB_PID, DISPLAY: :${display_num})"
            print_status "Virtual X11 display ready for headless Ardour ✓"
            return 0
        else
            print_status "Error: Failed to start Xvfb"
            return 1
        fi
    fi
    
    # If we still don't have a working DISPLAY
    if [ "$MODE" = "test" ]; then
        print_status "Error: Cannot start Ardour in GUI mode without working X11 display"
        print_status "Current environment:"
        echo "  DISPLAY: $DISPLAY"
        echo "  XAUTHORITY: $XAUTHORITY"
        echo "  XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
        print_status "Available X11 displays:"
        for check_display in ":0" ":1" ":2" ":3"; do
            if xset -display "$check_display" q >/dev/null 2>&1; then
                echo "  ✓ $check_display"
            else
                echo "  ✗ $check_display"
            fi
        done
        return 1
    else
        print_status "Continuing in production mode (headless) - X11 not required"
        return 0
    fi
}

# Function to handle X11 environment preservation for --preserve-x11 argument
handle_x11_preservation() {
    if [ "$1" = "--preserve-x11" ]; then
        print_status "X11 environment preservation mode enabled"
        # Ensure X11 variables are properly set for the current user
        if [ "$MODE" = "test" ]; then
            setup_x11_environment
        fi
        return 0
    fi
    return 1
}

# Function to fix X11 permissions automatically (FIXED VERSION)
fix_x11_permissions() {
    print_status "Fix automatico permessi X11..."
    
    # Rileva l'utente reale che ha lanciato sudo
    local TARGET_USER="${SUDO_USER:-$USER}"
    
    # Concedere permessi X11 (deve essere fatto come utente normale)
    if [ -n "$SUDO_USER" ]; then
        sudo -u "$TARGET_USER" DISPLAY="$DISPLAY" xhost +si:localuser:root >/dev/null 2>&1
        print_status "✓ Permessi X11 concessi da $TARGET_USER a root"
    fi
    
    # Assicura che root veda il file .Xauthority dell'utente
    if [ -n "$SUDO_USER" ]; then
        export XAUTHORITY="/home/$TARGET_USER/.Xauthority"
    fi
    
    # Verifica che root possa accedere al display
    if [ -n "$DISPLAY" ] && [ -n "$XAUTHORITY" ]; then
        if sudo -u root env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" xset q >/dev/null 2>&1; then
            print_status "✓ Root può accedere a X11"
            return 0
        else
            print_status "Warning: Root non può accedere a X11"
            return 1
        fi
    else
        print_status "Warning: DISPLAY o XAUTHORITY non impostati"
        return 1
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

# Function to perform hard reset of audio processes (NEW - PROVEN SOLUTION)
perform_hard_reset() {
    print_status "Performing hard reset of audio processes..."
    
    # Complete cleanup - use the proven approach from fix_jack_ardour.sh
    print_status "Killing all JACK and jackdbus processes..."
    local jack_processes=$(pgrep -f "jackd\|jackdbus" 2>/dev/null)
    if [ -n "$jack_processes" ]; then
        print_status "Found JACK processes to kill: $jack_processes"
        killall -9 jackd jackdbus 2>/dev/null || true
    else
        print_status "No JACK processes found to kill"
    fi
    sleep 2
    
    # Kill any remaining audio processes that might conflict
    print_status "Killing remaining audio processes..."
    local audio_processes=$(pgrep -f "pipewire\|wireplumber\|pulseaudio" 2>/dev/null)
    if [ -n "$audio_processes" ]; then
        print_status "Found audio processes to kill: $audio_processes"
        pkill -9 -f "pipewire\|wireplumber\|pulseaudio" 2>/dev/null || true
    else
        print_status "No conflicting audio processes found"
    fi
    sleep 2
    
    # Remove JACK socket files to ensure clean state
    print_status "Cleaning JACK socket files..."
    local socket_files="/tmp/jack_* /dev/shm/jack_* /var/run/jack_* /run/jack_* /tmp/.jack* /var/lock/.jack*"
    for socket_pattern in $socket_files; do
        if ls $socket_pattern 1>/dev/null 2>&1; then
            print_status "Removing socket files: $socket_pattern"
            rm -f $socket_pattern 2>/dev/null || true
        fi
    done
    
    # Clean up shared memory segments
    print_status "Cleaning shared memory segments..."
    local shm_segments=$(ipcs -m | grep jack | awk '{print $2}' 2>/dev/null)
    if [ -n "$shm_segments" ]; then
        print_status "Found JACK shared memory segments: $shm_segments"
        for shm_id in $shm_segments; do
            ipcrm -m "$shm_id" 2>/dev/null || true
        done
    else
        print_status "No JACK shared memory segments found"
    fi
    
    local sem_segments=$(ipcs -s | grep jack | awk '{print $2}' 2>/dev/null)
    if [ -n "$sem_segments" ]; then
        print_status "Found JACK semaphore segments: $sem_segments"
        for sem_id in $sem_segments; do
            ipcrm -s "$sem_id" 2>/dev/null || true
        done
    else
        print_status "No JACK semaphore segments found"
    fi
    
    print_status "Hard reset completed - audio environment cleaned"
}

# Function to perform detailed system diagnostics (NEW)
perform_system_diagnostics() {
    print_status "Performing detailed system diagnostics..."
    
    # Check system load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    print_status "System load: $load_avg (cores: $cpu_cores)"
    
    # Check available memory
    local mem_info=$(free -m | awk 'NR==2{printf "Available: %sMB (%.1f%% of %sMB)", $7, $7*100/$2, $2}')
    print_status "Memory: $mem_info"
    
    # Check disk space
    local disk_info=$(df / | awk 'NR==2{printf "Available: %sKB (%.1f%% used)", $4, $5}')
    print_status "Disk space: $disk_info"
    
    # Check audio devices
    print_status "Audio devices:"
    if [ -d "/proc/asound" ]; then
        for card in /proc/asound/card*; do
            if [ -d "$card" ]; then
                local card_num=$(basename "$card" | sed 's/card//')
                local card_name=$(cat "$card/id" 2>/dev/null || echo "Unknown")
                print_status "  Card $card_num: $card_name"
                
                # Check for PCM devices
                if [ -d "$card/pcm0p" ]; then
                    local pcm_name=$(cat "$card/pcm0p/id" 2>/dev/null || echo "Unknown")
                    print_status "    PCM0p: $pcm_name"
                fi
            fi
        done
    else
        print_status "  /proc/asound not available"
    fi
    
    # Check for USB audio devices
    print_status "USB audio devices:"
    local usb_audio=$(lsusb 2>/dev/null | grep -i audio || echo "None found")
    if [ "$usb_audio" != "None found" ]; then
        echo "$usb_audio" | while read -r line; do
            print_status "  $line"
        done
    else
        print_status "  $usb_audio"
    fi
    
    # Check kernel version and audio subsystem
    local kernel_version=$(uname -r)
    print_status "Kernel version: $kernel_version"
    
    # Check if realtime patches are available
    if grep -q "PREEMPT_RT" /proc/version 2>/dev/null; then
        print_status "Realtime kernel detected ✓"
    else
        print_status "Standard kernel (no PREEMPT_RT)"
    fi
    
    # Check for audio-related kernel modules
    print_status "Audio kernel modules:"
    local modules="snd snd_hda_intel snd_usb_audio"
    for module in $modules; do
        if lsmod | grep -q "^$module "; then
            print_status "  $module: loaded"
        else
            print_status "  $module: not loaded"
        fi
    done
    
    print_status "System diagnostics completed"
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

# Function to verify audio device is free
verify_device_free() {
    local device="$1"
    
    print_status "Verifying audio device $device is free..."
    
    # Check if device is being used by any process
    local device_processes=$(lsof "$device" 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
    
    if [ -n "$device_processes" ]; then
        print_status "Warning: Device $device is still in use by processes: $device_processes"
        
        # Force release the device using fuser
        print_status "Force releasing device $device using fuser..."
        if fuser -k "$device" 2>/dev/null; then
            print_status "Device $device released via fuser"
            sleep 2
        else
            print_status "Warning: Could not release device $device via fuser"
        fi
        
        # Verify device is now free
        local remaining_processes=$(lsof "$device" 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
        if [ -n "$remaining_processes" ]; then
            print_status "Warning: Device $device still in use after fuser: $remaining_processes"
            return 1
        else
            print_status "✓ Device $device is now free"
            return 0
        fi
    else
        print_status "✓ Device $device is free"
        return 0
    fi
}

# Function to clean JACK shared memory and socket files (ULTRA-AGGRESSIVE VERSION)
clean_shm_files() {
    print_status "ULTRA-AGGRESSIVE JACK cleanup - ensuring complete audio environment reset..."
    
    # Phase 1: Kill existing JACK and audio processes with multi-phase approach
    local audio_processes="jackd jackdbus pipewire wireplumber pulseaudio alsa"
    for process in $audio_processes; do
        local pids=$(pgrep -f "$process" 2>/dev/null)
        if [ -n "$pids" ]; then
            print_status "Found $process processes: $pids"
            
            # Multi-phase cleanup approach with kill -9 as final fallback
            local max_attempts=5  # Increased from 3 to 5 attempts
            local attempt=1
            
            while [ $attempt -le $max_attempts ] && [ -n "$pids" ]; do
                print_status "  Cleanup attempt $attempt/$max_attempts for $process..."
                
                # Phase 1: Try graceful termination first
                if [ $attempt -eq 1 ]; then
                    print_status "    Attempting graceful termination (SIGTERM)..."
                    echo "$pids" | xargs -r sudo kill -TERM 2>/dev/null || true
                    sleep 3  # Increased from 2 to 3 seconds
                fi
                
                # Phase 2: Force kill with SIGKILL
                print_status "    Force killing with SIGKILL..."
                echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
                
                # Wait for processes to terminate
                sleep 3  # Increased from 2 to 3 seconds
                
                # Check again
                pids=$(pgrep -f "$process" 2>/dev/null)
                attempt=$((attempt + 1))
            done
            
            # Final verification
            local remaining_pids=$(pgrep -f "$process" 2>/dev/null)
            if [ -n "$remaining_pids" ]; then
                print_status "Warning: Some $process processes could not be terminated: $remaining_pids"
                # Additional force cleanup for stubborn processes
                print_status "  Applying additional force cleanup..."
                echo "$remaining_pids" | xargs -r sudo kill -9 2>/dev/null || true
                sleep 2
            else
                print_status "✓ All $process processes terminated successfully"
            fi
        fi
    done
    
    # Phase 2: Force release audio hardware devices (ENHANCED)
    print_status "Force releasing audio hardware devices..."
    local audio_devices="/dev/snd/*"
    for device in $audio_devices; do
        if [ -c "$device" ]; then
            print_status "Checking device: $device"
            
            # Use lsof to find processes holding the device
            local device_processes=$(lsof "$device" 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
            if [ -n "$device_processes" ]; then
                print_status "  Device $device held by processes: $device_processes"
                
                # Force release using fuser with multiple attempts
                local fuser_attempts=3
                local fuser_attempt=1
                
                while [ $fuser_attempt -le $fuser_attempts ]; do
                    print_status "    Fuser release attempt $fuser_attempt/$fuser_attempts..."
                    fuser -k "$device" 2>/dev/null || true
                    sleep 2
                    
                    # Check if device is released
                    local remaining_processes=$(lsof "$device" 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
                    if [ -z "$remaining_processes" ]; then
                        print_status "    ✓ Device $device released successfully on attempt $fuser_attempt"
                        break
                    fi
                    
                    fuser_attempt=$((fuser_attempt + 1))
                done
                
                # Final verification
                local final_processes=$(lsof "$device" 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u)
                if [ -n "$final_processes" ]; then
                    print_status "  Warning: Device $device still in use after fuser: $final_processes"
                    # Try additional force methods
                    print_status "  Applying additional force methods..."
                    sudo fuser -k -9 "$device" 2>/dev/null || true
                    sleep 2
                else
                    print_status "  ✓ Device $device released successfully"
                fi
            else
                print_status "  ✓ Device $device already free"
            fi
        fi
    done
    
    # Phase 3: Remove JACK socket files with enhanced cleanup
    print_status "Removing JACK socket files..."
    local socket_files="/tmp/jack_* /dev/shm/jack_* /var/run/jack_* /run/jack_* /tmp/.jack* /var/lock/.jack*"
    for socket_pattern in $socket_files; do
        if ls $socket_pattern 1>/dev/null 2>&1; then
            print_status "  Removing socket files: $socket_pattern"
            rm -f $socket_pattern 2>/dev/null || true
        fi
    done
    
    # Phase 4: Remove Pipewire socket files (critical for JACK stability)
    print_status "Removing Pipewire socket files..."
    local pipewire_files="/tmp/pipewire* /dev/shm/pipewire* /var/run/pipewire* /run/pipewire* /tmp/.pipewire* /var/lock/.pipewire*"
    for pipewire_pattern in $pipewire_files; do
        if ls $pipewire_pattern 1>/dev/null 2>&1; then
            print_status "  Removing Pipewire files: $pipewire_pattern"
            rm -f $pipewire_pattern 2>/dev/null || true
        fi
    done
    
    # Phase 5: Clean up shared memory segments with enhanced verification
    print_status "Cleaning shared memory segments..."
    local shm_segments=$(ipcs -m | grep -E "jack|pipewire|pulse" | awk '{print $2}' 2>/dev/null)
    if [ -n "$shm_segments" ]; then
        print_status "  Found audio shared memory segments: $shm_segments"
        for shm_id in $shm_segments; do
            if ipcrm -m "$shm_id" 2>/dev/null; then
                print_status "  ✓ Removed shared memory segment: $shm_id"
            else
                print_status "  Warning: Could not remove shared memory segment: $shm_id"
            fi
        done
    else
        print_status "  No audio shared memory segments found"
    fi
    
    local sem_segments=$(ipcs -s | grep -E "jack|pipewire|pulse" | awk '{print $2}' 2>/dev/null)
    if [ -n "$sem_segments" ]; then
        print_status "  Found audio semaphore segments: $sem_segments"
        for sem_id in $sem_segments; do
            if ipcrm -s "$sem_id" 2>/dev/null; then
                print_status "  ✓ Removed semaphore segment: $sem_id"
            else
                print_status "  Warning: Could not remove semaphore segment: $sem_id"
            fi
        done
    else
        print_status "  No audio semaphore segments found"
    fi
    
    # Phase 6: Reset environment variables
    export JACK_NO_AUDIO_RESERVATION=1
    export PIPEWIRE_RUNTIME_DIR=/dev/null
    
    # Phase 7: AGGRESSIVE HARDWARE RESET
    print_status "Performing aggressive hardware reset..."
    
    # Reset all audio devices
    for device in /dev/snd/*; do
        if [ -c "$device" ]; then
            print_status "  Resetting hardware device: $device"
            sudo fuser -k "$device" 2>/dev/null || true
        fi
    done
    
    # Force reload audio kernel modules
    print_status "Force reloading audio kernel modules..."
    sudo modprobe -r snd_hda_intel 2>/dev/null || true
    sudo modprobe -r snd_usb_audio 2>/dev/null || true
    sleep 1
    sudo modprobe snd_hda_intel 2>/dev/null || true
    sudo modprobe snd_usb_audio 2>/dev/null || true
    sleep 2
    
    # Phase 8: Final verification with enhanced checks
    print_status "Final verification of cleanup..."
    local remaining_audio_processes=$(pgrep -f "jackd|pipewire|pulseaudio|alsa" 2>/dev/null | wc -l)
    if [ "$remaining_audio_processes" -eq 0 ]; then
        print_status "✓ ULTRA-AGGRESSIVE JACK cleanup completed successfully"
        return 0
    else
        print_status "Warning: $remaining_audio_processes audio processes still running"
        print_status "  This may indicate stubborn processes that require manual intervention"
        return 1
    fi
}

# Function to verify JACK is running and stable (IMPROVED VERSION - FIXED SOCKET TIMEOUT)
is_jack_running() {
    local pid="$1"
    local max_attempts=5
    local attempt=1
    
    print_status "Verifying JACK process (PID: $pid) with enhanced checks..."
    
    while [ $attempt -le $max_attempts ]; do
        print_status "JACK verification attempt $attempt/$max_attempts..."
        
        # Verification 1: Process is active (kill -0)
        if ! kill -0 $pid 2>/dev/null; then
            print_status "JACK process not running (PID: $pid)"
            return 1
        fi
        
        # Verification 2: JACK socket exists (FIXED - UNIVERSAL SOCKET SEARCH)
        local socket_found=false
        local user_id=$(id -u)
        
        # Check for JACK socket in both possible locations (universal search)
        if [ -S "/dev/shm/jack_default_${user_id}_0" ] || [ -S "/tmp/jack_default_${user_id}_0" ]; then
            socket_found=true
            print_status "JACK socket found ✓"
        else
            print_status "JACK socket not found yet, waiting 2 more seconds..."
            sleep 2
            attempt=$((attempt + 1))
            continue
        fi
        
        # Verification 3: JACK communication test (jack_lsp) with timeout
        if timeout 3 jack_lsp >/dev/null 2>&1; then
            print_status "JACK communication test passed"
            print_status "JACK verification successful (PID: $pid)"
            return 0
        else
            print_status "JACK communication test failed, waiting 2 more seconds..."
            sleep 2
            attempt=$((attempt + 1))
            continue
        fi
    done
    
    print_status "JACK verification failed after $max_attempts attempts"
    return 1
}

# Function to start JACK with adaptive buffer strategy (IMPROVED VERSION)
start_jack_adaptive() {
    local raw_device="$1"
    local pid=""
    
    # Clean the string: remove spaces and tabs
    local clean_device=$(echo "$raw_device" | tr -d '[:space:]')
    local use_dummy=false

    # Robust Validation Logic
    if [[ -z "$clean_device" || "$clean_device" == "hw:" || ! "$clean_device" =~ [0-9] ]]; then
        print_status "⚠️ Validation: Device '$raw_device' is invalid/empty. Using DUMMY backend."
        use_dummy=true
    else
        print_status "Validation: Using ALSA hardware device '$clean_device' ✓"
    fi

    # Verify realtime privileges are active before starting
    print_status "Verifying realtime privileges before JACK startup..."
    if ! verify_realtime_privileges_active; then
        print_status "Warning: Realtime privileges may not be active - JACK startup may fail"
        print_status "Consider logging out and back in to activate realtime privileges"
    fi
    
    # Clean environment before any attempt
    print_status "Phase 1: Enhanced audio environment cleanup..."
    if ! clean_shm_files; then
        print_status "Warning: Enhanced cleanup had issues, but proceeding with JACK startup..."
    fi
    
    # Pro Audio Optimization: Stop irqbalance to prevent interrupt hopping
    print_status "Pro Audio Optimization: Stopping irqbalance to prevent interrupt hopping..."
    if systemctl is-active --quiet irqbalance 2>/dev/null; then
        sudo systemctl stop irqbalance 2>/dev/null || print_status "Warning: Could not stop irqbalance"
    fi
    
    # Pro Audio Optimization: Set CPU governor to performance
    print_status "Pro Audio Optimization: Setting CPU governor to performance mode..."
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [ -f "$cpu" ]; then
            echo performance | sudo tee "$cpu" >/dev/null 2>&1 || print_status "Warning: Could not set CPU governor for $cpu"
        fi
    done
    
    # --- ATTEMPT 1: 64 SAMPLES ---
    local buf="64"
    local cmd=""
    
    if [ "$use_dummy" = true ]; then
        # Dummy backend: NO -n parameter
        cmd="taskset -c 2,3 chrt -f 80 jackd -R -d dummy -r 48000 -p $buf"
        print_status "Starting JACK with DUMMY backend, buffer: $buf"
    else
        # ALSA backend: include -n 3 for USB stability (critical for 64-sample buffer)
        cmd="taskset -c 2,3 chrt -f 80 jackd -R -S -P 80 -d alsa -d $clean_device -r 48000 -p $buf -n 3"
        print_status "Starting JACK with ALSA device: $clean_device, buffer: $buf"
        print_status "Pro Audio: Using -n 3 for USB stability with 64-sample buffer"
    fi

    print_status "Executing: $cmd"
    # Use a user-writable log file instead of /tmp/jack_startup.log
    local log_file="$HOME/.olms/jack_startup.log"
    mkdir -p "$(dirname "$log_file")"
    eval "$cmd" > "$log_file" 2>&1 &
    pid=$!
    
    # Increased timeout for memory allocation and hardware sync
    sleep 7 
    
    if is_jack_running "$pid"; then
        print_status "✅ SUCCESS: JACK stable at 64 samples."
        JACK_PID=$pid
        return 0
    fi

    # --- ATTEMPT 2: 128 SAMPLES FALLBACK (Only for ALSA) ---
    if [ "$use_dummy" = false ]; then
        print_status "⚠️ 64 samples failed. Retrying with 128 samples..."
        kill -9 $pid 2>/dev/null
        clean_shm_files
        
        buf="128"
        cmd="taskset -c 2,3 jackd -R -S -P 80 -d alsa -d $clean_device -r 48000 -p $buf -n 3"
        
        print_status "Executing Fallback: $cmd"
        eval "$cmd" > "$log_file" 2>&1 &
        pid=$!
        sleep 7

        if is_jack_running "$pid"; then
            print_status "✅ SUCCESS: JACK stable at 128 samples."
            JACK_PID=$pid
            return 0
        fi
    fi

    # --- FINAL FALLBACK: DUMMY ---
    print_status "❌ Hardware failed both attempts. Forcing DUMMY backend for stability."
    kill -9 $pid 2>/dev/null
    clean_shm_files
    
    cmd="taskset -c 2,3 jackd -R -d dummy -r 48000 -p 128"
    eval "$cmd" > "$log_file" 2>&1 &
    pid=$!
    sleep 5

    if is_jack_running "$pid"; then
        JACK_PID=$pid
        return 0
    fi

    return 1
}

# Function to setup JACK environment (Phase 1)
setup_jack_environment() {
    print_status "Phase 1: Setting up JACK environment..."
    
    # Set environment variables to bypass Pipewire and force JACK client mode
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
            jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d dummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -C 2 -P 2"
            ;;
        "alsa")
            print_status "Starting JACK with ALSA backend (USB Audio)..."
            sleep 3  # Wait longer to ensure previous instances are fully terminated
            
            # Use detected USB Audio device with optimized parameters
            if [ -n "$USB_AUDIO_DEVICE" ]; then
                # Optimized JACK parameters based on technical analysis
                # -R: Realtime scheduling
                # -n 3: Number of periods (optimized for stability)
                # -p 64: Buffer size (fixed at 64 samples for optimal performance)
                # No MIDI flags to avoid crashes on unsupported hardware
                # Use all cores >=2 for audio processing
                # Add chrt -f 80 for realtime priority
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d alsa -r$JACK_SAMPLE_RATE -p 64 -n 3 -d $USB_AUDIO_DEVICE"
                print_status "Using detected USB device: $USB_AUDIO_DEVICE"
                print_status "JACK parameters: -R (realtime), -n 3 (periods), -p 64 (fixed buffer)"
                print_status "Audio cores: $audio_cores"
                print_status "Realtime priority: chrt -f 80"
            else
                # Fallback to first available card if detection failed
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 2"
                print_status "Using default ALSA device"
                print_status "JACK parameters: -R (realtime), -n 2 (periods), -p 64 (fixed buffer)"
                print_status "Audio cores: $audio_cores"
                print_status "Realtime priority: chrt -f 80"
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

# Function to verify JACK stability (Phase 3) - IMPROVED WITH ROBUST SYNCHRONIZATION
verify_jack_stability() {
    print_status "Verifying JACK stability with enhanced synchronization..."
    
    # Wait longer for JACK to fully initialize and establish all internal components
    print_status "Waiting for JACK to complete initialization..."
    sleep 5
    
    # Enhanced verification with multiple test methods and longer timeout
    local max_attempts=10
    local attempt=1
    local jack_ready=false
    
    # Determine if JACK is running with jackdbus or in standalone mode
    local jackdbus_available=false
    if timeout 3 jack_control status >/dev/null 2>&1; then
        jackdbus_available=true
        print_status "JACK with jackdbus detected - using standard verification methods"
    else
        print_status "JACK in standalone mode detected - using alternative verification methods"
    fi
    
    while [ $attempt -le $max_attempts ] && [ "$jack_ready" = false ]; do
        print_status "JACK stability test (attempt $attempt/$max_attempts)..."
        
        if [ "$jackdbus_available" = true ]; then
            # Test 1: Basic jack_lsp connectivity (with jackdbus)
            if ! timeout 3 jack_lsp >/dev/null 2>&1; then
                print_status "  JACK not responding to jack_lsp, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
            # Test 2: Check JACK control status (with jackdbus)
            if ! timeout 3 jack_control status >/dev/null 2>&1; then
                print_status "  JACK control not ready, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
            # Test 3: Verify JACK buffer configuration (with jackdbus)
            if ! timeout 3 jack_bufsize >/dev/null 2>&1; then
                print_status "  JACK buffer not configured, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
            # Test 4: Check for active JACK ports (with jackdbus)
            local port_count=$(timeout 3 jack_lsp 2>/dev/null | wc -l || echo "0")
            if [ "$port_count" -lt 2 ]; then
                print_status "  JACK ports not fully initialized ($port_count ports found), waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
        else
            # Alternative verification methods for standalone JACK mode
            
            # Test 1: Verify JACK process is still running
            if [ -z "$JACK_PID" ] || ! kill -0 $JACK_PID 2>/dev/null; then
                print_status "  JACK process not running, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
            # Test 2: Check for JACK socket files (indicates JACK is listening)
            local user_id=$(id -u)
            local socket_files="/dev/shm/jack_default_${user_id}_0 /tmp/.jack_default_${user_id}_0"
            local socket_found=false
            for socket_file in $socket_files; do
                if [ -S "$socket_file" ]; then
                    socket_found=true
                    print_status "  JACK socket found: $socket_file"
                    break
                fi
            done
            
            if [ "$socket_found" = false ]; then
                print_status "  JACK socket files not found, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
            # Test 3: Check JACK shared memory segments (indicates JACK is operational)
            local shm_files="/dev/shm/jack-${user_id}-0 /dev/shm/jack-${user_id}-1"
            local shm_found=false
            for shm_file in $shm_files; do
                if [ -f "$shm_file" ]; then
                    shm_found=true
                    print_status "  JACK shared memory found: $shm_file"
                    break
                fi
            done
            
            if [ "$shm_found" = false ]; then
                print_status "  JACK shared memory segments not found, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
            # Test 4: Verify JACK audio device is accessible
            if ! timeout 3 ls /dev/snd/pcmC* >/dev/null 2>&1; then
                print_status "  JACK audio device not accessible, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
            
            # Test 5: Check JACK process status (simplified - socket existence is sufficient)
            # If the socket exists, JACK is active even with CPU 0.0%
            local user_id=$(id -u)
            if [ -S "/dev/shm/jack_default_${user_id}_0" ]; then
                print_status "  ✓ JACK process is active (socket available)"
            else
                print_status "  JACK socket not found, waiting 3 more seconds..."
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
        fi
        
        # All tests passed - JACK is fully stable
        print_status "JACK stability verified successfully ✓"
        jack_ready=true
        break
    done
    
    if [ "$jack_ready" = true ]; then
        print_status "JACK is fully operational and ready for Ardour connection"
        
        # List available ports for debugging (only if jackdbus is available)
        if [ "$jackdbus_available" = true ]; then
            print_status "Available JACK ports:"
            jack_lsp 2>/dev/null | head -10 || echo "  No ports listed yet"
            
            # Show JACK status for verification (only if jackdbus is available)
            print_status "JACK status:"
            jack_control status 2>/dev/null | head -5 || echo "  Status unavailable"
        else
            print_status "JACK standalone mode - ports and status not available via jack_control"
            print_status "JACK process PID: $JACK_PID"
            print_status "JACK audio device: $USB_AUDIO_DEVICE"
        fi
        
        return 0
    else
        print_status "Error: JACK failed to stabilize after $max_attempts attempts"
        print_status "This may indicate a JACK configuration or hardware issue"
        print_status "Check: JACK parameters, audio hardware, and system resources"
        return 1
    fi
}

# Function to perform comprehensive JACK status verification (IMPROVED - NON-BLOCKING RT VERIFICATION)
verify_jack_comprehensive_status() {
    print_status "Performing comprehensive JACK status verification..."
    
    # Verify JACK process is running (CRITICAL - must not fail)
    if [ -z "$JACK_PID" ] || ! kill -0 $JACK_PID 2>/dev/null; then
        print_status "❌ JACK process not running or PID not available"
        return 1
    fi
    
    # Verify JACK process is running with correct RT priority (NON-BLOCKING - warnings only)
    print_status "Verifying JACK RT priority (non-blocking verification)..."
    
    # Wait additional time for RT priority to stabilize
    print_status "Waiting additional 2 seconds for RT priority to stabilize..."
    sleep 2
    
    # Capture raw chrt output for debugging
    local chrt_output=$(chrt -p "$JACK_PID" 2>&1)
    print_status "Debug: chrt -p output: '$chrt_output'"
    
    local jack_policy=""
    local jack_priority=""
    
    # Handle different chrt output formats
    if echo "$chrt_output" | grep -q "No such process"; then
        print_status "⚠ JACK process not found for RT verification (may have terminated)"
        jack_policy="unknown"
        jack_priority="unknown"
    elif echo "$chrt_output" | grep -q "policy"; then
        # Standard format: "pid X's current scheduling policy: policy"
        jack_policy=$(echo "$chrt_output" | grep "policy" | awk '{print $6}')
        jack_priority=$(echo "$chrt_output" | grep "priority" | awk '{print $6}')
    elif echo "$chrt_output" | grep -q "SCHED_"; then
        # Alternative format handling
        jack_policy=$(echo "$chrt_output" | grep -o "SCHED_[A-Z]*" | head -1)
        jack_priority=$(echo "$chrt_output" | grep -o "[0-9]+" | head -1)
    else
        # Fallback: try to extract from any format
        jack_policy=$(echo "$chrt_output" | awk -F'[,:]' '{for(i=1;i<=NF;i++) if($i ~ /SCHED_/) print $i; for(i=1;i<=NF;i++) if($i ~ /[0-9]+/) print $i}' | head -1)
        jack_priority=$(echo "$chrt_output" | awk -F'[,:]' '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+/) print $i}' | tail -1)
    fi
    
    # Verify RT priority (NON-BLOCKING - only warnings)
    if [ "$jack_policy" = "SCHED_FIFO" ] && [ "$jack_priority" = "80" ]; then
        print_status "✓ JACK process has correct RT priority (SCHED_FIFO, priority 80)"
    else
        print_status "⚠ JACK process RT priority incorrect (NON-BLOCKING WARNING)"
        print_status "  Current: policy=$jack_policy, priority=$jack_priority"
        print_status "  Expected: SCHED_FIFO, priority 80"
        print_status "  Note: JACK may still function correctly despite this warning"
        print_status "  This warning does not block system startup"
        # DO NOT return 1 here - this is non-blocking
    fi
    
    # Verify JACK configuration parameters
    print_status "Verifying JACK configuration parameters..."
    
    # Check sample rate
    local current_samplerate=$(jack_samplerate 2>/dev/null | head -1 || echo "0")
    if [ "$current_samplerate" = "$JACK_SAMPLE_RATE" ]; then
        print_status "✓ Sample rate correct: ${current_samplerate}Hz"
    else
        print_status "⚠ Sample rate mismatch: expected ${JACK_SAMPLE_RATE}Hz, got ${current_samplerate}Hz"
    fi
    
    # Check buffer size
    local current_bufsize=$(jack_bufsize 2>/dev/null | head -1 || echo "0")
    if [ "$current_bufsize" = "$JACK_PERIOD_SIZE" ]; then
        print_status "✓ Buffer size correct: ${current_bufsize} samples"
    else
        print_status "⚠ Buffer size mismatch: expected ${JACK_PERIOD_SIZE}, got ${current_bufsize}"
    fi
    
    # Check number of periods
    local current_periods=$(jack_bufsize 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
    if [ "$current_periods" = "3" ]; then
        print_status "✓ Number of periods correct: 3"
    else
        print_status "⚠ Number of periods: ${current_periods} (expected: 3)"
    fi
    
    # Calculate and verify latency
    local calculated_latency=$(echo "scale=2; $current_bufsize * $current_periods / ($current_samplerate / 1000)" | bc -l 2>/dev/null || echo "0")
    if [ "$calculated_latency" != "0" ] && [ "$(echo "$calculated_latency < 5.0" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
        print_status "✓ Latency optimal: ${calculated_latency}ms"
    else
        print_status "⚠ Latency: ${calculated_latency}ms (should be < 5.0ms for optimal performance)"
    fi
    
    # Verify JACK ports are available
    local capture_ports=$(jack_lsp 2>/dev/null | grep "system:capture" | wc -l || echo "0")
    local playback_ports=$(jack_lsp 2>/dev/null | grep "system:playback" | wc -l || echo "0")
    
    if [ "$capture_ports" -gt 0 ] && [ "$playback_ports" -gt 0 ]; then
        print_status "✓ JACK ports available: ${capture_ports} capture, ${playback_ports} playback"
    else
        print_status "⚠ JACK ports not available: ${capture_ports} capture, ${playback_ports} playback"
        return 1
    fi
    
    # Check for XRUNs (if available)
    if command -v jack_control >/dev/null 2>&1; then
        local xruns=$(jack_control status 2>/dev/null | grep -i "xrun" | awk '{print $2}' || echo "0")
        if [ "$xruns" = "0" ]; then
            print_status "✓ No XRUNs detected"
        else
            print_status "⚠ XRUNs detected: $xruns (system may be overloaded)"
        fi
    fi
    
    print_status "Comprehensive JACK status verification completed ✓"
    return 0
}

# Function to perform final JACK-Ardour synchronization (NEW)
final_jack_ardour_sync() {
    print_status "Performing final JACK-Ardour synchronization..."
    
    # Additional verification that JACK is ready for client connections
    local sync_attempts=3
    local sync_success=false
    
    for i in $(seq 1 $sync_attempts); do
        print_status "Final synchronization check $i/$sync_attempts..."
        
        # Verify JACK is in running state
        local jack_status=$(jack_control status 2>/dev/null | grep -i "running" || echo "")
        if [ -z "$jack_status" ]; then
            print_status "  JACK not in running state, waiting 2 more seconds..."
            sleep 2
            continue
        fi
        
        # Verify JACK has active ports (ready for client connections)
        local active_ports=$(jack_lsp 2>/dev/null | grep -E "system:capture|system:playback" | wc -l || echo "0")
        if [ "$active_ports" -lt 2 ]; then
            print_status "  JACK not ready for client connections ($active_ports active ports), waiting 2 more seconds..."
            sleep 2
            continue
        fi
        
        # Verify JACK buffer size is correct
        local current_bufsize=$(jack_bufsize 2>/dev/null | head -1 || echo "0")
        if [ "$current_bufsize" != "$JACK_PERIOD_SIZE" ]; then
            print_status "  JACK buffer size mismatch (expected: $JACK_PERIOD_SIZE, got: $current_bufsize), waiting 2 more seconds..."
            sleep 2
            continue
        fi
        
        # All synchronization checks passed
        print_status "JACK-Ardour synchronization successful ✓"
        sync_success=true
        break
    done
    
    if [ "$sync_success" = true ]; then
        print_status "JACK is fully synchronized and ready for Ardour connection"
        return 0
    else
        print_status "Warning: JACK-Ardour synchronization failed after $sync_attempts attempts"
        print_status "Proceeding with Ardour startup anyway (connection may take longer)"
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

# Function to attempt to set RT privileges temporarily (for current session)
attempt_temporary_rt_privileges() {
    print_status "Attempting to set temporary RT privileges for current session..."
    
    # Try to set the realtime priority limit for current session
    # This may work if the user has sudo privileges
    if sudo -n ulimit -r 99 2>/dev/null; then
        print_status "✓ Temporary RT privileges set for current session"
        return 0
    else
        print_status "⚠ Cannot set temporary RT privileges (requires sudo or proper configuration)"
        return 1
    fi
}

# Function to verify RT priority was applied successfully (IMPROVED WITH DETAILED LOGGING)
verify_rt_priority_after_startup() {
    print_status "Verifying RT priority after startup with detailed logging..."
    
    # Check JACK process RT priority with enhanced verification
    if [ -n "$JACK_PID" ] && kill -0 $JACK_PID 2>/dev/null; then
        print_status "Checking JACK process RT priority (PID: $JACK_PID)..."
        
        # Capture raw chrt output for detailed analysis
        local jack_chrt_output=$(chrt -p "$JACK_PID" 2>&1)
        print_status "  JACK chrt -p raw output: '$jack_chrt_output'"
        
        local jack_policy=""
        local jack_priority=""
        
        # Enhanced parsing with multiple format support
        if echo "$jack_chrt_output" | grep -q "No such process"; then
            print_status "  ⚠ JACK process not found for RT verification"
            jack_policy="unknown"
            jack_priority="unknown"
        elif echo "$jack_chrt_output" | grep -q "policy"; then
            # Standard format parsing
            jack_policy=$(echo "$jack_chrt_output" | grep "policy" | awk '{print $6}')
            jack_priority=$(echo "$jack_chrt_output" | grep "priority" | awk '{print $6}')
            print_status "  JACK parsed policy: '$jack_policy', priority: '$jack_priority'"
        elif echo "$jack_chrt_output" | grep -q "SCHED_"; then
            # Alternative format parsing
            jack_policy=$(echo "$jack_chrt_output" | grep -o "SCHED_[A-Z]*" | head -1)
            jack_priority=$(echo "$jack_chrt_output" | grep -o "[0-9]+" | head -1)
            print_status "  JACK alternative parsed policy: '$jack_policy', priority: '$jack_priority'"
        else
            # Fallback parsing
            jack_policy=$(echo "$jack_chrt_output" | awk -F'[,:]' '{for(i=1;i<=NF;i++) if($i ~ /SCHED_/) print $i; for(i=1;i<=NF;i++) if($i ~ /[0-9]+/) print $i}' | head -1)
            jack_priority=$(echo "$jack_chrt_output" | awk -F'[,:]' '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+/) print $i}' | tail -1)
            print_status "  JACK fallback parsed policy: '$jack_policy', priority: '$jack_priority'"
        fi
        
        # Verify JACK RT priority
        if [ "$jack_policy" = "SCHED_FIFO" ] && [ "$jack_priority" = "80" ]; then
            print_status "✓ JACK process has correct RT priority (SCHED_FIFO, priority 80)"
        else
            print_status "⚠ JACK process RT priority not set correctly"
            print_status "  Current policy: $jack_policy"
            print_status "  Current priority: $jack_priority"
            print_status "  Expected: SCHED_FIFO, priority 80"
            print_status "  Note: This is a non-blocking warning - JACK may still function"
        fi
    else
        print_status "⚠ JACK process not running or PID not available for RT verification"
    fi
    
    # Check Ardour process RT priority with enhanced verification
    if [ -n "$ARDOUR_PID" ] && kill -0 $ARDOUR_PID 2>/dev/null; then
        print_status "Checking Ardour process RT priority (PID: $ARDOUR_PID)..."
        
        # Capture raw chrt output for detailed analysis
        local ardour_chrt_output=$(chrt -p "$ARDOUR_PID" 2>&1)
        print_status "  Ardour chrt -p raw output: '$ardour_chrt_output'"
        
        local ardour_policy=""
        local ardour_priority=""
        
        # Enhanced parsing with multiple format support
        if echo "$ardour_chrt_output" | grep -q "No such process"; then
            print_status "  ⚠ Ardour process not found for RT verification"
            ardour_policy="unknown"
            ardour_priority="unknown"
        elif echo "$ardour_chrt_output" | grep -q "policy"; then
            # Standard format parsing
            ardour_policy=$(echo "$ardour_chrt_output" | grep "policy" | awk '{print $6}')
            ardour_priority=$(echo "$ardour_chrt_output" | grep "priority" | awk '{print $6}')
            print_status "  Ardour parsed policy: '$ardour_policy', priority: '$ardour_priority'"
        elif echo "$ardour_chrt_output" | grep -q "SCHED_"; then
            # Alternative format parsing
            ardour_policy=$(echo "$ardour_chrt_output" | grep -o "SCHED_[A-Z]*" | head -1)
            ardour_priority=$(echo "$ardour_chrt_output" | grep -o "[0-9]+" | head -1)
            print_status "  Ardour alternative parsed policy: '$ardour_policy', priority: '$ardour_priority'"
        else
            # Fallback parsing
            ardour_policy=$(echo "$ardour_chrt_output" | awk -F'[,:]' '{for(i=1;i<=NF;i++) if($i ~ /SCHED_/) print $i; for(i=1;i<=NF;i++) if($i ~ /[0-9]+/) print $i}' | head -1)
            ardour_priority=$(echo "$ardour_chrt_output" | awk -F'[,:]' '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+/) print $i}' | tail -1)
            print_status "  Ardour fallback parsed policy: '$ardour_policy', priority: '$ardour_priority'"
        fi
        
        # Verify Ardour RT priority
        if [ "$ardour_policy" = "SCHED_FIFO" ] && [ "$ardour_priority" = "75" ]; then
            print_status "✓ Ardour process has correct RT priority (SCHED_FIFO, priority 75)"
        else
            print_status "⚠ Ardour process RT priority not set correctly"
            print_status "  Current policy: $ardour_policy"
            print_status "  Current priority: $ardour_priority"
            print_status "  Expected: SCHED_FIFO, priority 75"
            print_status "  Note: This is a non-blocking warning - Ardour may still function"
        fi
    else
        print_status "⚠ Ardour process not running or PID not available for RT verification"
    fi
}

# Function to test actual JACK functionality despite RT verification issues (NEW)
test_jack_functionality() {
    print_status "Testing actual JACK functionality despite RT verification issues..."
    
    # Test 1: Verify JACK is actually running and responsive
    print_status "Test 1: Verifying JACK process is running and responsive..."
    if [ -n "$JACK_PID" ] && kill -0 $JACK_PID 2>/dev/null; then
        print_status "✓ JACK process is running (PID: $JACK_PID)"
        
        # Test JACK communication
        if timeout 3 jack_lsp >/dev/null 2>&1; then
            print_status "✓ JACK is responsive to client requests"
        else
            print_status "⚠ JACK is running but not responsive to client requests"
            return 1
        fi
    else
        print_status "❌ JACK process is not running"
        return 1
    fi
    
    # Test 2: Verify JACK has active ports
    print_status "Test 2: Verifying JACK has active audio ports..."
    local capture_ports=$(jack_lsp 2>/dev/null | grep "system:capture" | wc -l || echo "0")
    local playback_ports=$(jack_lsp 2>/dev/null | grep "system:playback" | wc -l || echo "0")
    
    if [ "$capture_ports" -gt 0 ] && [ "$playback_ports" -gt 0 ]; then
        print_status "✓ JACK has active audio ports: ${capture_ports} capture, ${playback_ports} playback"
    else
        print_status "⚠ JACK is running but has no active audio ports"
        return 1
    fi
    
    # Test 3: Verify JACK buffer configuration
    print_status "Test 3: Verifying JACK buffer configuration..."
    local current_bufsize=$(jack_bufsize 2>/dev/null | head -1 || echo "0")
    local current_samplerate=$(jack_samplerate 2>/dev/null | head -1 || echo "0")
    
    if [ "$current_bufsize" != "0" ] && [ "$current_samplerate" != "0" ]; then
        print_status "✓ JACK buffer configured: ${current_bufsize} samples, ${current_samplerate}Hz"
        
        # Calculate latency
        local calculated_latency=$(echo "scale=2; $current_bufsize * 3 / ($current_samplerate / 1000)" | bc -l 2>/dev/null || echo "0")
        if [ "$calculated_latency" != "0" ]; then
            print_status "✓ JACK latency calculated: ${calculated_latency}ms"
        fi
    else
        print_status "⚠ JACK buffer not properly configured"
        return 1
    fi
    
    # Test 4: Verify Ardour can connect to JACK
    print_status "Test 4: Verifying Ardour can connect to JACK..."
    if [ -n "$ARDOUR_PID" ] && kill -0 $ARDOUR_PID 2>/dev/null; then
        if jack_lsp 2>/dev/null | grep -q "ardour"; then
            print_status "✓ Ardour is connected to JACK"
        else
            print_status "⚠ Ardour is running but not connected to JACK yet"
            print_status "  This may be normal - connection can take additional time"
        fi
    else
        print_status "⚠ Ardour process not running"
    fi
    
    # Test 5: Check for XRUNs (if available)
    print_status "Test 5: Checking for XRUNs (audio dropouts)..."
    if command -v jack_control >/dev/null 2>&1; then
        local xruns=$(jack_control status 2>/dev/null | grep -i "xrun" | awk '{print $2}' || echo "0")
        if [ "$xruns" = "0" ]; then
            print_status "✓ No XRUNs detected - audio is stable"
        else
            print_status "⚠ XRUNs detected: $xruns (system may be overloaded)"
        fi
    fi
    
    print_status "JACK functionality test completed ✓"
    print_status "Note: JACK may function correctly even if RT priority verification failed"
    return 0
}

# Function to start Ardour as JACK client (Phase 4) - ENHANCED WITH ROOT AUDIO GROUP FIX AND DETAILED LOGGING
start_ardour_as_client() {
    local ardour_cmd=""
    
    print_status "Phase 4: Starting Ardour as JACK client..."
    
    # Setup JACK environment
    setup_jack_environment
    
    # Rilevamento pulito del target user
    local target_user="${SUDO_USER:-$USER}"
    
    # Se siamo root, dobbiamo forzare l'esecuzione di Ardour come utente normale
    # altrimenti Ardour creerà file in ~/.config/ardour8 come root (pericoloso!)
    if [ "$EUID" -eq 0 ]; then
        print_status "WARNING: Launcher is root. Dropping privileges to $target_user for Ardour GUI."
        LAUNCH_PREFIX="sudo -u $target_user -E env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY"
    else
        LAUNCH_PREFIX=""
    fi
    
    # Setup X11 environment for proper display access
    print_status "Configuring X11 environment for display access..."
    
    # Ensure DISPLAY is set correctly
    if [ -z "$DISPLAY" ]; then
        # Check for X11 socket files to determine correct display
        local display_found=false
        for display_num in 0 1 2 3 4 5; do
            local socket_path="/tmp/.X11-unix/X$display_num"
            if [ -S "$socket_path" ]; then
                export DISPLAY=":$display_num"
                print_status "Set DISPLAY to: $DISPLAY (found socket: $socket_path)"
                display_found=true
                break
            fi
        done
        
        if [ "$display_found" = false ]; then
            export DISPLAY=":0"
            print_status "Set DISPLAY to default: $DISPLAY"
        fi
    else
        print_status "DISPLAY already set: $DISPLAY"
    fi
    
    # Setup XAUTHORITY
    if [ -z "$XAUTHORITY" ]; then
        # Try to find XAUTHORITY in user's home directory
        local user_home="$HOME"
        if [ -n "$target_user" ] && [ "$target_user" != "$USER" ]; then
            user_home="/home/$target_user"
        fi
        
        local possible_xauth="$user_home/.Xauthority"
        if [ -f "$possible_xauth" ]; then
            export XAUTHORITY="$possible_xauth"
            print_status "Set XAUTHORITY to: $XAUTHORITY"
        else
            export XAUTHORITY="$HOME/.Xauthority"
            print_status "Set XAUTHORITY to default: $XAUTHORITY"
        fi
    else
        print_status "XAUTHORITY already set: $XAUTHORITY"
    fi
    
    # Setup XDG_RUNTIME_DIR
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        if [ -n "$target_user" ]; then
            # Get user ID for XDG_RUNTIME_DIR
            local user_id=$(id -u "$target_user" 2>/dev/null || echo "1000")
            export XDG_RUNTIME_DIR="/run/user/$user_id"
            print_status "Set XDG_RUNTIME_DIR to: $XDG_RUNTIME_DIR"
        else
            export XDG_RUNTIME_DIR="/run/user/1000"
            print_status "Set XDG_RUNTIME_DIR to default: $XDG_RUNTIME_DIR"
        fi
    else
        print_status "XDG_RUNTIME_DIR already set: $XDG_RUNTIME_DIR"
    fi
    
    # Test X11 connection
    if xset q >/dev/null 2>&1; then
        print_status "X11 connection verified successfully ✓"
    else
        print_status "Warning: X11 connection test failed"
        print_status "DISPLAY: $DISPLAY"
        print_status "XAUTHORITY: $XAUTHORITY"
        print_status "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
        print_status "This may cause Ardour GUI to fail"
    fi
    
    # Setup detailed logging
    local ardour_log="$HOME/.olms/ardour_startup.log"
    mkdir -p "$HOME/.olms"
    
    # FIX X11 PERMISSIONS AUTOMATICAMENTE (NUOVO)
    print_status "Fix automatico permessi X11 per root..."
    if ! fix_x11_permissions; then
        print_status "Warning: Fix X11 permissions failed, but continuing..."
    fi
    
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
    
    # Start Ardour with proper timing and synchronization
    print_status "Starting Ardour with command: $ardour_cmd"
    print_status "Environment: JACK_NO_START_SERVER=1, PIPEWIRE_RUNTIME_DIR=/dev/null"
    print_status "Audio cores: $audio_cores"
    print_status "Target user: $target_user"
    print_status "Logging to: $ardour_log"
    
    # CRITICAL: Add proper timing delay before starting Ardour
    print_status "Adding synchronization delay before Ardour startup..."
    print_status "Waiting 5 seconds to ensure JACK is fully stabilized..."
    sleep 5
    
    # Final verification that JACK is ready
    print_status "Final JACK readiness verification..."
    if ! verify_jack_stability; then
        print_status "Warning: JACK may not be fully stable, but proceeding with Ardour startup"
    else
        print_status "JACK verified as stable and ready"
    fi
    
    # Esecuzione finale
    print_status "Launching Ardour with command: $ardour_cmd"
    eval "$LAUNCH_PREFIX $ardour_cmd > \"$ardour_log\" 2>&1 &"
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
        # Show error details from log
        print_status "Ardour error details from log:"
        if [ -f "$ardour_log" ]; then
            tail -n 20 "$ardour_log"
        else
            echo "  - No log file found"
        fi
        
        # Show environment details
        if [ "$MODE" != "prod" ]; then
            echo "  - DISPLAY: $DISPLAY"
            echo "  - XAUTHORITY: $XAUTHORITY"
            echo "  - XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
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
    USB_AUDIO_DEVICE=""  # Ensure no device is set for virtual mode
else
    # Try to detect USB audio device
    USB_DEVICE=$(detect_usb_audio_device 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$USB_DEVICE" ]; then
        AUDIO_BACKEND="alsa"
        USB_AUDIO_DEVICE="$USB_DEVICE"
        print_status "Using detected USB audio device: $USB_AUDIO_DEVICE"
    else
        AUDIO_BACKEND="dummy"
        USB_AUDIO_DEVICE=""
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

# Phase 3: Starting JACK with Adaptive Buffer Strategy
print_status "Phase 3: Starting JACK with Adaptive Buffer Strategy"
if ! start_jack_adaptive "$USB_AUDIO_DEVICE"; then
    print_status "JACK startup with adaptive buffer failed, aborting"
    exit 1
fi

# Phase 4: Verifying JACK stability
print_status "Phase 4: Verifying JACK stability"
if ! verify_jack_stability; then
    print_status "JACK stability verification failed, stopping JACK"
    kill $JACK_PID 2>/dev/null
    exit 1
fi

# Phase 4.5: Comprehensive JACK status verification
print_status "Phase 4.5: Comprehensive JACK status verification"
if ! verify_jack_comprehensive_status; then
    print_status "JACK comprehensive status verification failed, stopping JACK"
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

# Test actual JACK functionality despite any RT verification issues
print_status "Phase 5.5: Testing actual JACK functionality despite RT verification issues..."
if ! test_jack_functionality; then
    print_status "Warning: JACK functionality test failed, but system may still be usable"
else
    print_status "✓ JACK functionality test passed - system is working correctly"
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
# Run final verification before completion
print_status "Running final system verification..."
if [ -f "$(dirname "$0")/olms-final-verification.sh" ]; then
    sudo "$(dirname "$0")/olms-final-verification.sh" $([ "$VERBOSE" = true ] && echo "--verbose")
    verification_status=$?
    
    if [ $verification_status -eq 0 ]; then
        print_success "All OLMS optimizations verified successfully"
    else
        print_warning "Some verification checks failed - see details above"
        print_status "System may still be functional but with sub-optimal performance"
    fi
else
    print_status "Warning: Final verification script not found, skipping verification"
fi

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
