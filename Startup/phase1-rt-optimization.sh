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

# Phase 1: System Real-Time Optimization
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
RT_CONFIG_FILE="/etc/sysctl.d/99-olms-rt.conf"
LIMITS_FILE="/etc/security/limits.d/99-realtime.conf"
MODE="${OLMS_RT_MODE:-prod}"  # prod, test, light

# Environment variables for the "all as same user" approach
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

# Function to write system files with privileges
safe_write_file() {
    local content="$1"
    local target="$2"
    echo "$content" > "$target"
}

# Configure kernel parameters
configure_kernel_parameters() {
    log "Configuring RT kernel parameters..."
    
    # Determine values based on mode
    local rt_runtime rt_period
    
    case "$MODE" in
        "prod")
            rt_runtime=950000  # 95% CPU for RT
            rt_period=1000000  # 1 second period
            ;;
        "test")
            rt_runtime=800000  # 80% CPU for RT (leaves 20% for GUI/debug)
            rt_period=1000000
            ;;
        "light")
            rt_runtime=600000  # 60% CPU for RT (for heavy debug environments)
            rt_period=1000000
            ;;
        *)
            rt_runtime=950000
            rt_period=1000000
            warn "Unknown mode: $MODE, using default (prod)"
            ;;
    esac
    
    log "Mode: $MODE - RT Runtime: ${rt_runtime}μs, RT Period: ${rt_period}μs"
    
    # Verify if the configuration file already exists
    if [[ -f "$RT_CONFIG_FILE" ]]; then
        log "RT configuration file already exists: $RT_CONFIG_FILE"
        log "Skipping file creation (requires root privileges)"
    else
        # Create configuration file only if it doesn't exist
        local config_content="# OLMS Real-Time Kernel Parameters
kernel.sched_rt_runtime_us = $rt_runtime
kernel.sched_rt_period_us = $rt_period
kernel.sched_migration_cost_ns = 500000
kernel.sched_wakeup_granularity_ns = $(id -u)000"
        
        safe_write_file "$config_content" "$RT_CONFIG_FILE"
    fi
    
    # Apply configuration if file exists
    if [[ -f "$RT_CONFIG_FILE" ]]; then
        log "DEBUG: Applying RT kernel parameters configuration..."
        # Apply kernel parameters, ignoring errors for optional parameters
        sudo sysctl -p "$RT_CONFIG_FILE" 2>/dev/null || true
        
        # Verify that the main parameters have been applied correctly
        local current_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
        local current_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "0")
        log "DEBUG: current_runtime=$current_runtime, current_period=$current_period"
        log "DEBUG: rt_runtime=$rt_runtime, rt_period=$rt_period"
        
        if [[ "$current_runtime" == "$rt_runtime" ]] && [[ "$current_period" == "$rt_period" ]]; then
            log "RT kernel parameters applied successfully"
        else
            warn "Unable to apply RT kernel parameters"
            warn "Verify that parameters are already applied or run: sudo sysctl -p $RT_CONFIG_FILE"
        fi
    else
        warn "RT configuration file not found, unable to apply parameters"
    fi
    
    # Verify application
    local current_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
    local current_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "0")
    log "DEBUG: Final verification - current_runtime=$current_runtime, current_period=$current_period"
    log "DEBUG: Final verification - rt_runtime=$rt_runtime, rt_period=$rt_period"
    
    if [[ "$current_runtime" == "$rt_runtime" ]] && [[ "$current_period" == "$rt_period" ]]; then
        log "Kernel parameters verified: runtime=$current_runtime, period=$current_period"
    else
        warn "Kernel parameters not matching: runtime=$current_runtime, period=$current_period"
    fi
}

