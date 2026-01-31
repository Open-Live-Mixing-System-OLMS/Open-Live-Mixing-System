#!/bin/bash

# OLMS IRQ Pinning Script
# 
# This script configures hardware IRQ pinning for optimal audio performance
# by detecting audio hardware and pinning IRQs to dedicated CPU cores.
# 
# Based on OLMS specifications for real-time audio system optimization.

set -e

# Default values
CPU_CORES=${CPU_CORES:-$(nproc)}
AUDIO_CPU_CORE=${AUDIO_CPU_CORE:-1}  # Default to core 1 for audio

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1" >&2
}

# Function to detect audio hardware and IRQ numbers
detect_audio_hardware() {
    print_status "=== DIAGNOSTICA AUDIO COMPLETA ==="
    print_status "Fase 1: Rilevamento hardware audio e assegnazione IRQ"
    
    local all_audio_irqs=""
    
    # METODO 1: Rilevamento tradizionale (schede integrate)
    print_status "Metodo 1: Rilevamento IRQ audio tradizionali..."
    local traditional_irqs=$(grep -iE "snd|audio|sound|hda|hdaudio|intel.*audio|realtek|creative|emu" /proc/interrupts 2>/dev/null | awk '{print $1}' | sed 's/://' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')
    
    if [ -n "$traditional_irqs" ]; then
        print_status "IRQ audio tradizionali trovate: $traditional_irqs"
        all_audio_irqs="$all_audio_irqs $traditional_irqs"
    fi
    
    # METODO 2: Rilevamento USB AUDIO (CRITICO FIX)
    print_status "Metodo 2: Rilevamento controller USB per audio..."
    
    # Controlliamo se ci sono dispositivi audio USB rilevati da ALSA
    local usb_audio_detected=false
    if arecord -l 2>/dev/null | grep -q "USB Audio\|usb.*audio\|audio.*usb"; then
        print_status "✓ Dispositivo audio USB rilevato in ALSA (capture)"
        usb_audio_detected=true
    fi
    
    if aplay -l 2>/dev/null | grep -q "USB Audio\|usb.*audio\|audio.*usb"; then
        print_status "✓ Dispositivo audio USB rilevato in ALSA (playback)"
        usb_audio_detected=true
    fi
    
    if [ "$usb_audio_detected" = true ]; then
        print_status "USB audio device detected, searching for USB controller IRQs..."
        
        # Ricerchiamo le IRQ dei controller USB
        local usb_controller_irqs=$(grep -iE "xhci_hcd|ehci_hcd|uhci_hcd" /proc/interrupts 2>/dev/null | awk '{print $1}' | sed 's/://' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')
        
        if [ -n "$usb_controller_irqs" ]; then
            print_status "Controller USB IRQs trovate: $usb_controller_irqs"
            all_audio_irqs="$all_audio_irqs $usb_controller_irqs"
            
            # Aggiungiamo anche eventuali IRQ con "usb" nella descrizione
            local usb_irqs=$(grep -iE "usb" /proc/interrupts 2>/dev/null | awk '{print $1}' | sed 's/://' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')
            if [ -n "$usb_irqs" ]; then
                print_status "IRQ USB aggiuntive trovate: $usb_irqs"
                all_audio_irqs="$all_audio_irqs $usb_irqs"
            fi
        else
            print_status "Attenzione: Dispositivo USB rilevato ma nessun controller USB trovato"
        fi
    else
        print_status "Nessun dispositivo audio USB rilevato"
    fi
    
    # METODO 3: Fallback per IRQ audio generiche
    print_status "Metodo 3: Ricerca fallback per IRQ audio..."
    local fallback_irqs=$(grep -iE "snd|audio|sound|hda|hdaudio|intel.*audio|realtek|creative|emu" /proc/interrupts 2>/dev/null | awk '{print $1}' | sed 's/://' | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')
    
    if [ -n "$fallback_irqs" ]; then
        print_status "IRQ audio di fallback trovate: $fallback_irqs"
        all_audio_irqs="$all_audio_irqs $fallback_irqs"
    fi
    
    # Validate and filter IRQs
    local unique_audio_irqs=""
    
    # Uniamo tutte le IRQ trovate dai diversi metodi
    local combined_irqs="$all_audio_irqs"
    
    print_status "DEBUG: combined_irqs = '$combined_irqs'"
    
    if [ -n "$combined_irqs" ]; then
        for irq in $combined_irqs; do
            print_status "DEBUG: Processing IRQ $irq"
            # Validate IRQ number
            if [[ "$irq" =~ ^[0-9]+$ ]] && [ "$irq" -ge 0 ] && [ "$irq" -le 4095 ]; then
                # Double-check that this IRQ is actually audio-related
                local irq_description=$(grep "^[ ]*$irq:" /proc/interrupts 2>/dev/null | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | xargs)
                print_status "DEBUG: IRQ $irq description: '$irq_description'"
                if echo "$irq_description" | grep -qiE "snd|audio|sound|hda|hdaudio|usb.*audio|intel.*audio|realtek|creative|emu|xhci_hcd|ehci_hcd|uhci_hcd"; then
                    print_status "DEBUG: IRQ $irq passed audio check"
                    # Only add if not already in the list
                    if ! echo "$unique_audio_irqs" | grep -q " $irq "; then
                        unique_audio_irqs="$unique_audio_irqs $irq "
                        print_status "DEBUG: Added IRQ $irq to unique list"
                    else
                        print_status "DEBUG: IRQ $irq already in unique list"
                    fi
                else
                    print_status "DEBUG: IRQ $irq failed audio check"
                fi
            else
                print_status "DEBUG: IRQ $irq failed validation"
            fi
        done
    fi
    
    # NEW: If we still have no IRQs, try a more direct approach
    if [ -z "$unique_audio_irqs" ] && [ -f "/proc/interrupts" ]; then
        print_status "No audio IRQs found with filtering, trying direct extraction..."
        
        # Extract all IRQs that have descriptions containing audio keywords
        local direct_irqs=$(grep -iE "snd|audio|sound|hda|hdaudio|usb.*audio|intel.*audio|realtek|creative|emu" /proc/interrupts 2>/dev/null | awk '{print $1}' | sed 's/://' | grep -E '^[0-9]+$' | sort -u)
        
        if [ -n "$direct_irqs" ]; then
            print_status "Found direct audio IRQs: $direct_irqs"
            unique_audio_irqs="$direct_irqs"
        fi
    fi
    
    # Trim whitespace
    unique_audio_irqs=$(echo "$unique_audio_irqs" | xargs)
    
    print_status "Final audio IRQs: '$unique_audio_irqs'"
    
    if [ -n "$unique_audio_irqs" ]; then
        print_status "✓ Audio hardware detection completed successfully"
        print_status "Detected audio IRQs: $unique_audio_irqs"
        echo "$unique_audio_irqs"
        return 0
    else
        print_status "✗ No audio hardware detected or IRQs not found"
        return 1
    fi
}

# Function to configure IRQ affinity with retry mechanism (IMPROVED VERSION)
configure_irq_affinity() {
    local irq_list="$1"
    
    print_status "Configuring IRQ affinity for audio optimization with retry mechanism..."
    
    # Create CPU mask for the dedicated audio core
    # Convert CPU core number to hex mask (e.g., core 1 = 0x2, core 2 = 0x4)
    local cpu_mask=$(printf "0x%x" $((1 << AUDIO_CPU_CORE)))
    
    print_status "Pinning audio IRQs to CPU core $AUDIO_CPU_CORE (mask: $cpu_mask)"
    
    # Apply IRQ affinity for each detected IRQ with retry mechanism
    for irq in $irq_list; do
        local irq_file="/proc/irq/$irq/smp_affinity"
        
        if [ -f "$irq_file" ]; then
            # Check if IRQ is configurable before attempting to set it
            if check_irq_configurability "$irq"; then
                print_status "Setting IRQ $irq affinity to $cpu_mask..."
                
                # Use retry mechanism for IRQ pinning
                local max_attempts=3
                local attempt=1
                local success=false
                
                while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
                    print_status "  IRQ pinning attempt $attempt/$max_attempts for IRQ $irq..."
                    
                    if echo "$cpu_mask" | sudo tee "$irq_file" > /dev/null 2>&1; then
                        # Verify the setting was applied
                        local current_affinity=$(cat "$irq_file")
                        if [ "$current_affinity" = "$cpu_mask" ]; then
                            print_status "  ✓ IRQ $irq successfully pinned to CPU core $AUDIO_CPU_CORE"
                            success=true
                        else
                            print_status "  Warning: IRQ $irq affinity mismatch: expected $cpu_mask, got $current_affinity"
                            if [ $attempt -lt $max_attempts ]; then
                                print_status "  Retrying in 1 second..."
                                sleep 1
                            fi
                        fi
                    else
                        print_status "  Warning: Failed to set IRQ $irq affinity (may not be configurable)"
                        if [ $attempt -lt $max_attempts ]; then
                            print_status "  Retrying in 1 second..."
                            sleep 1
                        fi
                    fi
                    
                    attempt=$((attempt + 1))
                done
                
                if [ "$success" = false ]; then
                    print_status "  ✗ IRQ $irq could not be pinned after $max_attempts attempts"
                fi
            else
                print_status "IRQ $irq not configurable, trying alternative pinning..."
                # Try fallback pinning with broader mask
                configure_irq_fallback "$irq"
            fi
        else
            print_status "Warning: IRQ $irq smp_affinity file not found"
        fi
    done
}

# Function to configure IRQ affinity fallback for non-configurable IRQs
configure_irq_fallback() {
    local irq="$1"
    
    # Try alternative pinning strategies for non-configurable IRQs
    local irq_file="/proc/irq/$irq/smp_affinity"
    
    # Strategy 1: Try to pin to audio core + adjacent core
    local fallback_mask=$(printf "0x%x" $((1 << AUDIO_CPU_CORE | 1 << ((AUDIO_CPU_CORE + 1) % CPU_CORES))))
    print_status "Trying fallback mask $fallback_mask for IRQ $irq"
    
    if echo "$fallback_mask" | sudo tee "$irq_file" > /dev/null 2>&1; then
        local current_affinity=$(cat "$irq_file")
        if [ "$current_affinity" = "$fallback_mask" ]; then
            print_status "✓ IRQ $irq pinned with fallback mask to cores $AUDIO_CPU_CORE and $(( (AUDIO_CPU_CORE + 1) % CPU_CORES ))"
            return 0
        fi
    fi
    
    # Strategy 2: Try to pin only to audio core (force attempt)
    local audio_core_mask=$(printf "0x%x" $((1 << AUDIO_CPU_CORE)))
    print_status "Trying force pinning to audio core $AUDIO_CPU_CORE for IRQ $irq"
    
    if echo "$audio_core_mask" | sudo tee "$irq_file" > /dev/null 2>&1; then
        local current_affinity=$(cat "$irq_file")
        if [ "$current_affinity" = "$audio_core_mask" ]; then
            print_status "✓ IRQ $irq force pinned to audio core $AUDIO_CPU_CORE"
            return 0
        fi
    fi
    
    # Strategy 3: Check if IRQ is already pinned to desired core
    local current_affinity=$(cat "$irq_file")
    local current_mask=$(printf "0x%x" $((1 << AUDIO_CPU_CORE)))
    
    if [ "$current_affinity" = "$current_mask" ]; then
        print_status "✓ IRQ $irq already pinned to audio core $AUDIO_CPU_CORE"
        return 0
    fi
    
    print_status "✗ IRQ $irq could not be pinned (may be kernel-managed)"
    return 1
}

# Function to check if IRQ is configurable
check_irq_configurability() {
    local irq="$1"
    
    # Check if IRQ is shared (multiple handlers)
    local irq_info="/proc/interrupts"
    if [ -f "$irq_info" ]; then
        local irq_line=$(grep "^$irq:" "$irq_info")
        if [ -n "$irq_line" ]; then
            # Count the number of CPU columns with non-zero values (excluding the first column which is the IRQ number)
            local cpu_count=$(echo "$irq_line" | awk '{for(i=2;i<=NF;i++) if($i>0) count++} END{print count+0}')
            if [ "$cpu_count" -gt 1 ]; then
                print_status "IRQ $irq appears to be shared across multiple CPUs"
                return 1
            fi
        fi
    fi
    
    # Check if IRQ is managed by kernel (common for timer IRQs)
    local irq_type="/proc/irq/$irq/affinity_hint"
    if [ -f "$irq_type" ]; then
        local affinity_hint=$(cat "$irq_type" 2>/dev/null)
        if [ -n "$affinity_hint" ] && [ "$affinity_hint" = "0" ]; then
            print_status "IRQ $irq is kernel-managed and not configurable"
            return 1
        fi
    fi
    
    # Check if IRQ is a timer or other system IRQ
    local irq_description=$(grep "^$irq:" /proc/interrupts 2>/dev/null | cut -d' ' -f4-)
    if echo "$irq_description" | grep -qiE "timer|clock|rtc|i8042|keyboard|mouse"; then
        print_status "IRQ $irq is a system IRQ and not configurable for audio"
        return 1
    fi
    
    return 0
}

# Function to verify IRQ pinning configuration
verify_irq_pinning() {
    local irq_list="$1"
    
    print_status "Verifying IRQ pinning configuration..."
    
    local cpu_mask=$(printf "0x%x" $((1 << AUDIO_CPU_CORE)))
    
    for irq in $irq_list; do
        local irq_file="/proc/irq/$irq/smp_affinity"
        
        if [ -f "$irq_file" ]; then
            local current_affinity=$(cat "$irq_file")
            if [ "$current_affinity" = "$cpu_mask" ]; then
                print_status "✓ IRQ $irq correctly pinned to CPU core $AUDIO_CPU_CORE"
            else
                print_status "✗ IRQ $irq affinity mismatch: expected $cpu_mask, got $current_affinity"
            fi
        fi
    done
}

# Function to show help
show_help() {
    echo "OLMS IRQ Pinning Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --cpu-core N     Specify CPU core for audio IRQs (default: 1)"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AUDIO_CPU_CORE   CPU core number for audio IRQs (default: 1)"
    echo "  CPU_CORES        Total number of CPU cores (auto-detected)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use default settings"
    echo "  $0 --cpu-core 2             # Pin to CPU core 2"
    echo "  AUDIO_CPU_CORE=3 $0         # Pin to CPU core 3 via environment"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cpu-core)
            AUDIO_CPU_CORE="$2"
            shift 2
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

# Validate CPU core number
if ! [[ "$AUDIO_CPU_CORE" =~ ^[0-9]+$ ]] || [ "$AUDIO_CPU_CORE" -lt 0 ] || [ "$AUDIO_CPU_CORE" -ge "$CPU_CORES" ]; then
    print_status "Error: Invalid CPU core number: $AUDIO_CPU_CORE"
    print_status "Valid range: 0-$((CPU_CORES-1))"
    exit 1
fi

print_status "=== OLMS IRQ Pinning Configuration ==="
print_status "Target CPU core: $AUDIO_CPU_CORE"
print_status "Total CPU cores detected: $CPU_CORES"
echo

# Phase 1: Detect audio hardware
print_status "Phase 1: Audio Hardware Detection"
audio_irqs=$(detect_audio_hardware)
if [ $? -ne 0 ]; then
    print_status "Warning: No audio hardware detected, skipping IRQ pinning"
    exit 0
fi
echo

# Phase 2: Configure IRQ affinity
print_status "Phase 2: IRQ Affinity Configuration"
configure_irq_affinity "$audio_irqs"
echo

# Phase 3: Verify configuration
print_status "Phase 3: Configuration Verification"
verify_irq_pinning "$audio_irqs"
echo

print_status "=== IRQ Pinning Complete ==="
print_status "Audio IRQs have been pinned to CPU core $AUDIO_CPU_CORE for optimal performance"
print_status ""
print_status "Benefits:"
echo "  - Reduced audio latency through dedicated CPU core"
echo "  - Minimized IRQ handling interference from other processes"
echo "  - Improved real-time audio performance"
echo
print_status "To verify manually:"
echo "  cat /proc/irq/[IRQ_NUMBER]/smp_affinity"
echo "  # Should show the CPU mask for core $AUDIO_CPU_CORE"
echo
print_status "IRQ pinning configuration completed successfully!"
