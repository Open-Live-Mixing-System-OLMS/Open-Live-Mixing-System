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

# Phase 2: Hardware Configuration & IRQ Pinning
# Version: 2.0

set -euo pipefail

# Configuration
OLMS_HOME="$HOME/.olms"
mkdir -p "$OLMS_HOME"
LOG_FILE="$OLMS_HOME/olms-orchestrator.log"

# Try to detect if we're running from within OLMS-Core
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$script_dir" == */Startup2 ]]; then
    # We're running from within OLMS-Core, use the parent directory
    olms_core_root="$(dirname "$script_dir")"
    export OLMS_CORE_ROOT="$olms_core_root"
    export OLMS_ENGINE_DIR="$olms_core_root/engine"
    export OLMS_CONFIG_DIR="$olms_core_root/config"
    export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
    export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
    export OLMS_TEST_DIR="$olms_core_root/test"
    export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
    export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
fi

# Dynamic core detection
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))

# Dynamic core assignment
SYSTEM_CORE=0
IRQ_CORE=1
AUDIO_CORES="2-$LAST_CORE"  # Dynamic range from 2 to n

# CPU mask for IRQ (core 1)
CPU_MASK_CORE_1="0x2"  # Hex mask for core 1

# Environment variables for "same user" approach
export TARGET_USER="$(whoami)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} Startup process aborted due to warning: $1" | tee -a "$LOG_FILE"
    exit 1
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Audio hardware detection - DYNAMIC VERSION WITH USB CONTROL
detect_audio_hardware() {
    log "Audio hardware detection (dynamic approach)..."
    local audio_irqs=()
    local usb_devices=()
    
    # Specific patterns to avoid false positives
    local patterns="snd|audio|sound|hda|xhci_hcd|ehci_hcd"
    
    # Collect all results before processing
    local irq_results=$(grep -iE "$patterns" /proc/interrupts | awk -F: '{print $1}' | tr -d ' ')
    local usb_results=$(grep -iE "xhci_hcd|ehci_hcd" /proc/interrupts | wc -l)
    
    # Check if there are too many USB devices
    if [[ $usb_results -gt 3 ]]; then
        warn "Too many USB devices detected on the same bus ($usb_results devices)"
        warn "This can cause blocking during IRQ pinning"
        warn "SUGGESTION: Unplug external HD or other non-essential USB devices"
        warn "EXECUTE: sudo /home/$(whoami)/Progetti/OLMS-Core/Startup2/olms-orchestrator.sh after unplugging devices"
        exit 1
    fi
    
    # Process results safely
    while read -r irq; do
        if [[ -n "$irq" ]]; then
            audio_irqs+=("$irq")
            log "IRQ $irq identified for optimization."
        fi
    done <<< "$irq_results"
    
    printf '%s\n' "${audio_irqs[@]}" | sort -nu
}

