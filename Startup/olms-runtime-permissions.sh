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

# OLMS Runtime Permission Manager
# Manages sysfs permissions in real-time for any Linux user
# Version: 1.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# User and system detection
detect_user_environment() {
    # Intelligent home path management to handle sudo execution
    if [[ "$EUID" -eq 0 ]]; then
        # If we are root, we need to determine the actual user
        if [[ -n "${SUDO_USER:-}" ]]; then
            # Executed with sudo, use original user
            ACTUAL_USER="$SUDO_USER"
            ACTUAL_HOME=$(eval echo ~$SUDO_USER)
        elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
            # Executed as root but USER is set to a non-root user
            ACTUAL_USER="$USER"
            ACTUAL_HOME=$(eval echo ~$USER)
        else
            # Executed directly as root
            ACTUAL_USER="root"
            ACTUAL_HOME="/root"
        fi
    else
        # Executed as normal user
        ACTUAL_USER="$(whoami)"
        ACTUAL_HOME="$HOME"
    fi
    
    ACTUAL_UID=$(id -u "$ACTUAL_USER")
    ACTUAL_GID=$(id -g "$ACTUAL_USER")
    
    # Get user's primary group
    USER_GROUP=$(id -gn "$ACTUAL_USER")
    
    log "User environment detected:"
    log "  User: $ACTUAL_USER"
    log "  UID: $ACTUAL_UID"
    log "  GID: $ACTUAL_GID"
    log "  Group: $USER_GROUP"
    log "  Home: $ACTUAL_HOME"
    
    # Verify that the user exists and has necessary permissions
    if ! id "$ACTUAL_USER" >/dev/null 2>&1; then
        error "User $ACTUAL_USER does not exist"
        exit 1
    fi
    
    # Verify that the user has a home directory
    if [[ ! -d "$ACTUAL_HOME" ]]; then
        warn "Home directory $ACTUAL_HOME does not exist"
        return 1
    fi
}

# Apply sysfs permissions for CPU/Governor
apply_cpu_permissions() {
    log "Applying sysfs permissions for CPU/Governor..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    log "Detected cores: $num_cores"
    
    local applied_count=0
    local total_count=0
    
    # Sysfs files for CPU governor and frequencies
    local cpu_files=(
        "scaling_governor"
        "scaling_min_freq"
        "scaling_max_freq"
        "scaling_setspeed"
        "scaling_cur_freq"
    )
    
    # Sysfs files for Turbo Boost
    local turbo_files=(
        "no_turbo"
    )
    
    # Apply permissions for each core
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpufreq"
        
        # Verify that the directory exists
        if [[ ! -d "$cpu_path" ]]; then
            warn "CPU $i: directory $cpu_path does not exist (may be offline)"
            continue
        fi
        
        # Apply permissions to CPU files
        for file in "${cpu_files[@]}"; do
            local target_file="$cpu_path/$file"
            if [[ -f "$target_file" ]]; then
                total_count=$((total_count + 1))
                if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                    log "CPU $i: permissions applied to $file"
                    applied_count=$((applied_count + 1))
                else
                    warn "CPU $i: unable to apply permissions to $file"
                fi
            fi
        done
    done
    
    # Apply permissions for Turbo Boost (if present)
    for file in "${turbo_files[@]}"; do
        local target_file="/sys/devices/system/cpu/intel_pstate/$file"
        if [[ -f "$target_file" ]]; then
            total_count=$((total_count + 1))
            if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                log "Turbo Boost: permissions applied to $file"
                applied_count=$((applied_count + 1))
            else
                warn "Turbo Boost: unable to apply permissions to $file"
            fi
        fi
    done
    
    log "CPU permissions applied: $applied_count/$total_count"
    
    # Verify application
    verify_cpu_permissions
}