# Configure CPU governor
configure_cpu_governor() {
    log "Configuring CPU governor for performance (forced mode)..."
    
    local num_cores=$(nproc)
    log "Detected cores: $num_cores"
    
    # 1. First of all, let's make sure sysfs permissions are correct
    log "Verifying and applying sysfs permissions..."
    ensure_sysfs_permissions
    
    # 2. Try to disable Intel hardware power saving if present
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        if echo "0" > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null; then
            log "Turbo Boost disabled successfully"
        else
            warn "Unable to disable Turbo Boost (insufficient permissions)"
        fi
    fi

    # 3. Apply 'performance' to each available core
    # We use an approach that bypasses potential individual write errors
    local success_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            
            # Verify if the file is writable
            if [[ -w "$governor_file" ]]; then
                # Try to write performance
                if echo "performance" > "$governor_file"; then
                    log "CPU $i: governor set to 'performance'"
                    success_count=$((success_count + 1))
                else
                    warn "Unable to write to $governor_file"
                fi
            else
                warn "CPU $i: governor file not writable (permissions: $(stat -c '%a' "$governor_file" 2>/dev/null || echo 'N/A'))"
            fi
        else
            warn "Governor file not found for CPU $i"
        fi
    done
    
    # 4. Force minimum frequency to maximum possible (for intel_pstate driver)
    for i in $(seq 0 $((num_cores - 1))); do
        local min_freq="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_min_freq"
        local max_freq="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_max_freq"
        
        if [ -f "$max_freq" ] && [ -f "$min_freq" ]; then
            cat "$max_freq" > "$min_freq" 2>&1 || true
        fi
    done
    
    # Verify setting of all governors
    log "Verifying governor status for all CPUs..."
    local all_performance=true
    local failed_cpus=()
    
    for i in $(seq 0 $((num_cores - 1))); do
        local gov=$(cat "/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor" 2>/dev/null || echo "unknown")
        if [[ "$gov" != "performance" ]]; then
            all_performance=false
            failed_cpus+=("$i:$gov")
            warn "CPU $i: governor=$gov (expected performance)"
        fi
    done
    
    if [[ "$all_performance" == "true" ]]; then
        log "All governors set correctly to performance"
    else
        warn "Some governors are not in performance mode"
        warn "Problem CPUs: ${failed_cpus[*]}"
    fi
    
    log "CPU governor configuration: $success_count/$total_count cores configured"
}

# Configure power management
configure_power_management() {
    log "Configuring power management..."
    
    # Verify irqbalance status (without attempting to modify it)
    log "Verifying irqbalance status..."
    if systemctl is-active --quiet irqbalance 2>/dev/null; then
        warn "irqbalance is active (may cause audio jitter)"
        warn "To disable it: sudo systemctl stop irqbalance && sudo systemctl disable irqbalance"
    else
        log "irqbalance is disabled (correct for RT audio)"
    fi
    
    # Configure C-states (disable via sysfs for systems without GRUB)
    log "Configuring C-states via sysfs..."
    disable_cstates
}

# Function to disable problematic C-states via sysfs
disable_cstates() {
    log "Disabling problematic C-states for real-time audio..."
    
    local num_cores=$(nproc)
    local disabled_states=0
    
    # Disable C3 and C6 for all cores (most problematic for latency)
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        # Disable C3 state (if present)
        if [[ -f "${cpu_path}/state3/disable" ]]; then
            if echo 1 > "${cpu_path}/state3/disable" 2>/dev/null; then
                log "C3 state disabled for CPU $i"
                disabled_states=$((disabled_states + 1))
            else
                warn "Unable to disable C3 state for CPU $i (permissions)"
            fi
        fi
        
        # Disable C6 state (if present)
        if [[ -f "${cpu_path}/state4/disable" ]]; then
            if echo 1 > "${cpu_path}/state4/disable" 2>/dev/null; then
                log "C6 state disabled for CPU $i"
                disabled_states=$((disabled_states + 1))
            else
                warn "Unable to disable C6 state for CPU $i (permissions)"
            fi
        fi
    done
    
    if [[ $disabled_states -gt 0 ]]; then
        log "C-states disabled successfully: $disabled_states states"
    else
        warn "No C-states disabled (may already be configured or missing permissions)"
    fi
}

