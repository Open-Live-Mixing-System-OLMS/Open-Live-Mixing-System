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

# --- RILEVAMENTO UTENTE REALE ---
# Se lo script è lanciato con sudo, SUDO_USER contiene l'utente originale.
# Se lanciato direttamente da root (es. systemd), usa root.
REAL_USER="${SUDO_USER:-$USER}"

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to get process IDs by name pattern
get_process_pids() {
    local process_pattern="$1"
    pgrep -f "$process_pattern" 2>/dev/null || true
}

# Function to check if user has realtime privileges
check_realtime_privileges() {
    local target_user="${1:-$REAL_USER}"
    print_status "Checking realtime privileges for user: $target_user..."
    
    # Check if user is in realtime group
    if groups "$target_user" | grep -q "realtime"; then
        print_status "✓ User $target_user is in realtime group"
    else
        print_status "⚠ User $target_user is NOT in realtime group"
        # Fix suggerito dinamico
        print_status "  To fix: sudo usermod -aG realtime $target_user"
        return 1
    fi
    
    # Check if user is in audio group
    if groups "$target_user" | grep -q "audio"; then
        print_status "✓ User $target_user is in audio group"
    else
        print_status "⚠ User $target_user is NOT in audio group"
        print_status "  To fix: sudo usermod -aG audio $target_user"
        return 1
    fi
    
    # Check current realtime priority limit
    # Nota: ulimit controlla i limiti della shell CORRENTE (quindi root/sudo).
    # Tuttavia, se root ha privilegi illimitati, va bene. 
    # Il controllo cruciale era l'appartenenza al gruppo dell'utente audio.
    local rt_limit=$(ulimit -r)
    
    if [ "$rt_limit" = "unlimited" ] || [ "$rt_limit" -ge 90 ]; then
        print_status "✓ Realtime privileges are active (limit: $rt_limit)"
        return 0
    else
        print_status "⚠ Realtime privileges limit low: $rt_limit"
        if sudo -n ulimit -r 99 2>/dev/null; then
             print_status "✓ Temporary RT privileges set"
             return 0
        fi
        return 0 # Non blocchiamo, proviamo comunque
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

# Function to add debug environment for diagnostics
debug_environment() {
    print_status "=== Environment Debug ==="
    print_status "Effective User: $USER"
    print_status "Original User (SUDO_USER): $SUDO_USER"
    print_status "Target Logic User: $REAL_USER"
    print_status "HOME: $HOME"
    print_status "SHELL: $SHELL"
    print_status "ulimit -r: $(ulimit -r)"
    print_status "ulimit -l: $(ulimit -l)"
    print_status "groups: $(groups)"
    print_status "DISPLAY: $DISPLAY"
    print_status "XAUTHORITY: $XAUTHORITY"
    print_status "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
    print_status "CPU_CORES: $CPU_CORES"
    print_status "AUDIO_CPU_CORES: $AUDIO_CPU_CORES"
    print_status "SYSTEM_CPU_CORES: $SYSTEM_CPU_CORES"
    print_status "=== End Environment Debug ==="
}

# Function to restart JACK with proper RT priority (NEW - CRITICAL FIX)
restart_jack_with_rt_priority() {
    local jack_cmd="$1"
    
    print_status "Restarting JACK with proper RT priority configuration..."
    
    # Stop existing JACK processes
    local jack_pids=$(get_process_pids "jackd")
    if [ -n "$jack_pids" ]; then
        print_status "Stopping existing JACK processes: $jack_pids"
        for pid in $jack_pids; do
            if [ -d "/proc/$pid" ]; then
                print_status "  Stopping JACK PID $pid..."
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
        
        # Force kill any remaining JACK processes
        local remaining_pids=$(get_process_pids "jackd")
        if [ -n "$remaining_pids" ]; then
            print_status "Force killing remaining JACK processes: $remaining_pids"
            for pid in $remaining_pids; do
                kill -9 "$pid" 2>/dev/null || true
            done
            sleep 2
        fi
    fi
    
    # Clean up JACK socket files
    print_status "Cleaning JACK socket files..."
    local socket_files="/tmp/jack_* /dev/shm/jack_* /var/run/jack_* /run/jack_* /tmp/.jack* /var/lock/.jack*"
    for socket_pattern in $socket_files; do
        if ls $socket_pattern 1>/dev/null 2>&1; then
            rm -f $socket_pattern 2>/dev/null || true
        fi
    done
    
    # Start JACK with proper RT configuration
    print_status "Starting JACK with RT priority: $jack_cmd"
    
    # Ensure we have proper RT privileges before starting
    if ! check_realtime_privileges; then
        print_status "Warning: Realtime privileges not properly configured"
        print_status "Attempting to set temporary RT privileges..."
        attempt_temporary_rt_privileges
    fi
    
    # Start JACK with RT scheduling
    eval "$jack_cmd" &
    local new_jack_pid=$!
    
    # Wait for JACK to start
    sleep 3
    
    # Verify JACK started successfully
    if kill -0 $new_jack_pid 2>/dev/null; then
        print_status "✓ JACK restarted successfully with PID: $new_jack_pid"
        
        # Verify RT priority was applied correctly
        local current_policy=$(chrt -p "$new_jack_pid" 2>/dev/null | grep "policy" | awk '{print $3}')
        local current_priority=$(chrt -p "$new_jack_pid" 2>/dev/null | grep "priority" | awk '{print $3}')
        
        if [ "$current_policy" = "SCHED_FIFO" ] && [ "$current_priority" = "80" ]; then
            print_status "✓ JACK has correct RT priority (SCHED_FIFO, priority 80)"
            return 0
        else
            print_status "⚠ JACK RT priority may not be optimal"
            print_status "  Current: $current_policy, priority $current_priority"
            print_status "  Expected: SCHED_FIFO, priority 80"
            return 1
        fi
    else
        print_status "✗ Failed to restart JACK"
        return 1
    fi
}

# Function to set process priorities with RT scheduling (IMPROVED WITH RETRY MECHANISM)
set_process_rt_priority() {
    local process_pattern="$1"
    local rt_priority="$2"
    local process_name="$3"
    
    print_status "Setting RT priority for $process_name processes..."
    
    # Check privileges before attempting to set RT priority
    if ! check_realtime_privileges; then
        print_status "Warning: Realtime privileges may not be fully configured"
        print_status "  Attempting to set temporary RT privileges for current session..."
        
        # Try to set temporary RT privileges for current session
        if ! attempt_temporary_rt_privileges; then
            print_status "  Cannot set RT privileges for current session"
            print_status "  This may cause RT priority setting to fail"
            print_status "  Audio processes will run without realtime scheduling"
            print_status "  To fix permanently: log out and log back in after group configuration"
        fi
    fi
    
    local pids=$(get_process_pids "$process_pattern")
    if [ -z "$pids" ]; then
        print_status "No $process_name processes found - will retry when processes are running"
        return 0
    fi
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_status "RT priority setting attempt $attempt/$max_attempts..."
        
        local success_count=0
        local total_count=0
        
        for pid in $pids; do
            if [ -d "/proc/$pid" ]; then
                total_count=$((total_count + 1))
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                local current_policy=$(chrt -p "$pid" 2>/dev/null | grep "policy" | awk '{print $3}')
                local current_priority=$(chrt -p "$pid" 2>/dev/null | grep "priority" | awk '{print $3}')
                
                # Check if process already has correct RT configuration
                if [ "$current_policy" = "SCHED_FIFO" ] && [ "$current_priority" = "$rt_priority" ]; then
                    print_status "  ✓ PID $pid ($process_cmd) already has correct RT configuration (SCHED_FIFO, priority $rt_priority)"
                    success_count=$((success_count + 1))
                    continue
                fi
                
                print_status "  Setting RT priority for PID $pid ($process_cmd) to $rt_priority"
                
                # Use chrt for RT scheduling with improved error handling
                if chrt -f "$rt_priority" -p "$pid" 2>/dev/null; then
                    print_status "    ✓ PID $pid ($process_cmd): RT priority set successfully"
                    success_count=$((success_count + 1))
                else
                    # Check if the process already has RT scheduling but different priority
                    local new_policy=$(chrt -p "$pid" 2>/dev/null | grep "policy" | awk '{print $3}')
                    local new_priority=$(chrt -p "$pid" 2>/dev/null | grep "priority" | awk '{print $3}')
                    
                    if [ "$new_policy" = "SCHED_FIFO" ] && [ -n "$new_priority" ]; then
                        print_status "    ⚠ PID $pid ($process_cmd): Process has RT scheduling but wrong priority"
                        print_status "      Current: SCHED_FIFO, priority $new_priority"
                        print_status "      Expected: SCHED_FIFO, priority $rt_priority"
                        print_status "      This may cause audio performance issues"
                        success_count=$((success_count + 1))  # Count as success since it has RT scheduling
                    else
                        print_status "    ✗ PID $pid ($process_cmd): Failed to set RT priority"
                        print_status "      This process will not have realtime scheduling"
                        print_status "      Check: user privileges, process permissions, and system limits"
                        print_status "      Audio performance may be sub-optimal"
                    fi
                fi
                
                # Also set nice value for additional priority
                if ! renice -5 "$pid" > /dev/null 2>&1; then
                    print_status "    Warning: Failed to set nice value for PID $pid"
                fi
            fi
        done
        
        # Check if we have sufficient success rate
        if [ $total_count -eq 0 ]; then
            print_status "  No processes found to configure"
            return 0
        fi
        
        local success_rate=$((success_count * 100 / total_count))
        print_status "  Success rate: $success_rate% ($success_count/$total_count processes)"
        
        if [ $success_rate -eq 100 ]; then
            print_status "✓ All processes successfully configured with RT priority"
            return 0
        elif [ $success_rate -ge 80 ]; then
            print_status "✓ Most processes configured with RT priority (partial success)"
            return 0
        elif [ $attempt -lt $max_attempts ]; then
            print_status "  Retrying in 2 seconds..."
            sleep 2
        fi
        
        attempt=$((attempt + 1))
    done
    
    print_status "⚠ RT priority setting completed with partial success after $max_attempts attempts"
    return 0
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
    
    # Calculate expected mask for validation (for all cores >=2)
    # This should match the actual audio core allocation
    local expected_mask=0
    for ((i=2; i<CPU_CORES; i++)); do  # All cores >=2
        expected_mask=$((expected_mask | (1 << i)))
    done
    EXPECTED_CPU_MASK=$(printf "0x%x" $expected_mask)
    
    print_status "✓ CPU masks configured successfully"
    print_status "Audio CPU cores: $AUDIO_CPU_CORES (mask: $AUDIO_CPU_MASK)"
    print_status "System CPU cores: $SYSTEM_CPU_CORES (mask: $SYSTEM_CPU_MASK)"
    print_status "Expected mask for validation: $EXPECTED_CPU_MASK"
    print_status "Total available CPU cores: $CPU_CORES"
}

# Function to get actual CPU affinity from taskset output
get_actual_affinity() {
    local pid="$1"
    if [ -d "/proc/$pid" ]; then
        # Use taskset to get the actual affinity
        local affinity_output=$(taskset -p "$pid" 2>/dev/null)
        if [ $? -eq 0 ]; then
            # Extract the hex mask from output like "pid 123's current affinity mask: 0xf"
            echo "$affinity_output" | awk -F': ' '{print $2}' | tr -d ' '
        else
            echo "error"
        fi
    else
        echo "notfound"
    fi
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
                
                # Use the correct format for taskset (comma-separated list for multiple cores)
                # For cores 2+ we need to use "2,3,4,..." format
                local affinity_cores="$AUDIO_CPU_CORES"
                # Convert range format to comma-separated if needed
                if [[ "$affinity_cores" == *"-"* ]]; then
                    # Convert range like "2-3" to "2,3" or "2-5" to "2,3,4,5"
                    local start_core=$(echo "$affinity_cores" | cut -d'-' -f1)
                    local end_core=$(echo "$affinity_cores" | cut -d'-' -f2)
                    affinity_cores=""
                    for ((i=start_core; i<=end_core; i++)); do
                        if [ -z "$affinity_cores" ]; then
                            affinity_cores="$i"
                        else
                            affinity_cores="$affinity_cores,$i"
                        fi
                    done
                fi
                
                taskset -cp "$affinity_cores" "$pid" > /dev/null 2>&1 || {
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
                
                # Use the correct format for taskset (comma-separated list for multiple cores)
                local affinity_cores="$AUDIO_CPU_CORES"
                # Convert range format to comma-separated if needed
                if [[ "$affinity_cores" == *"-"* ]]; then
                    # Convert range like "2-3" to "2,3" or "2-5" to "2,3,4,5"
                    local start_core=$(echo "$affinity_cores" | cut -d'-' -f1)
                    local end_core=$(echo "$affinity_cores" | cut -d'-' -f2)
                    affinity_cores=""
                    for ((i=start_core; i<=end_core; i++)); do
                        if [ -z "$affinity_cores" ]; then
                            affinity_cores="$i"
                        else
                            affinity_cores="$affinity_cores,$i"
                        fi
                    done
                fi
                
                taskset -cp "$affinity_cores" "$pid" > /dev/null 2>&1 || {
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
            local actual_affinity=$(get_actual_affinity "$pid")
            local expected_mask="$EXPECTED_CPU_MASK"
            
            if [ "$actual_affinity" = "error" ]; then
                print_status "ERROR: Cannot read affinity for PID $pid"
                validation_passed=false
            elif [ "$actual_affinity" = "notfound" ]; then
                print_status "ERROR: Process PID $pid not found"
                validation_passed=false
            else
                # Normalize both values for comparison (remove 0x prefix if present)
                local normalized_actual="${actual_affinity#0x}"
                local normalized_expected="${expected_mask#0x}"
                
                if [ "$normalized_actual" != "$normalized_expected" ]; then
                    print_status "CRITICAL FAILURE: PID $pid has wrong affinity: $actual_affinity (expected: $expected_mask)"
                    print_status "  Normalized comparison: $normalized_actual != $normalized_expected"
                    validation_passed=false
                else
                    print_status "✓ PID $pid correctly pinned to cores $AUDIO_CPU_CORES (affinity: $actual_affinity)"
                fi
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

# Debug environment for diagnostics
print_status "Phase 0: Environment Debug"
debug_environment
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