# Apply sysfs permissions for C-states
apply_cstate_permissions() {
    log "Applying sysfs permissions for C-states..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local applied_count=0
    local total_count=0
    
    # C-states to disable (C3, C6 are most problematic for latency)
    local cstates=("state3" "state4")
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        # Verify that the directory exists
        if [[ ! -d "$cpu_path" ]]; then
            warn "CPU $i: cpuidle directory does not exist"
            continue
        fi
        
        # Apply permissions to C-states files
        for cstate in "${cstates[@]}"; do
            local disable_file="$cpu_path/$cstate/disable"
            local name_file="$cpu_path/$cstate/name"
            
            if [[ -f "$disable_file" ]]; then
                total_count=$((total_count + 1))
                if chmod 666 "$disable_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$disable_file" 2>/dev/null; then
                    log "CPU $i: permissions applied to $cstate/disable"
                    applied_count=$((applied_count + 1))
                else
                    warn "CPU $i: unable to apply permissions to $cstate/disable"
                fi
            fi
            
            if [[ -f "$name_file" ]]; then
                total_count=$((total_count + 1))
                if chmod 666 "$name_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$name_file" 2>/dev/null; then
                    log "CPU $i: permissions applied to $cstate/name"
                    applied_count=$((applied_count + 1))
                else
                    warn "CPU $i: unable to apply permissions to $cstate/name"
                fi
            fi
        done
    done
    
    log "C-states permissions applied: $applied_count/$total_count"
    
    # Verify application
    verify_cstate_permissions
}

# Apply sysfs permissions for IRQ
apply_irq_permissions() {
    log "Applying sysfs permissions for IRQ..."
    
    local applied_count=0
    local total_count=0
    
    # Sysfs files for IRQ
    local irq_files=(
        "smp_affinity"
        "smp_affinity_list"
        "affinity_hint"
    )
    
    # Find all available IRQs
    if [[ -d "/proc/irq" ]]; then
        for irq_dir in /proc/irq/*/; do
            if [[ -d "$irq_dir" ]]; then
                local irq_num=$(basename "$irq_dir")
                
                # Apply permissions to IRQ files
                for file in "${irq_files[@]}"; do
                    local target_file="/proc/irq/$irq_num/$file"
                    if [[ -f "$target_file" ]]; then
                        total_count=$((total_count + 1))
                        if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                            log "IRQ $irq_num: permissions applied to $file"
                            applied_count=$((applied_count + 1))
                        else
                            warn "IRQ $irq_num: unable to apply permissions to $file"
                        fi
                    fi
                done
            fi
        done
    fi
    
    log "IRQ permissions applied: $applied_count/$total_count"
    
    # Verify application
    verify_irq_permissions
}

# Verify CPU permissions
verify_cpu_permissions() {
    log "Verifying CPU permissions..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local verified_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            local perms=$(stat -c "%a" "$governor_file" 2>/dev/null || echo "0")
            local owner=$(stat -c "%U:%G" "$governor_file" 2>/dev/null || echo "unknown:unknown")
            
            if [[ "$perms" == "666" ]] && [[ "$owner" == "$ACTUAL_USER:$USER_GROUP" ]]; then
                log "CPU $i: permissions verified (666, $owner)"
                verified_count=$((verified_count + 1))
            else
                warn "CPU $i: incorrect permissions (perms=$perms, owner=$owner)"
            fi
        fi
    done
    
    log "CPU verification completed: $verified_count/$total_count correct"
}

# Verify C-states permissions
verify_cstate_permissions() {
    log "Verifying C-states permissions..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local verified_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            for state in state3 state4; do
                local disable_file="$cpu_path/$state/disable"
                
                if [[ -f "$disable_file" ]]; then
                    total_count=$((total_count + 1))
                    local perms=$(stat -c "%a" "$disable_file" 2>/dev/null || echo "0")
                    local owner=$(stat -c "%U:%G" "$disable_file" 2>/dev/null || echo "unknown:unknown")
                    
                    if [[ "$perms" == "666" ]] && [[ "$owner" == "$ACTUAL_USER:$USER_GROUP" ]]; then
                        log "CPU $i $state: permissions verified (666, $owner)"
                        verified_count=$((verified_count + 1))
                    else
                        warn "CPU $i $state: incorrect permissions (perms=$perms, owner=$owner)"
                    fi
                fi
            done
        fi
    done
    
    log "C-states verification completed: $verified_count/$total_count correct"
}

# Verify IRQ permissions
verify_irq_permissions() {
    log "Verifying IRQ permissions..."
    
    local verified_count=0
    local total_count=0
    
    if [[ -d "/proc/irq" ]]; then
        for irq_dir in /proc/irq/*/; do
            if [[ -d "$irq_dir" ]]; then
                local irq_num=$(basename "$irq_dir")
                local affinity_file="/proc/irq/$irq_num/smp_affinity"
                
                if [[ -f "$affinity_file" ]]; then
                    total_count=$((total_count + 1))
                    local perms=$(stat -c "%a" "$affinity_file" 2>/dev/null || echo "0")
                    local owner=$(stat -c "%U:%G" "$affinity_file" 2>/dev/null || echo "unknown:unknown")
                    
                    if [[ "$perms" == "666" ]] && [[ "$owner" == "$ACTUAL_USER:$USER_GROUP" ]]; then
                        log "IRQ $irq_num: permissions verified (666, $owner)"
                        verified_count=$((verified_count + 1))
                    else
                        warn "IRQ $irq_num: incorrect permissions (perms=$perms, owner=$owner)"
                    fi
                fi
            fi
        done
    fi
    
    log "IRQ verification completed: $verified_count/$total_count correct"
}

