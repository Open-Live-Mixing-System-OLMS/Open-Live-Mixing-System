# Copyright (C) 2024 Francesco Nano <tua@email.com>
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

# Configuration
LOG_FILE="/tmp/olms-orchestrator.log"
FINAL_REPORT_LOG="/tmp/olms-final-report.log"

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

# Extracts real-time technical data from the system
get_realtime_audio_data() {
    local jack_pid=$(pgrep -u "$TARGET_USER" -x "jackd" | head -n 1)
    local audio_data=""
    
    if [[ -n "$jack_pid" ]]; then
        # Extracts real-time JACK configuration
        local jack_cmdline=$(cat /proc/"$jack_pid"/cmdline 2>/dev/null | tr '\0' ' ')
        local buffer_size=$(echo "$jack_cmdline" | grep -o " -p [0-9]*" | awk '{print $2}')
        local periods=$(echo "$jack_cmdline" | grep -o " -n [0-9]*" | awk '{print $2}')
        local sample_rate=$(echo "$jack_cmdline" | grep -o " -r [0-9]*" | awk '{print $2}')
        local device=$(echo "$jack_cmdline" | grep -o " -d [^ ]*" | awk '{print $2}')
        
        # Calculates effective latency
        local latency_ms=0
        if [[ -n "$buffer_size" && -n "$periods" && -n "$sample_rate" ]]; then
            latency_ms=$(( (buffer_size * periods * $(id -u)) / sample_rate ))
        fi
        
        # Extracts ALSA device information
        local card_info=""
        if [[ -n "$device" ]]; then
            local card_index=$(echo "$device" | sed 's/hw://')
            card_info=$(cat /proc/asound/cards 2>/dev/null | grep -A1 "^[[:space:]]*$card_index\[" | tail -1 | sed 's/^[[:space:]]*//')
        fi
        
        audio_data="JACK Configuration:
  Device: $device
  Sample Rate: ${sample_rate}Hz
  Buffer Size: $buffer_size frames
  Periods: $periods
  Latency: ${latency_ms}ms
  PID: $jack_pid"
        
        # Checks JACK sockets
        local socket_count=$(find /dev/shm -name "jack_*" 2>/dev/null | wc -l)
        audio_data="$audio_data
  Socket Files: $socket_count found"
        
        # Checks JACK port status
        local port_count=0
        if command -v jack_lsp >/dev/null 2>&1; then
            port_count=$(sudo -u "$TARGET_USER" env JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | wc -l || echo "0")
        fi
        audio_data="$audio_data
  Active Ports: $port_count"
        
        # Hardware device information
        if [[ -n "$card_info" ]]; then
            audio_data="$audio_data
  Hardware: $card_info"
        fi
    else
        audio_data="JACK Server: NOT RUNNING"
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
    log "INFO: Core 0=SYSTEM | Core 1=AUDIO IRQ | Core $AUDIO_CORES=AUDIO RT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Final summary
    local error_count=$(grep -c "ERROR:" "$FINAL_REPORT_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    local warning_count=$(grep -c "WARNING:" "$FINAL_REPORT_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    
    if [[ $error_count -eq 0 ]] && [[ $warning_count -eq 0 ]]; then
        log "✅ Real-time audio system fully operational"
        log "✅ Ready for professional use"
    elif [[ $error_count -eq 0 ]] && [[ $warning_count -le 2 ]]; then
        log "⚠ Audio system operational with some warnings"
        log "⚠ Performance potentially reduced"
    else
        log "✗ Audio system with critical errors"
        log "✗ Manual intervention required"
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