# Function to find USB IRQ dynamically (solution for IRQ 122 problem)
find_usb_irq_dynamic() {
    log "Dynamic USB IRQ search for xhci_hcd..."
    
    # Search for IRQ associated with xhci_hcd (USB controller)
    # Format /proc/interrupts: "122:      40313    4390635          0          0 PCI-MSI-0000:00:14.0    0-edge      xhci_hcd"
    local usb_irq=$(grep "xhci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':')
    
    if [[ -n "$usb_irq" ]]; then
        log "Dynamic USB IRQ found: $usb_irq (driver: xhci_hcd)"
        echo "$usb_irq"
    else
        # Fallback: search for other USB patterns
        local usb_irq_alt=$(grep -E "usb.*hcd|ehci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':' | head -1)
        if [[ -n "$usb_irq_alt" ]]; then
            log "Alternative USB IRQ found: $usb_irq_alt"
            echo "$usb_irq_alt"
        else
            log "No dynamic USB IRQ found"
            echo ""
        fi
    fi
}

# Configure IRQ affinity - ENHANCED VERSION with IRQ 126 Fix
configure_irq_affinity() {
    local audio_irqs=("$@")
    [[ ${#audio_irqs[@]} -eq 0 ]] && { log "No audio IRQ detected from standard patterns"; }
    
    log "Configuring IRQ affinity for detected IRQs..."
    
    # Combine detected IRQs with dynamic USB IRQ to process them all together
    local usb_irq=$(find_usb_irq_dynamic)
    if [[ -n "$usb_irq" ]]; then
        audio_irqs+=("$usb_irq")
    fi

    # Remove duplicates
    local unique_irqs=($(printf "%s\n" "${audio_irqs[@]}" | sort -u))

    for irq in "${unique_irqs[@]}"; do
        local affinity_file="/proc/irq/${irq}/smp_affinity"
        
        if [[ ! -f "$affinity_file" ]]; then 
            log "IRQ $irq not present in /proc/irq, skipping..."
            continue 
        fi

        log "Attempting to pin IRQ $irq on core $IRQ_CORE..."
        
        local success=false
        # Attempt 1: Hexadecimal mask (0x2 for core 1)
        if { echo "0x2" > "$affinity_file"; } 2>/dev/null; then
        log "IRQ $irq: OK (Core $IRQ_CORE) - Hexadecimal mask"
        success=true
    # Attempt 2: Numeric core ID
    elif { echo "$IRQ_CORE" > "/proc/irq/$irq/smp_affinity_list"; } 2>/dev/null; then
        log "IRQ $irq: OK (Core $IRQ_CORE) - Numeric core ID"
        success=true
        fi
        
        if [[ "$success" == "false" ]]; then
            log "WARNING: IRQ $irq not relocatable (permission denied or fixed hardware)"
        fi
    done
}

# Verify IRQ configuration
verify_irq_configuration() {
    log "Verifying IRQ configuration..."
    
    local verified_irqs=0
    local total_irqs=0
    
    # Read all IRQs and verify audio ones
    while IFS= read -r line; do
        local irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        local description=$(echo "$line" | cut -d' ' -f2-)
        
        if [[ "$irq" =~ ^[0-9]+$ ]] && [[ $irq -ge 0 ]] && [[ $irq -le 4095 ]]; then
            total_irqs=$((total_irqs + 1))
            
            # Verify if it's an audio IRQ
            if echo "$description" | grep -iqE "snd|audio|sound|hda|usb.*audio|audio.*usb"; then
                local affinity_file="/proc/irq/${irq}/smp_affinity"
                local current_affinity=$(cat "$affinity_file" 2>/dev/null || echo "")
                
                if [[ -n "$current_affinity" ]]; then
                    log "IRQ $irq: $description -> affinity: $current_affinity"
                    verified_irqs=$((verified_irqs + 1))
                else
                    warn "IRQ $irq: unable to read affinity"
                fi
            fi
        fi
    done < /proc/interrupts
    
    log "Verification completed: $verified_irqs audio IRQs out of $total_irqs total"
    
    if [[ $verified_irqs -gt 0 ]]; then
        log "IRQ pinning: $verified_irqs audio IRQs configured"
    else
        # Don't block startup if audio is disabled
        local enable_status=$(cat /sys/module/snd_hda_intel/parameters/enable 2>/dev/null || echo "")
        if [[ "$enable_status" =~ ^N, ]]; then
            log "No audio IRQ configured (audio disabled via kernel parameter - normal)"
        else
            warn "No audio IRQ configured"
        fi
    fi
}

# Hardware reset and final detection
final_hardware_check() {
    log "Final hardware check..."
    
    # Verify audio devices
    if [[ -d "/dev/snd" ]]; then
        log "Audio devices detected:"
        ls -la /dev/snd/ | while read -r line; do
            log "  $line"
        done
        
        # Verify permissions
        local device_users=$(fuser /dev/snd/* 2>/dev/null || true)
        if [[ -n "$device_users" ]]; then
            warn "Audio devices in use by PID: $device_users"
        else
            log "Audio devices free"
        fi
    else
        warn "No audio device detected in /dev/snd"
    fi
    
    # Verify ALSA
    if command -v aplay >/dev/null 2>&1; then
        local alsa_cards=$(aplay -l 2>/dev/null | head -10 || true)
        if [[ -n "$alsa_cards" ]]; then
            log "ALSA audio cards:"
            echo "$alsa_cards" | while read -r card; do
                log "  $card"
            done
        fi
    fi
    
    # Verify USB audio
    if lsusb >/dev/null 2>&1; then
        local usb_audio=$(lsusb 2>/dev/null | grep -i audio || true)
        if [[ -n "$usb_audio" ]]; then
            log "USB audio devices:"
            echo "$usb_audio" | while read -r device; do
                log "  $device"
            done
        fi
    fi
}

# Function to prepare the system
prepare_system() {
    if systemctl is-active --quiet irqbalance; then
        log "Permanently disabling irqbalance to unlock IRQs..."
        systemctl stop irqbalance
        systemctl mask irqbalance
    fi
}

# Function to detect available volume controls on an audio card
detect_volume_controls() {
    local card_index=$1
    local controls=()
    
    log "Detecting available volume controls for card $card_index..."
    
    # Get all available controls for the card
    local all_controls=$(amixer -c "$card_index" controls 2>/dev/null | grep -E "numid=[0-9]+" || true)
    
    if [[ -z "$all_controls" ]]; then
        log "No controls found for card $card_index"
        return 1
    fi
    
    # Filter controls that are likely volume controls
    while IFS= read -r control; do
        local numid=$(echo "$control" | grep -o "numid=[0-9]*" | cut -d'=' -f2)
        local control_name=$(amixer -c "$card_index" cget numid="$numid" 2>/dev/null | grep -o "name='[^']*'" | head -1 | tr -d "'" || true)
        
        if [[ -n "$control_name" ]]; then
            # Common volume controls
            if echo "$control_name" | grep -iqE "volume|pcm|master|capture|playback|headphone|speaker"; then
                controls+=("$numid:$control_name")
                log "Volume control found: numid=$numid, name='$control_name'"
            fi
        fi
    done <<< "$all_controls"
    
    if [[ ${#controls[@]} -eq 0 ]]; then
        log "No specific volume controls found, trying generic names..."
        
        # Try with generic volume control names
        local generic_controls=("PCM" "Master" "Capture" "Playback" "Headphone" "Speaker")
        for control_name in "${generic_controls[@]}"; do
            if amixer -c "$card_index" sget "$control_name" >/dev/null 2>&1; then
                controls+=("generic:$control_name")
                log "Generic volume control found: $control_name"
            fi
        done
    fi
    
    if [[ ${#controls[@]} -eq 0 ]]; then
        log "No volume controls found on card $card_index"
        return 1
    fi
    
    # Return found controls
    printf '%s\n' "${controls[@]}"
    return 0
}

# Function to get the maximum range of a volume control
get_volume_range() {
    local card_index=$1
    local numid=$2
    local max_value=""
    
    # Extract the maximum range from the control
    max_value=$(amixer -c "$card_index" cget numid="$numid" 2>/dev/null | grep -o "max=[0-9]*" | cut -d'=' -f2)
    
    # Verify that max_value is a valid number
    if [[ -n "$max_value" ]] && [[ "$max_value" =~ ^[0-9]+$ ]]; then
        echo "$max_value"
    else
        # Fallback to standard values
        echo "128"
    fi
}

# Function to apply volume configuration safely
apply_volume_settings() {
    local card_index=$1
    shift
    local controls=("$@")
    local success=false
    local critical_controls=("PCM" "Master" "Playback" "Headphone")
    
    log "Applying safe volume configuration for card $card_index..."
    
    # First try with critical controls (maximum 3 controls)
    local critical_found=0
    for control in "${controls[@]}"; do
        local numid=$(echo "$control" | cut -d':' -f1)
        local control_name=$(echo "$control" | cut -d':' -f2-)
        
        # Limit to maximum 3 critical controls to avoid overload
        if [[ $critical_found -ge 3 ]]; then
            log "⚠️ Critical control limit reached (3), skipping further changes"
            break
        fi
        
        # Check if it's a critical control
        local is_critical=false
        for critical in "${critical_controls[@]}"; do
            if [[ "$control_name" == *"$critical"* ]]; then
                is_critical=true
                break
            fi
        done
        
        if [[ "$is_critical" == "true" ]] || [[ "$numid" == "generic" ]]; then
            critical_found=$((critical_found + 1))
            
            # Method 1: Try with control name (if not a numeric numid)
            if [[ "$numid" == "generic" ]]; then
                # Set volume to 70% to avoid overload
                if amixer -c "$card_index" sset "$control_name" 70% unmute >/dev/null 2>&1; then
                    log "✅ Volume set for critical control: $control_name (70%)"
                    success=true
                fi
            # Method 2: Try with specific numid (with range check)
            elif [[ "$numid" =~ ^[0-9]+$ ]]; then
                local max_range=$(get_volume_range "$card_index" "$numid")
                local safe_value=$((max_range * 70 / 100))
                
                # Set volume to 70% of maximum range
                if amixer -c "$card_index" cset numid="$numid" "$safe_value" >/dev/null 2>&1; then
                    log "✅ Volume set for numid=$numid (safe value: $safe_value out of $max_range)"
                    success=true
                # Fallback to medium value if 70% doesn't work
                elif amixer -c "$card_index" cset numid="$numid" $((max_range / 2)) >/dev/null 2>&1; then
                    log "✅ Volume set for numid=$numid (medium value: $((max_range / 2)))"
                    success=true
                # Method 3: Try with unmute
                elif amixer -c "$card_index" cset numid="$numid" on >/dev/null 2>&1; then
                    log "✅ Control enabled for numid=$numid"
                    success=true
                fi
            fi
        fi
    done
    
    # If no critical controls found, try with first 2 generic controls
    if [[ "$success" == "false" ]] && [[ ${#controls[@]} -gt 0 ]]; then
        log "⚠️ No critical controls found, trying with first 2 generic controls..."
        
        local generic_count=0
        for control in "${controls[@]}"; do
            if [[ $generic_count -ge 2 ]]; then
                break
            fi
            
            local numid=$(echo "$control" | cut -d':' -f1)
            local control_name=$(echo "$control" | cut -d':' -f2-)
            
            if [[ "$numid" == "generic" ]]; then
                if amixer -c "$card_index" sset "$control_name" 50% unmute >/dev/null 2>&1; then
                    log "✅ Volume set for generic control: $control_name (50%)"
                    success=true
                    generic_count=$((generic_count + 1))
                fi
            elif [[ "$numid" =~ ^[0-9]+$ ]]; then
                local max_range=$(get_volume_range "$card_index" "$numid")
                local safe_value=$((max_range * 50 / 100))
                
                if amixer -c "$card_index" cset numid="$numid" "$safe_value" >/dev/null 2>&1; then
                    log "✅ Volume set for numid=$numid (safe value: $safe_value out of $max_range)"
                    success=true
                    generic_count=$((generic_count + 1))
                fi
            fi
        done
    fi
    
    if [[ "$success" == "false" ]]; then
        log "⚠️ Unable to configure volumes automatically"
        log "Suggestion: check available controls with 'amixer -c $card_index controls'"
        return 1
    else
        log "✅ Safe volume configuration completed successfully"
        return 0
    fi
}


# Main function for universal hardware volume configuration
fix_hardware_volumes() {
    log "Universal hardware volume configuration for UAC cards..."
    
    # Find the UAC audio card (same approach as Phase 3)
    local uac_card=""
    
    # Search for UAC card using the same method as Phase 3
    for card_path in /sys/class/sound/card*; do
        [ -e "$card_path" ] || continue
        CARD_ID=$(basename "$card_path" | sed 's/card//')
        
        # Verify if the card is USB by checking the physical device path
        if readlink "$card_path/device" 2>/dev/null | grep -q "usb"; then
            CARD_NAME=$(cat "$card_path/id" 2>/dev/null || echo "Unknown")
            log "✅ UAC Hardware device detected: card $CARD_ID ($CARD_NAME)"
            uac_card="$CARD_ID"
            break
        fi
    done
    
    # If we don't find UAC devices via kernel, try the ALSA detection fallback
    if [ -z "$uac_card" ]; then
        log "⚠️ No UAC device found via kernel, fallback to ALSA detection..."
        
        # Search for any USB card (contains "USB" in name)
        uac_card=$(aplay -l | grep -i "USB" | grep -E "card [0-9]+:" | head -n1 | cut -d' ' -f2 | tr -d ':')
        
        if [ -n "$uac_card" ]; then
            log "✅ Generic USB card found: card $uac_card"
        fi
    fi
    
    # If we don't find USB cards, don't proceed with volume configuration
    if [ -z "$uac_card" ]; then
        log "⚠️ No USB UAC card found, skipping volume configuration"
        log "   Possible causes:"
        log "   - Audio card is not Class Compliant (requires proprietary drivers)"
        log "   - Card is not connected properly"
        log "   - Card is disabled in USB permissions"
        log "   - Card does not support UAC standard"
        return 0
    fi
    
    log "Configuring volumes for UAC card: card $uac_card"
    
    # Add an availability check before proceeding
    if ! amixer -c "$uac_card" info >/dev/null 2>&1; then
        log "⚠️ Card detected but not yet ready for ALSA. Waiting..."
        sleep 2
    fi
    
    # Detect available volume controls
    local volume_controls=($(detect_volume_controls "$uac_card"))
    
    if [[ ${#volume_controls[@]} -eq 0 ]]; then
        log "⚠️ No volume controls found on card $uac_card"
        log "Skipping volume configuration (not a critical error)"
        return 0
    fi
    
    # Apply volume configuration
    if apply_volume_settings "$uac_card" "${volume_controls[@]}"; then
        log "✅ Hardware volume configuration completed successfully"
        return 0
    else
        log "⚠️ Volume configuration failed, but not critical for startup"
        log "   Audio card should still work"
        return 0
    fi
}

# Main function
main() {
    prepare_system
    
    log "=== PHASE 2: HARDWARE OPTIMIZATION ==="
    info "Dedicated audio core: $IRQ_CORE (mask: $CPU_MASK_CORE_1)"
    
    # Hardware detection
    local audio_irqs=($(detect_audio_hardware))
    
    # IRQ affinity configuration
    configure_irq_affinity "${audio_irqs[@]}"
    
    # Verify configuration
    verify_irq_configuration
    
    # Hardware volume configuration (new function to prevent zero volume problem)
    fix_hardware_volumes
    
    # Final hardware check
    final_hardware_check
    
    log "Hardware configuration, IRQ pinning and volumes completed"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
