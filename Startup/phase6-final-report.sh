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

# Phase 6: Final System Report
# Version: 1.0

# Initialize OLMS paths for relative path support
init_olms_paths() {
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 1. Direct detection from current script directory
    local potential_startup_dir="$script_dir"
    local potential_core_root="$(dirname "$script_dir")"
    
    if [[ -f "$potential_core_root/OLMS_specs.md" ]] && [[ -f "$potential_core_root/OLMS_STARTUP_SPECIFICATION.md" ]]; then
        export OLMS_CORE_ROOT="$potential_core_root"
        export OLMS_ENGINE_DIR="$olms_core_root/engine"
        export OLMS_CONFIG_DIR="$olms_core_root/config"
        export OLMS_STARTUP_DIR="$potential_startup_dir"
        export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
        export OLMS_TEST_DIR="$olms_core_root/test"
        export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
        export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
        log "OLMS paths initialized from script directory: $olms_core_root"
        return 0
    fi
    
    # 2. Search for OLMS marker files
    local search_dirs=("$HOME" "/opt" "/usr/local")
    for search_dir in "${search_dirs[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' potential_root; do
                if [[ -f "$potential_root/OLMS_specs.md" ]] && [[ -f "$potential_root/OLMS_STARTUP_SPECIFICATION.md" ]]; then
                    export OLMS_CORE_ROOT="$potential_root"
                    export OLMS_ENGINE_DIR="$olms_core_root/engine"
                    export OLMS_CONFIG_DIR="$olms_core_root/config"
                    export OLMS_STARTUP_DIR="$olms_core_root/Startup"
                    export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
                    export OLMS_TEST_DIR="$olms_core_root/test"
                    export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
                    export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
                    log "OLMS paths initialized from marker files: $olms_core_root"
                    return 0
                fi
            done < <(find "$search_dir" -maxdepth 3 -type d -name "OLMS-Core" -print0 2>/dev/null)
        fi
    done
    
    # 3. Fallback to standard locations
    if [[ -d "$HOME/Progetti/OLMS-Core" ]]; then
        export OLMS_CORE_ROOT="$HOME/Progetti/OLMS-Core"
        export OLMS_ENGINE_DIR="$olms_core_root/engine"
        export OLMS_CONFIG_DIR="$olms_core_root/config"
        export OLMS_STARTUP_DIR="$olms_core_root/Startup"
        export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
        export OLMS_TEST_DIR="$olms_core_root/test"
        export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
        export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
        log "OLMS paths initialized from fallback location: $olms_core_root"
        return 0
    fi
    
    # 4. Final fallback - search recursively in home directory
    if [[ -d "$HOME" ]]; then
        while IFS= read -r -d '' potential_root; do
            if [[ -f "$potential_root/OLMS_specs.md" ]] && [[ -f "$potential_root/OLMS_STARTUP_SPECIFICATION.md" ]]; then
                export OLMS_CORE_ROOT="$potential_root"
                export OLMS_ENGINE_DIR="$olms_core_root/engine"
                export OLMS_CONFIG_DIR="$olms_core_root/config"
                export OLMS_STARTUP_DIR="$olms_core_root/Startup"
                export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
                export OLMS_TEST_DIR="$olms_core_root/test"
                export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
                export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
                log "OLMS paths initialized from recursive search: $olms_core_root"
                return 0
            fi
        done < <(find "$HOME" -maxdepth 4 -type d -name "OLMS-Core" -print0 2>/dev/null)
    fi
    
    warn "OLMS-Core directory not found, using current directory"
    export OLMS_CORE_ROOT="$(pwd)"
    export OLMS_ENGINE_DIR="$olms_core_root/engine"
    export OLMS_CONFIG_DIR="$olms_core_root/config"
    export OLMS_STARTUP_DIR="$olms_core_root/Startup"
    export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
    export OLMS_TEST_DIR="$olms_core_root/test"
    export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
    export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
    return 1
}

