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
# OLMS LATENCY ANALYZER - v1.9 (CLEAN OUTPUT)
# Fix: Logic identical to v1.8, only improved log readability.
# Feature: Column alignment and differential calculation in final report.

set -e

# --- CONFIGURATION ---
export TARGET_USER="francesco_ssh"
export BIN_JACK_DELAY="/usr/bin/jack_delay"
export J_ENV="PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1"
export J_CMD="sudo -u $TARGET_USER env $J_ENV"

# Current settings (for theoretical calculation only)
BUFFER=64
RATE=48000
PERIODS=3

# --- COLORS AND STYLES ---
GREEN='\033[1;32m' # Bold Green
YELLOW='\033[1;33m' # Bold Yellow
RED='\033[1;31m'   # Bold Red
CYAN='\033[1;36m'  # Bold Cyan
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Robust analysis function (Clean output)
analyze_result() {
    local file=$1
    local phase=$2
    
    if grep -q "frames" "$file"; then
        # Takes the last valid line
        local last_line=$(grep "frames" "$file" | tail -n 1)
        
        # OUTPUT CLEANUP: Removes leading spaces and tabs for alignment
        # Example Raw: "  384.597 frames     8.012 ms" -> Clean: "384.597 frames | 8.012 ms"
        local clean_val=$(echo "$last_line" | sed 's/^[ \t]*//' | sed 's/[ \t]*frames[ \t]*/ frames | /')
        
        echo -e "   > Result $phase: ${GREEN}${clean_val}${NC}"
        return 0
    else
        log_warn "Automatic parsing failed. Raw output:"
        tail -n 3 "$file"
        return 1
    fi
}

run_software_test() {
    log_step "PHASE 1: Software Routing Verification (Ardour)"
    
    local ardour_in="ardour:Audio 1/audio_in 1"
    local ardour_out="ardour:Master/audio_out 1"
    local logfile="/tmp/lat_soft.log"

    # Verify ports
    if ! $J_CMD jack_lsp | grep -Fq "$ardour_in"; then
        log_warn "Track '$ardour_in' not found. Is Ardour open?"
        return
    fi

    echo "   Routing: $ardour_in -> $ardour_out"
    echo "   Status:  Signal injection (Meters MUST move)..."

    $J_CMD "$BIN_JACK_DELAY" -O "$ardour_in" -I "$ardour_out" > "$logfile" 2>&1 &
    local pid=$!
    
    sleep 4
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    
    analyze_result "$logfile" "Software"
}

run_hardware_test() {
    log_step "PHASE 2: HARDWARE TEST (Physical Loopback)"
    log_warn "Required configuration: Loopback Cable (OUT 1 -> IN 1)"
    log_warn "IMPORTANT: Mute Ardour Master or disable Input Monitoring!"
    echo -n "   Press ENTER to measure..."
    read
    
    local logfile="/tmp/lat_hard.log"
    
    # Dynamic JACK port detection (like Session Adaptation)
    log_info "Detecting available JACK ports..."
    local available_ports
    available_ports=$($J_CMD jack_lsp 2>/dev/null | grep "^system:" | sort)
    
    if [ -z "$available_ports" ]; then
        log_err "No JACK ports found for server 'olms'"
        return 1
    fi
    
    # Extract available capture and playback ports
    local capture_ports=$(echo "$available_ports" | grep "capture" | head -10)
    local playback_ports=$(echo "$available_ports" | grep "playback" | head -10)
    
    # Count available ports
    local capture_count=$(echo "$capture_ports" | wc -l)
    local playback_count=$(echo "$playback_ports" | wc -l)
    
    log_info "Available ports: $capture_count capture, $playback_count playback"
    
    # Verify there are enough ports for the test
    if [ "$capture_count" -lt 1 ] || [ "$playback_count" -lt 1 ]; then
        log_err "Insufficient ports for hardware test"
        return 1
    fi
    
    # Extract the first available capture and playback ports
    local capture_port=$(echo "$capture_ports" | head -1)
    local playback_port=$(echo "$playback_ports" | head -1)
    
    log_info "Hardware test on ports: $capture_port -> $playback_port"
    
    # Execution on dynamic physical ports
    $J_CMD "$BIN_JACK_DELAY" -I "$capture_port" -O "$playback_port" > "$logfile" 2>&1 &
    local pid=$!
    
    echo "   Sampling in progress (5s)..."
    sleep 5
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    
    if analyze_result "$logfile" "Hardware"; then
        # Data extraction for final report
        local last_line=$(grep "frames" "$logfile" | tail -n 1)
        # Extract only milliseconds (e.g., 8.012)
        local ms_measured=$(echo "$last_line" | grep -oE "[0-9]+\.[0-9]+ ms" | awk '{print $1}')
        
        # Theoretical Calculation
        local theoretical_ms=$(echo "scale=3; ($BUFFER * $PERIODS + $BUFFER) / $RATE * 1000" | bc)
        # Overhead Calculation (Pure Hardware)
        local overhead_ms=$(echo "scale=3; $ms_measured - $theoretical_ms" | bc)

        echo ""
        echo "======================================================="
        echo -e "              ${CYAN}OLMS FINAL REPORT${NC}"
        echo "======================================================="
        printf "   %-25s : %s ms\n" "Theoretical Latency (Buffer)" "$theoretical_ms"
        printf "   %-25s : %s ms\n" "Overhead (USB+Conv)" "$overhead_ms"
        echo "   ---------------------------------------"
        printf "   %-25s : ${GREEN}%s ms${NC} (TOTAL)\n" "REAL LATENCY MEASURED" "$ms_measured"
        echo "   ---------------------------------------"
        printf "   %-25s : %s\n" "Input Port" "$capture_port"
        printf "   %-25s : %s\n" "Output Port" "$playback_port"
        echo "======================================================="
    else
        log_err "Hardware Test failed. Signal not received."
        log_warn "Available ports: $available_ports"
    fi
}

# --- MAIN ---
clear
echo "==============================================="
echo "   OLMS LATENCY ANALYZER - v1.9 (CLEAN)"
echo "==============================================="

if ! pgrep -f "jackd.*olms" > /dev/null; then
    log_err "JACK server non attivo."
    exit 1
fi

run_software_test
run_hardware_test

echo -e "\nAnalisi completata."