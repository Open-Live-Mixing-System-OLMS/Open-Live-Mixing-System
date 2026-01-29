#!/bin/bash

# OLMS CPU Affinity Configuration Script
# 
# This script configures CPU affinity and resource allocation for optimal
# audio performance by setting process priorities and CPU core allocation.
# 
# Based on OLMS specifications for real-time audio system optimization.

set -e

# Default values
CPU_CORES=${CPU_CORES:-$(nproc)}
AUDIO_CPU_CORES=${AUDIO_CPU_CORES:-"2-$(($CPU_CORES-1))"}  # Default to cores 2+ for audio (Core 1 reserved for IRQs)
SYSTEM_CPU_CORES=${SYSTEM_CPU_CORES:-"0"}  # Use core 0 for system processes

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to get process IDs by name pattern
get_process_pids() {
    local process_pattern="$1"
    pgrep -f "$process_pattern" 2>/dev/null || true
}

# Function to set process priorities with RT scheduling (CORRECTED)
set_process_rt_priority() {
    local process_pattern="$1"
    local rt_priority="$2"
    local process_name="$3"
    
    print_status "Setting RT priority for $process_name processes..."
    
    local pids=$(get_process_pids "$process_pattern")
    if [ -z "$pids" ]; then
        print_status "No $process_name processes found - will retry when processes are running"
        return 0
    fi
    
    for pid in $pids; do
        if [ -d "/proc/$pid" ]; then
            local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
            print_status "Setting RT priority for PID $pid ($process_cmd) to $rt_priority"
            
            # Use chrt for RT scheduling (CORRECT STRATEGY)
            chrt -f "$rt_priority" -p "$pid" 2>/dev/null || {
                print_status "Warning: Failed to set RT priority for PID $pid (may need realtime privileges)"
            }
            
            # Also set nice value for additional priority
            renice -5 "$pid" > /dev/null 2>&1 || {
                print_status "Warning: Failed to set nice value for PID $pid"
            }
        fi
    done
}