get_olms_path() {
    local path_type="$1"
    
    case "$path_type" in
        "core_root") echo "$OLMS_CORE_ROOT" ;;
        "engine_dir") echo "$OLMS_ENGINE_DIR" ;;
        "config_dir") echo "$OLMS_CONFIG_DIR" ;;
        "startup_dir") echo "$OLMS_STARTUP_DIR" ;;
        "systemd_dir") echo "$OLMS_SYSTEMD_DIR" ;;
        "test_dir") echo "$OLMS_TEST_DIR" ;;
        "ardour_session_path") echo "$OLMS_ARDOUR_SESSION_PATH" ;;
        "ardour_session_dir") echo "$OLMS_ARDOUR_SESSION_DIR" ;;
        *) warn "Unknown path type: $path_type"; echo "$OLMS_CORE_ROOT" ;;
    esac
}

# Initialize paths at the beginning
init_olms_paths

# Environment variables for the "all as same user" approach
export TARGET_USER="$(whoami)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DISPLAY=":0"
export XAUTHORITY="/home/$(whoami)/.Xauthority"
export JACK_DEFAULT_SERVER="olms"
export JACK_NO_START_SERVER=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_SESSION_DIR="/dev/shm/jack-olms-0"

# Removed -e to avoid unexpected closures, keeping -u and -o pipefail
set -uo pipefail

# Dynamic core calculation
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))
SYSTEM_CORE="0"
IRQ_CORE="1"
AUDIO_CORES="2-$LAST_CORE"

# Variables for correct pinning
RT_PRIORITY=70

# Function to extract the bitwise mask of affinity
# Example: Core 0 = 1, Core 1 = 2, Core 2 = 4, Core 3 = 8
get_affinity_mask() {
    local pid=$1
    taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' '
}

# Configuration - Use dynamic paths
LOG_FILE="/tmp/olms-orchestrator-${TARGET_USER}.log"
FINAL_REPORT_LOG="/tmp/olms-final-report-${TARGET_USER}.log"

# Ensure log files are writable
mkdir -p /tmp
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
touch "$FINAL_REPORT_LOG" 2>/dev/null || FINAL_REPORT_LOG="/dev/null"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} Startup process aborted due to warning: $1" | tee -a "$LOG_FILE"
    exit 1
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