# Force governor setting to performance
force_performance_governor() {
    log "Forcing governor to performance..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local success_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            # Verify if file is writable
            if [[ -w "$governor_file" ]]; then
                if echo "performance" > "$governor_file" 2>/dev/null; then
                    log "CPU $i: governor set to performance"
                    success_count=$((success_count + 1))
                else
                    warn "CPU $i: unable to set governor to performance"
                fi
            else
                warn "CPU $i: governor file not writable"
            fi
        fi
    done
    
    log "Performance governors set: $success_count cores"
}

# Force disabling problematic C-states
force_disable_cstates() {
    log "Forcing disabling of problematic C-states..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local disabled_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            # Disable C3 state (if present)
            if [[ -f "${cpu_path}/state3/disable" ]]; then
                if [[ -w "${cpu_path}/state3/disable" ]]; then
                    if echo 1 > "${cpu_path}/state3/disable" 2>/dev/null; then
                        log "CPU $i: C3 state disabled"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: unable to disable C3 state"
                    fi
                else
                    warn "CPU $i: C3 state file not writable"
                fi
            fi
            
            # Disable C6 state (if present)
            if [[ -f "${cpu_path}/state4/disable" ]]; then
                if [[ -w "${cpu_path}/state4/disable" ]]; then
                    if echo 1 > "${cpu_path}/state4/disable" 2>/dev/null; then
                        log "CPU $i: C6 state disabled"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: unable to disable C6 state"
                    fi
                else
                    warn "CPU $i: C6 state file not writable"
                fi
            fi
        fi
    done
    
    log "C-states disabled: $disabled_count states"
}

# Main function
main() {
    log "=== OLMS RUNTIME PERMISSION MANAGER ==="
    log "Real-time sysfs permissions management for any Linux user"
    
    # Verify that the script is executed as root (required for sysfs modifications)
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be executed as root to modify sysfs files"
        error "Run: sudo $0"
        exit 1
    fi
    
    detect_user_environment
    
    # Apply sysfs permissions
    apply_cpu_permissions
    apply_cstate_permissions
    apply_irq_permissions
    
    # Force RT settings
    force_performance_governor
    force_disable_cstates
    
    log "=== RUNTIME PERMISSION MANAGER COMPLETED ==="
    log "Sysfs permissions applied for user $ACTUAL_USER"
    log "System ready for real-time audio use"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