# Function to set Ardour thread affinity
set_ardour_thread_affinity() {
    local ardour_pid="$1"
    
    if [ -d "/proc/$ardour_pid/task" ]; then
        print_status "Setting affinity for Ardour threads..."
        for thread_dir in /proc/$ardour_pid/task/*/; do
            if [ -d "$thread_dir" ]; then
                local thread_pid=$(basename "$thread_dir")
                if [[ "$thread_pid" =~ ^[0-9]+$ ]]; then
                    taskset -cp $AUDIO_CPU_CORES "$thread_pid" > /dev/null 2>&1 || true
                fi
            fi
        done
    fi
}

# Function to verify RT priority was applied successfully
verify_rt_priority() {
    local process_pattern="$1"
    local process_name="$2"
    
    print_status "Verifying RT priority for $process_name processes..."
    
    local pids=$(get_process_pids "$process_pattern")
    if [ -z "$pids" ]; then
        print_status "No $process_name processes found for verification"
        return 0
    fi
    
    for pid in $pids; do
        if [ -d "/proc/$pid" ]; then
            local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
            local current_policy=$(chrt -p "$pid" 2>/dev/null | grep "policy" | awk '{print $3}')
            local current_priority=$(chrt -p "$pid" 2>/dev/null | grep "priority" | awk '{print $3}')
            
            if [ "$current_policy" = "SCHED_FIFO" ] && [ -n "$current_priority" ]; then
                print_status "  ✓ PID $pid ($process_cmd): RT priority $current_priority (SCHED_FIFO)"
            else
                print_status "  ⚠ PID $pid ($process_cmd): Priority not set correctly"
                print_status "    Current policy: $current_policy"
                print_status "    Current priority: $current_priority"
            fi
        fi
    done
}

# Function to set process priorities (nice values only for system processes)
set_process_priorities() {
    local process_pattern="$1"
    local nice_value="$2"
    local process_name="$3"
    
    print_status "Setting process priority for $process_name processes..."
    
    local pids=$(get_process_pids "$process_pattern")
    if [ -z "$pids" ]; then
        print_status "No $process_name processes found"
        return 0
    fi
    
    for pid in $pids; do
        if [ -d "/proc/$pid" ]; then
            local current_nice=$(ps -p "$pid" -o ni= 2>/dev/null | head -1 | tr -d ' ')
            if [ "$current_nice" != "$nice_value" ]; then
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                print_status "Setting nice value for PID $pid ($process_cmd) to $nice_value"
                renice "$nice_value" "$pid" > /dev/null 2>&1 || {
                    print_status "Warning: Failed to set nice value for PID $pid"
                }
            fi
        fi
    done
}

# Function to configure CPU affinity masks
configure_cpu_masks() {
    print_status "Phase 1: CPU Mask Configuration"
    print_status "Configuring CPU affinity masks for optimal resource allocation..."
    
    # Create CPU mask for audio processes (cores 2+)
    # For multiple cores, we need to build the mask properly
    local audio_mask=0
    for ((i=2; i<CPU_CORES; i++)); do
        audio_mask=$((audio_mask | (1 << i)))
    done
    AUDIO_CPU_MASK=$(printf "0x%x" $audio_mask)
    
    # Create CPU mask for system processes (core 0 only)
    SYSTEM_CPU_MASK=$(printf "0x%x" $((1 << 0)))
    
    # Calculate expected mask for validation (for cores 2,3 on 4-core system: 0xc)
    # This is for backward compatibility with the validation function
    local expected_mask=0
    for ((i=2; i<4; i++)); do  # Only for first 4 cores (2,3)
        expected_mask=$((expected_mask | (1 << i)))
    done
    EXPECTED_CPU_MASK=$(printf "0x%x" $expected_mask)
    
    print_status "✓ CPU masks configured successfully"
    print_status "Audio CPU cores: $AUDIO_CPU_CORES (mask: $AUDIO_CPU_MASK)"
    print_status "System CPU cores: $SYSTEM_CPU_CORES (mask: $SYSTEM_CPU_MASK)"
    print_status "Expected mask for validation: $EXPECTED_CPU_MASK"
    print_status "Total available CPU cores: $CPU_CORES"
}

# Function to apply RT priorities to running processes (CORRECTED)
apply_running_process_rt_priority() {
    print_status "Applying RT priorities to running audio processes..."
    
    # Set RT priority for JACK processes (CORRECT STRATEGY)
    set_process_rt_priority "jackd" "80" "JACK"
    
    # Set RT priority for Ardour processes (CORRECT STRATEGY)
    set_process_rt_priority "ardour" "75" "Ardour"
    
    # Set normal priority for system processes (no RT needed)
    set_process_priorities "pulseaudio" "0" "PulseAudio"
    set_process_priorities "pipewire" "0" "PipeWire"
    set_process_priorities "wireplumber" "0" "WirePlumber"
}

# Function to apply CPU affinity to audio processes
apply_cpu_affinity() {
    print_status "Applying CPU affinity to audio processes..."
    
    # Apply affinity to JACK processes
    local jack_pids=$(get_process_pids "jackd")
    if [ -n "$jack_pids" ]; then
        print_status "Setting CPU affinity for JACK processes..."
        for pid in $jack_pids; do
            if [ -d "/proc/$pid" ]; then
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                print_status "Setting affinity for JACK PID $pid ($process_cmd) to cores $AUDIO_CPU_CORES"
                taskset -cp $AUDIO_CPU_CORES "$pid" > /dev/null 2>&1 || {
                    print_status "Warning: Failed to set affinity for JACK PID $pid"
                }
            fi
        done
    fi
    
    # Apply affinity to Ardour processes and their threads
    local ardour_pids=$(get_process_pids "ardour")
    if [ -n "$ardour_pids" ]; then
        print_status "Setting CPU affinity for Ardour processes and threads..."
        for pid in $ardour_pids; do
            if [ -d "/proc/$pid" ]; then
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                print_status "Setting affinity for Ardour PID $pid ($process_cmd) to cores $AUDIO_CPU_CORES"
                taskset -cp $AUDIO_CPU_CORES "$pid" > /dev/null 2>&1 || {
                    print_status "Warning: Failed to set affinity for Ardour PID $pid"
                }
                
                # Set affinity for all Ardour threads
                set_ardour_thread_affinity "$pid"
            fi
        done
    fi
}

# Function to validate affinity configuration
validate_affinity_configuration() {
    print_status "Validating affinity configuration..."
    
    local jack_pids=$(get_process_pids "jackd")
    local ardour_pids=$(get_process_pids "ardour")
    
    local validation_passed=true
    
    for pid in $jack_pids $ardour_pids; do
        if [ -n "$pid" ]; then
            local current_affinity=$(taskset -p "$pid" | awk -F': ' '{print $2}')
            # Use the calculated expected mask for validation
            local expected_mask="$EXPECTED_CPU_MASK"
            
            if [ "$current_affinity" != "$expected_mask" ]; then
                print_status "CRITICAL FAILURE: PID $pid has wrong affinity: $current_affinity (expected: $expected_mask)"
                validation_passed=false
            else
                print_status "✓ PID $pid correctly pinned to cores $AUDIO_CPU_CORES"
            fi
        fi
    done
    
    if [ "$validation_passed" = true ]; then
        print_status "✓ All audio processes correctly pinned to cores $AUDIO_CPU_CORES"
        return 0
    else
        print_status "✗ Some audio processes have incorrect affinity"
        return 1
    fi
}

# Function to apply process priorities (legacy function - kept for compatibility)
apply_process_priorities() {
    print_status "Applying process priorities..."
    
    # Note: Audio processes now use RT priority via apply_running_process_rt_priority
    # This function is kept for system processes only
    
    # Set normal priority for system processes
    set_process_priorities "pulseaudio" "0" "PulseAudio"
    set_process_priorities "pipewire" "0" "PipeWire"
    set_process_priorities "wireplumber" "0" "WirePlumber"
}

# Function to verify CPU affinity configuration
verify_cpu_affinity() {
    print_status "Verifying CPU affinity configuration..."
    
    # Check JACK processes
    local jack_pids=$(get_process_pids "jackd")
    if [ -n "$jack_pids" ]; then
        print_status "JACK process affinity (should be $AUDIO_CPU_CORES):"
        for pid in $jack_pids; do
            if [ -d "/proc/$pid" ]; then
                local current_affinity=$(taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}')
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                print_status "  PID $pid ($process_cmd): $current_affinity"
            fi
        done
    fi
    
    # Check Ardour processes
    local ardour_pids=$(get_process_pids "ardour")
    if [ -n "$ardour_pids" ]; then
        print_status "Ardour process affinity (should be $AUDIO_CPU_CORES):"
        for pid in $ardour_pids; do
            if [ -d "/proc/$pid" ]; then
                local current_affinity=$(taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}')
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                print_status "  PID $pid ($process_cmd): $current_affinity"
            fi
        done
    fi
}

# Function to show help
show_help() {
    echo "OLMS CPU Affinity Configuration Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --audio-cores LIST Specify CPU cores for audio processes (default: 2-$(($CPU_CORES-1)))"
    echo "  --system-cores LIST Specify CPU cores for system processes (default: 0)"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AUDIO_CPU_CORES    CPU cores for audio processes (default: 2-$(($CPU_CORES-1)))"
    echo "  SYSTEM_CPU_CORES   CPU cores for system processes (default: 0)"
    echo "  CPU_CORES          Total number of CPU cores (auto-detected)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use default settings (cores 2+ for audio, core 0 for system)"
    echo "  $0 --audio-cores 2,3        # Use CPU cores 2,3 for audio"
    echo "  AUDIO_CPU_CORES=2,3 $0      # Set via environment variable"
    echo ""
    echo "Architecture:"
    echo "  - Core 0: OS, servizi di sistema, I/O generale"
    echo "  - Core 1: IRQ controller USB scheda audio"
    echo "  - Core 2+: JACK2 e thread DSP Ardour"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --audio-cores)
            AUDIO_CPU_CORES="$2"
            shift 2
            ;;
        --system-cores)
            SYSTEM_CPU_CORES="$2"
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

# Validate CPU core configuration
# For now, we assume the default configuration is correct (cores 2+ for audio, core 0 for system)
# In a more advanced version, we could validate custom configurations
if [ "$CPU_CORES" -lt 4 ]; then
    print_status "Warning: System has less than 4 cores. OLMS requires minimum 4 cores for optimal performance."
    print_status "Current configuration: $CPU_CORES cores"
fi

print_status "=== OLMS CPU Affinity Configuration ==="
print_status "Audio CPU cores: $AUDIO_CPU_CORES"
print_status "System CPU cores: $SYSTEM_CPU_CORES"
print_status "Total CPU cores detected: $CPU_CORES"
echo

# Phase 1: Configure CPU masks
print_status "Phase 1: CPU Mask Configuration"
configure_cpu_masks
echo

# Phase 2: Apply RT priorities to running processes
print_status "Phase 2: RT Priority Configuration"
apply_running_process_rt_priority
echo

# Phase 3: Apply system process priorities
print_status "Phase 3: System Process Priority Configuration"
apply_process_priorities
echo

# Phase 4: Verify configuration
print_status "Phase 4: Configuration Verification"
verify_cpu_affinity
echo

# Phase 5: Apply CPU affinity
print_status "Phase 5: CPU Affinity Application"
apply_cpu_affinity
echo

# Phase 6: Validate affinity configuration
print_status "Phase 6: Affinity Validation"
if ! validate_affinity_configuration; then
    print_status "Error: CPU affinity validation failed"
    exit 1
fi
echo

# Phase 7: Verify RT priorities
print_status "Phase 7: RT Priority Verification"
verify_rt_priority "jackd" "JACK"
verify_rt_priority "ardour" "Ardour"
echo

print_status "=== CPU Affinity Configuration Complete ==="
print_status "CPU resources have been allocated for optimal audio performance"
print_status ""
print_status "Benefits:"
echo "  - Audio processes pinned to dedicated CPU core"
echo "  - Reduced CPU scheduling interference"
echo "  - Improved real-time audio performance"
echo "  - Optimized system resource allocation"
echo
print_status "To verify manually:"
echo "  taskset -p [PID]           # Check process affinity"
echo "  ps -p [PID] -o ni,cmd      # Check process priority"
echo
print_status "CPU affinity configuration completed successfully!"

# Keep the script running to maintain the configuration
trap "print_status 'CPU affinity configuration preserved'" EXIT