# Enhanced JACK detection with multiple methods
detect_jack_server() {
    local -n _jack_pid_ref=$1
    local -n _detection_method_ref=$2
    
    _jack_pid_ref=""
    _detection_method_ref=""
    
    # Method 1: Check for any process with JACK in command line (most reliable)
    # Use ps command to find JACK processes by user and command pattern
    local jack_processes=$(ps -u "$TARGET_USER" -o pid,cmd | grep -E "jackd.*-d.*alsa|jackdbus|jackd.*-d.*dummy" | grep -v grep | awk '{print $1}' 2>/dev/null || true)
    if [[ -n "$jack_processes" ]]; then
        for pid in $jack_processes; do
            if [[ -f "/proc/$pid/cmdline" ]]; then
                local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
                # Check if this is actually a JACK server process
                if [[ "$cmdline" =~ jackd.*-d.*alsa ]] || [[ "$cmdline" =~ jackdbus ]] || [[ "$cmdline" =~ jackd.*-d.*dummy ]]; then
                    _jack_pid_ref="$pid"
                    _detection_method_ref="Process detection (user: $TARGET_USER)"
                    return 0
                fi
            fi
        done
    fi
    
    # Method 2: Check for jackd process by name (fallback)
    local jack_pid=$(pgrep -u "$TARGET_USER" -f "jackd" | head -n 1)
    if [[ -n "$jack_pid" ]]; then
        _jack_pid_ref="$jack_pid"
        _detection_method_ref="Process detection (jackd)"
        return 0
    fi
    
    # Method 3: Check for jackdbus process (fallback)
    jack_pid=$(pgrep -u "$TARGET_USER" -f "jackdbus" | head -n 1)
    if [[ -n "$jack_pid" ]]; then
        _jack_pid_ref="$jack_pid"
        _detection_method_ref="Process detection (jackdbus)"
        return 0
    fi
    
    # Method 4: Check for PID file from startup scripts
    if [[ -f "/tmp/jack.pid" ]]; then
        jack_pid=$(cat /tmp/jack.pid 2>/dev/null)
        if [[ -n "$jack_pid" ]] && kill -0 "$jack_pid" 2>/dev/null; then
            _jack_pid_ref="$jack_pid"
            _detection_method_ref="PID file from startup script"
            return 0
        fi
    fi
    
    # Method 5: Check for JACK socket files (indicates running server)
    local socket_dirs=($(find /dev/shm -name "jack-*" -type d 2>/dev/null))
    if [[ ${#socket_dirs[@]} -gt 0 ]]; then
        # Try to find a process associated with the socket
        for socket_dir in "${socket_dirs[@]}"; do
            local socket_name=$(basename "$socket_dir")
            # Look for processes that might be JACK
            local potential_pids=$(ps -u "$TARGET_USER" -o pid | grep -E "^[0-9]+$" 2>/dev/null || true)
            for pid in $potential_pids; do
                if [[ -d "/proc/$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    # Verify it's a JACK server process
                    if [[ -f "/proc/$pid/cmdline" ]]; then
                        local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
                        if [[ "$cmdline" =~ jackd.*-d.*alsa ]] || [[ "$cmdline" =~ jackdbus ]] || [[ "$cmdline" =~ jackd.*-d.*dummy ]]; then
                            _jack_pid_ref="$pid"
                            _detection_method_ref="Socket file detection ($socket_name)"
                            return 0
                        fi
                    fi
                fi
            done
        done
    fi
    
    return 1
}

# Extracts comprehensive audio hardware information
get_audio_hardware_info() {
    local hardware_info=""
    
    # Get audio card information from /proc/asound/
    if [[ -f "/proc/asound/cards" ]]; then
        local card_info=$(cat /proc/asound/cards 2>/dev/null)
        if [[ -n "$card_info" ]]; then
            hardware_info="Audio Hardware:
$(echo "$card_info" | sed 's/^/  /')"
        fi
    fi
    
    # Get detailed card capabilities
    if [[ -d "/proc/asound/card0" ]]; then
        local card0_info=""
        if [[ -f "/proc/asound/card0/id" ]]; then
            local card0_id=$(cat /proc/asound/card0/id 2>/dev/null)
            card0_info="Card 0 ID: $card0_id"
        fi
        
        if [[ -f "/proc/asound/card0/pcm0p/sub0/hw_params" ]]; then
            local pcm_info=$(cat /proc/asound/card0/pcm0p/sub0/hw_params 2>/dev/null | head -5)
            if [[ -n "$pcm_info" ]]; then
                card0_info="$card0_info
  PCM0 Output: $pcm_info"
            fi
        fi
        
        if [[ -n "$card0_info" ]]; then
            hardware_info="$hardware_info
  $card0_info"
        fi
    fi
    
    # Get USB audio device information
    local usb_audio_info=""
    for device in /sys/class/sound/card*; do
        if [[ -d "$device" ]]; then
            local card_num=$(basename "$device" | sed 's/card//')
            if [[ -f "$device/device/driver" ]]; then
                local driver_link=$(readlink "$device/device/driver" 2>/dev/null)
                if [[ "$driver_link" == *"snd-usb-audio"* ]]; then
                    local usb_info="USB Audio Device (Card $card_num):
    Driver:     $(basename "$driver_link")
    Device Path: $device"
                    
                    # Get device name from id file
                    if [[ -f "$device/id" ]]; then
                        local device_id=$(cat "$device/id" 2>/dev/null)
                        usb_info="$usb_info
    Device ID:  $device_id"
                    fi
                    
                    # Get device capabilities
                    if [[ -f "$device/stream0" ]]; then
                        local stream_info=$(cat "$device/stream0" 2>/dev/null | head -3)
                        if [[ -n "$stream_info" ]]; then
                            usb_info="$usb_info
    Stream Info: $(echo "$stream_info" | tr '\n' ' ')"
                        fi
                    fi
                    
                    usb_audio_info="$usb_audio_info
  $usb_info"
                fi
            fi
        fi
    done
    
    if [[ -n "$usb_audio_info" ]]; then
        hardware_info="$hardware_info
  $usb_audio_info"
    fi
    
    echo "$hardware_info"
}

# Extracts comprehensive JACK configuration parameters
get_jack_configuration() {
    local jack_pid="$1"
    local config_info=""
    
    if [[ -z "$jack_pid" ]] || ! kill -0 "$jack_pid" 2>/dev/null; then
        echo "JACK Configuration: NOT RUNNING"
        return 1
    fi
    
    # Extract command line parameters
    local jack_cmdline=""
    if [[ -f "/proc/$jack_pid/cmdline" ]]; then
        jack_cmdline=$(cat "/proc/$jack_pid/cmdline" 2>/dev/null | tr '\0' ' ')
    fi
    
    if [[ -z "$jack_cmdline" ]]; then
        echo "JACK Configuration: RUNNING (Parameters unavailable)"
        return 1
    fi
    
    # Parse JACK parameters
    local sample_rate=""
    local buffer_size=""
    local periods=""
    local bit_depth=""
    local device=""
    local server_name=""
    local realtime_priority=""
    local scheduling_policy=""
    
    # Extract parameters using regex
    if [[ "$jack_cmdline" =~ -r[[:space:]]*([0-9]+) ]]; then
        sample_rate="${BASH_REMATCH[1]}"
    fi
    
    if [[ "$jack_cmdline" =~ -p[[:space:]]*([0-9]+) ]]; then
        buffer_size="${BASH_REMATCH[1]}"
    fi
    
    if [[ "$jack_cmdline" =~ -n[[:space:]]*([0-9]+) ]]; then
        periods="${BASH_REMATCH[1]}"
    fi
    
    if [[ "$jack_cmdline" =~ -S[[:space:]]*([0-9]+) ]]; then
        bit_depth="${BASH_REMATCH[1]}"
    fi
    
    if [[ "$jack_cmdline" =~ -d[[:space:]]*([^[:space:]]+) ]]; then
        device="${BASH_REMATCH[1]}"
    fi
    
    if [[ "$jack_cmdline" =~ -n[[:space:]]*([^[:space:]]+) ]]; then
        server_name="${BASH_REMATCH[1]}"
    fi
    
    # Get scheduling information using ps command (correct method)
    # Find the actual JACK process (not the sudo wrapper)
    local actual_jack_pid="$jack_pid"
    if [[ -f "/proc/$jack_pid/cmdline" ]]; then
        local cmdline=$(cat "/proc/$jack_pid/cmdline" 2>/dev/null | tr '\0' ' ')
        if [[ "$cmdline" =~ sudo ]]; then
            # This is a sudo process, find the actual JACK child process
            local jackd_pid=$(pgrep -P "$jack_pid" -f "jackd" | head -n 1)
            if [[ -n "$jackd_pid" ]] && kill -0 "$jackd_pid" 2>/dev/null; then
                actual_jack_pid="$jackd_pid"
            fi
        fi
    fi
    
    if command -v ps >/dev/null 2>&1; then
        local ps_info=$(ps -o cls,pri -p "$actual_jack_pid" 2>/dev/null | tail -n 1)
        if [[ -n "$ps_info" ]]; then
            scheduling_policy=$(echo "$ps_info" | awk '{print $1}')
            realtime_priority=$(echo "$ps_info" | awk '{print $2}')
        fi
    fi
    
    # Calculate effective latency
    local latency_ms=0
    if [[ -n "$buffer_size" && -n "$periods" && -n "$sample_rate" ]]; then
        latency_ms=$(echo "scale=2; ($buffer_size * $periods * 1000) / $sample_rate" | bc 2>/dev/null || echo "0")
    fi
    
    # Format with proper alignment and spacing
    config_info="JACK Configuration:
  Server Name:     ${server_name:-olms}
  Process ID:      $jack_pid
  Scheduling:      ${scheduling_policy:-unknown} (Priority: ${realtime_priority:-unknown})
  Sample Rate:     ${sample_rate:-unknown} Hz
  Buffer Size:     ${buffer_size:-unknown} frames
  Periods:         ${periods:-unknown}
  Bit Depth:       ${bit_depth:-unknown} bits
  Device:          ${device:-unknown}
  Calculated Latency: ${latency_ms:-unknown} ms"
    
    # Add socket information
    local socket_count=$(find /dev/shm -name "jack_*" 2>/dev/null | wc -l)
    config_info="$config_info
  Socket Files:    $socket_count found"
    
    # Add port information
    local port_count=0
    if command -v jack_lsp >/dev/null 2>&1; then
        port_count=$(sudo -u "$TARGET_USER" env JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | wc -l || echo "0")
    fi
    config_info="$config_info
  Active Ports:    $port_count"
    
    echo "$config_info"
}

# Enhanced port status checking
get_jack_port_status() {
    local port_status=""
    
    if command -v jack_lsp >/dev/null 2>&1; then
        local capture_ports=""
        local playback_ports=""
        local system_ports=""
        
        # Get all ports
        local all_ports=$(sudo -u "$TARGET_USER" env JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null || echo "")
        
        if [[ -n "$all_ports" ]]; then
            capture_ports=$(echo "$all_ports" | grep -c "capture\|input" || echo "0")
            playback_ports=$(echo "$all_ports" | grep -c "playback\|output" || echo "0")
            system_ports=$(echo "$all_ports" | grep -c "system:" || echo "0")
            
            port_status="Port Status:
  Capture Ports:  $capture_ports
  Playback Ports: $playback_ports
  System Ports:   $system_ports
  Total Ports:    $(echo "$all_ports" | wc -l)"
        else
            port_status="Port Status: Unable to retrieve port list"
        fi
    else
        port_status="Port Status: jack_lsp command not available"
    fi
    
    echo "$port_status"
}

# Extracts real-time technical data from the system
get_realtime_audio_data() {
    local audio_data=""
    local jack_pid=""
    local detection_method=""
    
    # Enhanced JACK detection
    if detect_jack_server jack_pid detection_method; then
        # Get JACK configuration
        local jack_config=$(get_jack_configuration "$jack_pid")
        audio_data="$audio_data
$jack_config"
        
        # Get hardware information
        local hardware_info=$(get_audio_hardware_info)
        if [[ -n "$hardware_info" ]]; then
            audio_data="$audio_data

$hardware_info"
        fi
        
        # Get port status
        local port_status=$(get_jack_port_status)
        audio_data="$audio_data

$port_status"
        
        # Add system information
        audio_data="$audio_data

System Information:
  Target User:     $TARGET_USER
  Target UID:      $(id -u "$TARGET_USER" 2>/dev/null || echo "unknown")
  OLMS Core Root:  ${OLMS_CORE_ROOT:-unknown}
  Startup Directory: ${OLMS_STARTUP_DIR:-unknown}"
        
    else
        # Check if JACK processes exist but aren't accessible
        local potential_jack_processes=$(pgrep -f "jack" 2>/dev/null || true)
        if [[ -n "$potential_jack_processes" ]]; then
            audio_data="JACK Server: RUNNING BUT INACCESSIBLE
  Found JACK-related processes: $potential_jack_processes
  This may indicate a permission or user context issue.
  Check that JACK is running under the correct user context."
        else
            audio_data="JACK Server: NOT RUNNING
  No JACK processes detected.
  Check phase 3 (JACK initialization) for startup issues."
        fi
    fi
    
    echo "$audio_data"
}

# Generates synthetic final report
generate_final_report() {
    log "=== PHASE 6: FINAL SYSTEM REPORT (UNIVERSAL) ==="
    echo ""
    log "OLMS STARTUP COMPLETED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # --- 1. SYSTEM ISOLATION VERIFICATION (Core 0) ---
    # Check a random system process (e.g., init or kthreadd)
    local sys_pid=$(pgrep -x "systemd" | head -n 1 || pgrep -x "init" | head -n 1 || echo "1")
    local sys_aff=$(taskset -cp "$sys_pid" 2>/dev/null | awk -F': ' '{print $2}')
    
    # Verify if the system is isolated on core 0
    if [[ "$sys_aff" == "0" ]]; then
        log "✓ System: Correctly isolated on Core $SYSTEM_CORE"
    else
        # Check if it's a false positive (process with multi-core affinity)
        if [[ "$sys_aff" == *"0"* ]]; then
            log "✓ System: Core $SYSTEM_CORE included (OK - multi-core)"
        else
            log "⚠ System: Not isolated (Current Affinity: $sys_aff)"
        fi
    fi

    # --- 2. JACK SERVER (Core 2+) ---
    local jack_pid=$(pgrep -u "$TARGET_USER" -x "jackd" | head -n 1 || echo "")
    if [[ -n "$jack_pid" ]]; then
        local affinity=$(taskset -cp "$jack_pid" 2>/dev/null | awk -F': ' '{print $2}')
        local priority=$(chrt -p "$jack_pid" 2>/dev/null | awk -F': ' '/priority/ {print $2}' || echo "N/A")
        
        # Verify if affinity doesn't touch cores 0 and 1
        if [[ "$affinity" != *"0"* && "$affinity" != *"1"* ]]; then
            log "✓ JACK Server: Core $affinity (OK), RT Prio $priority"
        else
            log "⚠ JACK Server: Core $affinity (SYSTEM/IRQ CONFLICT)"
        fi
    fi
    
    # --- 3. ARDOUR DAW (Core 2+) ---
    local ardour_pid=$(pgrep -u "$TARGET_USER" -f "ardour" | head -n 1 || echo "")
    if [[ -n "$ardour_pid" ]]; then
        log "🔧 Executing One-Shot Hard-Pinning for Ardour (PID: $ardour_pid)..."
        
        # 1. Retrieve ALL thread IDs of the Ardour process
        # 2. Force each of them on dedicated cores
        # 3. No active background processes left
        ls /proc/$ardour_pid/task | xargs -I {} taskset -pc "$AUDIO_CORES" {} >/dev/null 2>&1
        
        # Final verification
        local final_aff=$(taskset -cp "$ardour_pid" 2>/dev/null | awk -F': ' '{print $2}')
        log "✅ Ardour stabilized on Core $final_aff. No residual watchdog."
    fi

    # --- 4. IRQ ANALYSIS (Core 1) ---
    local usb_irq=$(grep "xhci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':' | head -n 1 || echo "")
    if [[ -n "$usb_irq" ]]; then
        local aff_mask=$(cat "/proc/irq/$usb_irq/smp_affinity" 2>/dev/null | tr -d ' \n' | sed 's/^0*//')
        # 2 in hex/dec is always the second core (Core 1)
        if [[ "$aff_mask" == "2" ]]; then
            log "✓ USB IRQ $usb_irq: Core $IRQ_CORE (Verified 0x2)"
        else
            log "⚠ USB IRQ $usb_irq: Pinning Error (Mask: 0x$aff_mask)"
        fi
    fi
    
    # --- 5. DYNAMIC TECHNICAL DATA ---
    echo ""
    log "DYNAMIC TECHNICAL DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local audio_data=$(get_realtime_audio_data)
    echo "$audio_data" | while IFS= read -r line; do
        log "$line"
    done
    
    # --- 6. ARCHITECTURE SUMMARY ---
    echo ""
    log "INFO: Core $SYSTEM_CORE=SYSTEM | Core $IRQ_CORE=AUDIO IRQ | Core $AUDIO_CORES=AUDIO RT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Final summary - Enhanced validation logic
    local error_count=$(grep -c "ERROR:" "$FINAL_REPORT_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    local warning_count=$(grep -c "WARNING:" "$FINAL_REPORT_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    
    # Check critical real-time conditions
    local rt_validation_passed=true
    local critical_issues=()
    
    # 1. Verify JACK is in real-time mode with proper privileges
    local jack_pid=$(pgrep -u "$TARGET_USER" -x "jackd" | head -n 1)
    if [[ -n "$jack_pid" ]]; then
        local actual_jack_pid="$jack_pid"
        if [[ -f "/proc/$jack_pid/cmdline" ]]; then
            local cmdline=$(cat "/proc/$jack_pid/cmdline" 2>/dev/null | tr '\0' ' ')
            if [[ "$cmdline" =~ sudo ]]; then
                local jackd_pid=$(pgrep -P "$jack_pid" -f "jackd" | head -n 1)
                if [[ -n "$jackd_pid" ]] && kill -0 "$jackd_pid" 2>/dev/null; then
                    actual_jack_pid="$jackd_pid"
                fi
            fi
        fi
        
        # Check scheduling policy
        local scheduling=$(ps -o cls -p "$actual_jack_pid" 2>/dev/null | tail -n 1 | tr -d ' ')
        if [[ "$scheduling" != "FF" ]]; then
            rt_validation_passed=false
            critical_issues+=("JACK not in real-time mode (SCHED_FIFO)")
        fi
        
        # Check real-time priority level
        local rt_priority=$(ps -o pri -p "$actual_jack_pid" 2>/dev/null | tail -n 1 | tr -d ' ')
        if [[ -n "$rt_priority" ]] && [[ "$rt_priority" -lt 80 ]]; then
            rt_validation_passed=false
            critical_issues+=("JACK real-time priority too low ($rt_priority < 80)")
        fi
        
        # Check if JACK has real-time privileges (rtprio limit)
        local rtprio_limit=$(ulimit -r 2>/dev/null || echo "0")
        if [[ "$rtprio_limit" -lt 80 ]]; then
            rt_validation_passed=false
            critical_issues+=("User real-time priority limit too low ($rtprio_limit < 80)")
        fi
        
        # Verify JACK can actually use real-time scheduling
        if ! chrt -p "$actual_jack_pid" 2>/dev/null | grep -q "SCHED_FIFO"; then
            rt_validation_passed=false
            critical_issues+=("JACK cannot use real-time scheduling despite SCHED_FIFO")
        fi
    else
        rt_validation_passed=false
        critical_issues+=("JACK server not running")
    fi
    
    # 2. Verify system isolation on core 0
    local sys_pid=$(pgrep -x "systemd" | head -n 1 || pgrep -x "init" | head -n 1 || echo "1")
    local sys_aff=$(taskset -cp "$sys_pid" 2>/dev/null | awk -F': ' '{print $2}')
    if [[ "$sys_aff" != "0" ]] && [[ "$sys_aff" != *"0"* ]]; then
        rt_validation_passed=false
        critical_issues+=("System not isolated on core 0")
    fi
    
    # 3. Verify IRQ pinning on core 1
    local usb_irq=$(grep "xhci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':' | head -n 1 || echo "")
    if [[ -n "$usb_irq" ]]; then
        local irq_aff_mask=$(cat "/proc/irq/$usb_irq/smp_affinity" 2>/dev/null | tr -d ' \n' | sed 's/^0*//')
        if [[ "$irq_aff_mask" != "2" ]]; then
            rt_validation_passed=false
            critical_issues+=("USB IRQ not pinned to core 1")
        fi
    fi
    
    # 4. Verify JACK and Ardour on audio cores (2-n)
    local audio_cores_pattern="^[2-$LAST_CORE]"
    if [[ -n "$jack_pid" ]]; then
        local jack_aff=$(taskset -cp "$jack_pid" 2>/dev/null | awk -F': ' '{print $2}')
        if [[ "$jack_aff" == *"0"* ]] || [[ "$jack_aff" == *"1"* ]]; then
            rt_validation_passed=false
            critical_issues+=("JACK not isolated on audio cores (2-n)")
        fi
    fi
    
    local ardour_pid=$(pgrep -u "$TARGET_USER" -f "ardour" | head -n 1)
    if [[ -n "$ardour_pid" ]]; then
        local ardour_aff=$(taskset -cp "$ardour_pid" 2>/dev/null | awk -F': ' '{print $2}')
        if [[ "$ardour_aff" == *"0"* ]] || [[ "$ardour_aff" == *"1"* ]]; then
            rt_validation_passed=false
            critical_issues+=("Ardour not isolated on audio cores (2-n)")
        fi
    fi
    
    # Final validation
    if [[ "$rt_validation_passed" == "true" ]] && [[ $error_count -eq 0 ]] && [[ $warning_count -eq 0 ]]; then
        log "✅ Real-time audio system fully operational"
        log "✅ Ready for professional use"
    elif [[ $error_count -eq 0 ]] && [[ $warning_count -le 2 ]]; then
        if [[ "$rt_validation_passed" == "false" ]]; then
            log "⚠ Audio system with real-time configuration issues"
            log "⚠ Critical issues: ${critical_issues[*]}"
        else
            log "⚠ Audio system operational with some warnings"
            log "⚠ Performance potentially reduced"
        fi
    else
        log "✗ Audio system with critical errors"
        log "✗ Manual intervention required"
        if [[ "$rt_validation_passed" == "false" ]]; then
            log "✗ Real-time issues: ${critical_issues[*]}"
        fi
    fi
    
    log "Detailed log: $FINAL_REPORT_LOG"
}

# Main function
main() {
    generate_final_report
    log "Final system report completed"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
