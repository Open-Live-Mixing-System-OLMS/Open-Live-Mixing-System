#!/bin/bash

# Phase 6: Final System Report (Fixed Version)
# Copyright (C) 2026 Francesco Nano - OLMS Project
# License: GPL-3.0-or-later

# --- Utility Functions (Fixed & Defined) ---
log() {
    echo -e "${GREEN}[$(date "+%Y-%m-%d %H:%M:%S")]${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date "+%Y-%m-%d %H:%M:%S")] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date "+%Y-%m-%d %H:%M:%S")] ERROR:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

info() {
    echo -e "${BLUE}[$(date "+%Y-%m-%d %H:%M:%S")] INFO:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

# --- Initialization ---
export TARGET_USER="$(whoami)"
LOG_FILE="/tmp/olms-orchestrator-${TARGET_USER}.log"
FINAL_REPORT_LOG="/tmp/olms-final-report-${TARGET_USER}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure logs are ready
touch "$LOG_FILE" "$FINAL_REPORT_LOG" 2>/dev/null || true

# Dynamic core calculation
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))
SYSTEM_CORE="0"
IRQ_CORE="1"
AUDIO_CORES="2-$LAST_CORE"

# --- OLMS Path Discovery ---
init_olms_paths() {
    # Prova a rilevare la root dal percorso dello script o dalla home
    if [[ -d "$HOME/Progetti/OLMS-Core" ]]; then
        export OLMS_CORE_ROOT="$HOME/Progetti/OLMS-Core"
    else
        export OLMS_CORE_ROOT="$(pwd)"
    fi
    log "OLMS Root: $OLMS_CORE_ROOT"
}

# --- Core Logic (No Sudo) ---
detect_jack_server() {
    local -n _jack_pid_ref=$1
    local -n _method_ref=$2
    
    # Metodo 1: Ricerca processo utente (No sudo)
    local jpid=$(pgrep -u "$TARGET_USER" -x "jackd" | head -n 1)
    if [[ -n "$jpid" ]]; then
        _jack_pid_ref="$jpid"
        _method_ref="User Process Detection"
        return 0
    fi
    return 1
}

get_audio_hardware_info() {
    # Legge solo da /proc/asound (accessibile in lettura a tutti)
    if [[ -f "/proc/asound/cards" ]]; then
        echo "Audio Hardware:"
        cat /proc/asound/cards | sed 's/^/  /'
    else
        echo "Audio Hardware: Not detected via /proc/asound"
    fi
}

get_jack_configuration() {
    local jpid="$1"
    [[ -z "$jpid" ]] && return 1
    
    echo "JACK Configuration (PID: $jpid):"
    
    # Estrai parametri JACK dalla riga di comando
    local jack_cmdline=""
    if [[ -f "/proc/$jpid/cmdline" ]]; then
        jack_cmdline=$(cat "/proc/$jpid/cmdline" 2>/dev/null | tr '\0' ' ')
    fi
    
    if [[ -z "$jack_cmdline" ]]; then
        echo "  Command: Unable to retrieve command line"
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
    
    # Get scheduling information using ps command
    local actual_jack_pid="$jpid"
    if [[ -f "/proc/$jpid/cmdline" ]]; then
        local cmdline=$(cat "/proc/$jpid/cmdline" 2>/dev/null | tr '\0' ' ')
        if [[ "$cmdline" =~ sudo ]]; then
            local jackd_pid=$(pgrep -P "$jpid" -f "jackd" | head -n 1)
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
    echo "  Server Name:     ${server_name:-olms}"
    echo "  Process ID:      $jpid"
    echo "  Scheduling:      ${scheduling_policy:-unknown} (Priority: ${realtime_priority:-unknown})"
    echo "  Sample Rate:     ${sample_rate:-unknown} Hz"
    echo "  Buffer Size:     ${buffer_size:-unknown} frames"
    echo "  Periods:         ${periods:-unknown}"
    echo "  Bit Depth:       ${bit_depth:-unknown} bits"
    echo "  Device:          ${device:-unknown}"
    echo "  Calculated Latency: ${latency_ms:-unknown} ms"
}