# Ensure sysfs permissions are correct
ensure_sysfs_permissions() {
    log "Ensuring correct sysfs permissions..."
    
    # Get the user's primary group
    local user_group=$(id -gn "$(whoami)")
    
    # Sysfs files for CPU governor and frequencies
    local cpu_files=(
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/intel_pstate/no_turbo"
    )
    
    # Sysfs files for C-states
    local cstate_files=(
        "/sys/devices/system/cpu/cpu0/cpuidle/state3/disable"
        "/sys/devices/system/cpu/cpu0/cpuidle/state4/disable"
        "/sys/devices/system/cpu/cpu1/cpuidle/state3/disable"
        "/sys/devices/system/cpu/cpu1/cpuidle/state4/disable"
        "/sys/devices/system/cpu/cpu2/cpuidle/state3/disable"
        "/sys/devices/system/cpu/cpu2/cpuidle/state4/disable"
        "/sys/devices/system/cpu/cpu3/cpuidle/state3/disable"
        "/sys/devices/system/cpu/cpu3/cpuidle/state4/disable"
    )
    
    local applied_count=0
    local total_count=0
    
    # Apply permissions to CPU files
    for file in "${cpu_files[@]}"; do
        if [[ -f "$file" ]]; then
            total_count=$((total_count + 1))
            local current_perms=$(stat -c "%a" "$file" 2>/dev/null || echo "0")
            local current_owner=$(stat -c "%U:%G" "$file" 2>/dev/null || echo "unknown:unknown")
            
            # If permissions are not correct, apply them
            if [[ "$current_perms" != "666" ]] || [[ "$current_owner" != "$(whoami):$user_group" ]]; then
                if chmod 666 "$file" 2>/dev/null && chown "$(whoami):$user_group" "$file" 2>/dev/null; then
                    log "Permissions applied to $file (666, $(whoami):$user_group)"
                    applied_count=$((applied_count + 1))
                else
                    warn "Unable to apply permissions to $file (permissions: $current_perms, owner: $current_owner)"
                fi
            else
                log "Permissions already correct for $file"
                applied_count=$((applied_count + 1))
            fi
        fi
    done
    
    # Apply permissions to C-state files
    for file in "${cstate_files[@]}"; do
        if [[ -f "$file" ]]; then
            total_count=$((total_count + 1))
            local current_perms=$(stat -c "%a" "$file" 2>/dev/null || echo "0")
            local current_owner=$(stat -c "%U:%G" "$file" 2>/dev/null || echo "unknown:unknown")
            
            # If permissions are not correct, apply them
            if [[ "$current_perms" != "666" ]] || [[ "$current_owner" != "$(whoami):$user_group" ]]; then
                if chmod 666 "$file" 2>/dev/null && chown "$(whoami):$user_group" "$file" 2>/dev/null; then
                    log "Permissions applied to $file (666, $(whoami):$user_group)"
                    applied_count=$((applied_count + 1))
                else
                    warn "Unable to apply permissions to $file (permissions: $current_perms, owner: $current_owner)"
                fi
            else
                log "Permissions already correct for $file"
                applied_count=$((applied_count + 1))
            fi
        fi
    done
    
    log "Sysfs permissions verified/applied: $applied_count/$total_count"
    
    # If not all permissions have been applied, try to run the Runtime Permission Manager
    if [[ $applied_count -lt $total_count ]]; then
        log "Some permissions were not applied, attempting with Runtime Permission Manager..."
        if [[ -x "/usr/local/bin/olms-runtime-permissions" ]]; then
            sudo /usr/local/bin/olms-runtime-permissions
            log "Runtime Permission Manager executed"
        else
            warn "Runtime Permission Manager not found or not executable"
        fi
    fi
}

# Configure memory locking and realtime privileges
configure_realtime_privileges() {
    log "Configuring memory locking and realtime privileges..."
    
    # Verify if the limits file already exists
    if [[ -f "$LIMITS_FILE" ]]; then
        log "Limits file already exists: $LIMITS_FILE"
        log "Skipping file creation (requires root privileges)"
    else
        # Create realtime limits file only if it doesn't exist
        local limits_content="# OLMS Real-Time User Limits
@realtime soft rtprio 99
@realtime hard rtprio 99
@realtime soft memlock unlimited
@realtime hard memlock unlimited
@audio soft rtprio 99
@audio hard rtprio 99
@audio soft memlock unlimited
@audio hard memlock unlimited"
        
        safe_write_file "$limits_content" "$LIMITS_FILE"
    fi
    
    log "Limits file verified: $LIMITS_FILE"
    
    # Verify current limits
    local current_rtprio=$(ulimit -r 2>/dev/null || echo "0")
    local current_memlock=$(ulimit -l 2>/dev/null || echo "0")
    
    log "Current limits: rtprio=$current_rtprio, memlock=${current_memlock}KB"
    
    # Verify group membership
    local current_user=$(whoami)
    if groups "$current_user" | grep -q "realtime"; then
        log "User $current_user belongs to the 'realtime' group"
    else
        warn "User $current_user does NOT belong to the 'realtime' group"
    fi
    
    if groups "$current_user" | grep -q "audio"; then
        log "User $current_user belongs to the 'audio' group"
    else
        warn "User $current_user does NOT belong to the 'audio' group"
    fi
}

# Verify RT configuration
verify_rt_configuration() {
    log "Final verification..."
    
    # Verify CPU governor
    local gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
    [[ "$gov" == "performance" ]] && log "Governor: OK ($gov)" || error "Governor: FAIL ($gov)"
    
    # Verify user limits
    local rtprio=$(ulimit -r)
    [[ "$rtprio" -eq 99 ]] && log "RT Prio: OK ($rtprio)" || warn "RT Prio: $rtprio (requires session restart)"
    
    # Verify irqbalance
    if ! systemctl is-active --quiet irqbalance 2>/dev/null; then
        log "irqbalance: disabled (correct for RT audio)"
    else
        warn "irqbalance: active (may cause jitter)"
    fi
}

# Main function
main() {
    log "=== PHASE 1: REAL-TIME SYSTEM OPTIMIZATION ==="
    info "Mode: $MODE (prod=95%, test=80%, light=60%)"
    
    configure_kernel_parameters
    configure_cpu_governor
    configure_power_management
    configure_realtime_privileges
    verify_rt_configuration
    
    log "Real-time system optimization completed"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