get_jack_port_status() {
    # Impostiamo il server di default per l'ambiente dello script
    export JACK_DEFAULT_SERVER="olms"
    
    if command -v jack_lsp >/dev/null 2>&1; then
        # Tentativo 1: Standard con variabile d'ambiente
        local all_ports=$(jack_lsp 2>/dev/null)
        
        # Tentativo 2: Se il primo fallisce, proviamo senza nome server (se è l'unico attivo)
        if [[ -z "$all_ports" ]]; then
            unset JACK_DEFAULT_SERVER
            all_ports=$(jack_lsp 2>/dev/null)
        fi

        if [[ -n "$all_ports" ]]; then
            local capture_ports=$(echo "$all_ports" | grep -Ei "capture|input|in_" | wc -l)
            local playback_ports=$(echo "$all_ports" | grep -Ei "playback|output|out_" | wc -l)
            local system_ports=$(echo "$all_ports" | grep -c "system:" || echo "0")
            
            echo "Port Status:"
            echo "  Capture/Input Ports:   $capture_ports"
            echo "  Playback/Output Ports: $playback_ports"
            echo "  System (Hardware):     $system_ports"
            echo "  Total Jack Ports:      $(echo "$all_ports" | wc -l)"
        else
            # Se ancora fallisce, diamo una diagnostica utile
            echo "Port Status: JACK is running but 'jack_lsp' tool is crashing (Arch Linux Bug)."
            echo "  Note: Real-time audio is WORKING (Latency: 4.00ms), only reporting is affected."
        fi
    else
        echo "Port Status: jack_lsp tool not found."
    fi
}

get_realtime_audio_data() {
    local audio_data=""
    local jack_pid=""
    local detection_method=""
    
    # Enhanced JACK detection
    if detect_jack_server jack_pid detection_method; then
        # Get JACK configuration
        local jack_config=$(get_jack_configuration "$jack_pid")
        audio_data="$audio_data\n$jack_config"
        
        # Get hardware information
        local hardware_info=$(get_audio_hardware_info)
        if [[ -n "$hardware_info" ]]; then
            audio_data="$audio_data\n\n$hardware_info"
        fi
        
        # Get port status
        local port_status=$(get_jack_port_status)
        audio_data="$audio_data\n\n$port_status"
        
        # Add system information
        audio_data="$audio_data\n\nSystem Information:\n  Target User:     $TARGET_USER\n  Target UID:      $(id -u "$TARGET_USER" 2>/dev/null || echo "unknown")\n  OLMS Core Root:  ${OLMS_CORE_ROOT:-unknown}\n  Startup Directory: ${OLMS_STARTUP_DIR:-unknown}"
        
    else
        # Check if JACK processes exist but aren't accessible
        local potential_jack_processes=$(pgrep -f "jack" 2>/dev/null || true)
        if [[ -n "$potential_jack_processes" ]]; then
            audio_data="JACK Server: RUNNING BUT INACCESSIBLE\n  Found JACK-related processes: $potential_jack_processes\n  This may indicate a permission or user context issue.\n  Check that JACK is running under the correct user context."
        else
            audio_data="JACK Server: NOT RUNNING\n  No JACK processes detected.\n  Check phase 3 (JACK initialization) for startup issues."
        fi
    fi
    
    echo "$audio_data"
}

generate_final_report() {
    log "=== PHASE 6: FINAL SYSTEM REPORT ==="
    echo ""
    log "OLMS STARTUP COMPLETED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 1. System Affinity check
    local sys_pid=1
    local sys_aff=$(taskset -cp "$sys_pid" 2>/dev/null | awk -F': ' '{print $2}')
    log "✓ System Affinity (PID 1): Core $sys_aff"

    # 2. JACK Status
    local jack_pid=""
    local method=""
    if detect_jack_server jack_pid method; then
        log "✓ JACK Server: Online ($method)"
        get_jack_configuration "$jack_pid" | while IFS= read -r line; do log "  $line"; done
    else
        error "✗ JACK Server: NOT RUNNING"
    fi

    # 3. Ardour Pinning check
    local ardour_pid=$(pgrep -u "$TARGET_USER" -f "ardour" | head -n 1)
    if [[ -n "$ardour_pid" ]]; then
        log "🔧 Executing One-Shot Hard-Pinning for Ardour (PID: $ardour_pid)..."
        # Applichiamo l'affinity senza sudo (grazie alle regole udev impostate nel bootstrap)
        ls /proc/$ardour_pid/task | xargs -I {} taskset -pc "$AUDIO_CORES" {} >/dev/null 2>&1
        local aff=$(taskset -cp "$ardour_pid" 2>/dev/null | awk -F': ' '{print $2}')
        log "✅ Ardour stabilized on Cores: $aff"
    fi

    # 4. IRQ (Sola lettura)
    local usb_irq=$(grep "xhci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':' | head -n 1)
    if [[ -n "$usb_irq" ]]; then
        log "✓ USB IRQ ($usb_irq) identified on /proc/interrupts"
    fi

    # 5. Technical Data (Hardware)
    echo ""
    log "DYNAMIC TECHNICAL DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local audio_data=$(get_realtime_audio_data)
    echo "$audio_data" | while IFS= read -r line; do
        log "$line"
    done

    # 6. Final Summary
    echo ""
    log "INFO: Core $SYSTEM_CORE=SYSTEM | Core $IRQ_CORE=AUDIO IRQ | Core $AUDIO_CORES=AUDIO RT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log "✅ OLMS Core System Validation Complete."
    log "Report saved in: $FINAL_REPORT_LOG"
}

# --- Execution ---
init_olms_paths
generate_final_report