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

# OLMS System Monitor
# Continuous monitoring and automatic restoration of sysfs permissions
# Version: 1.0

set -euo pipefail

# Importa le funzioni di gestione dei percorsi
source "$(dirname "${BASH_SOURCE[0]}")/olms-path-utils.sh"

# Inizializza i percorsi OLMS
init_olms_paths

# Configuration
OLMS_HOME="$HOME/.olms"
mkdir -p "$OLMS_HOME"
LOG_FILE="$OLMS_HOME/olms-system-monitor.log"
MONITOR_INTERVAL=30  # Seconds between checks
MAX_RETRIES=3        # Maximum retry attempts for restoration

# Environment variables for the "all as same user" approach
export TARGET_USER="$(whoami)"
export TARGET_UID=$(id -u "$(whoami)" 2>/dev/null || echo "$(id -u)")
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"

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
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
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
    
    log "User environment detected: $ACTUAL_USER (UID: $ACTUAL_UID, GID: $ACTUAL_GID, Group: $USER_GROUP)"
}

# Check CPU permissions
check_cpu_permissions() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local failed_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            local perms=$(stat -c "%a" "$governor_file" 2>/dev/null || echo "0")
            local owner=$(stat -c "%U:%G" "$governor_file" 2>/dev/null || echo "unknown:unknown")
            
            if [[ "$perms" != "666" ]] || [[ "$owner" != "$ACTUAL_USER:$USER_GROUP" ]]; then
                failed_count=$((failed_count + 1))
                warn "CPU $i: incorrect permissions (perms=$perms, owner=$owner)"
            fi
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Incorrect CPU permissions: $failed_count/$total_count"
        return 1
    else
        log "CPU permissions verified: $total_count correct"
        return 0
    fi
}

# Check C-states permissions
check_cstate_permissions() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local failed_count=0
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
                    
                    if [[ "$perms" != "666" ]] || [[ "$owner" != "$ACTUAL_USER:$USER_GROUP" ]]; then
                        failed_count=$((failed_count + 1))
                        warn "CPU $i $state: incorrect permissions (perms=$perms, owner=$owner)"
                    fi
                fi
            done
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Incorrect C-states permissions: $failed_count/$total_count"
        return 1
    else
        log "C-states permissions verified: $total_count correct"
        return 0
    fi
}

# Check IRQ permissions
check_irq_permissions() {
    local failed_count=0
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
                    
                    if [[ "$perms" != "666" ]] || [[ "$owner" != "$ACTUAL_USER:$USER_GROUP" ]]; then
                        failed_count=$((failed_count + 1))
                        warn "IRQ $irq_num: incorrect permissions (perms=$perms, owner=$owner)"
                    fi
                fi
            fi
        done
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Incorrect IRQ permissions: $failed_count/$total_count"
        return 1
    else
        log "IRQ permissions verified: $total_count correct"
        return 0
    fi
}

# Check governor status
check_governor_status() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local failed_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            local gov=$(cat "$governor_file" 2>/dev/null || echo "unknown")
            
            if [[ "$gov" != "performance" ]]; then
                failed_count=$((failed_count + 1))
                warn "CPU $i: governor=$gov (expected performance)"
            fi
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Incorrect governors: $failed_count/$total_count"
        return 1
    else
        log "Governors verified: $total_count in performance"
        return 0
    fi
}

# Check C-states status
check_cstate_status() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local disabled_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            for state in state3 state4; do
                local disable_file="$cpu_path/$state/disable"
                
                if [[ -f "$disable_file" ]]; then
                    total_count=$((total_count + 1))
                    local disabled=$(cat "$disable_file" 2>/dev/null || echo "0")
                    
                    if [[ "$disabled" == "1" ]]; then
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i $state: C-state not disabled (disabled=$disabled)"
                    fi
                fi
            done
        fi
    done
    
    if [[ $disabled_count -eq $total_count ]] && [[ $total_count -gt 0 ]]; then
        log "C-states verified: $total_count disabled"
        return 0
    else
        warn "C-states not correctly disabled: $disabled_count/$total_count"
        return 1
    fi
}

# Restore CPU permissions
restore_cpu_permissions() {
    log "Restoring CPU permissions..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local restored_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpufreq"
        
        if [[ -d "$cpu_path" ]]; then
            # Sysfs files for CPU governor and frequencies
            local cpu_files=(
                "scaling_governor"
                "scaling_min_freq"
                "scaling_max_freq"
                "scaling_setspeed"
                "scaling_cur_freq"
            )
            
            for file in "${cpu_files[@]}"; do
                local target_file="$cpu_path/$file"
                if [[ -f "$target_file" ]]; then
                    total_count=$((total_count + 1))
                    if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                        log "CPU $i: permissions restored for $file"
                        restored_count=$((restored_count + 1))
                    else
                        warn "CPU $i: unable to restore permissions for $file"
                    fi
                fi
            done
        fi
    done
    
    # Restore Turbo Boost permissions
    local turbo_files=(
        "no_turbo"
    )
    
    for file in "${turbo_files[@]}"; do
        local target_file="/sys/devices/system/cpu/intel_pstate/$file"
        if [[ -f "$target_file" ]]; then
            total_count=$((total_count + 1))
            if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                log "Turbo Boost: permissions restored for $file"
                restored_count=$((restored_count + 1))
            else
                warn "Turbo Boost: unable to restore permissions for $file"
            fi
        fi
    done
    
    log "CPU permissions restoration completed: $restored_count/$total_count"
    return $((total_count - restored_count))
}

# Restore C-states permissions
restore_cstate_permissions() {
    log "Restoring C-states permissions..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local restored_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            # C-states to disable (C3, C6 are most problematic for latency)
            local cstates=("state3" "state4")
            
            for cstate in "${cstates[@]}"; do
                local disable_file="$cpu_path/$cstate/disable"
                local name_file="$cpu_path/$cstate/name"
                
                if [[ -f "$disable_file" ]]; then
                    total_count=$((total_count + 1))
                    if chmod 666 "$disable_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$disable_file" 2>/dev/null; then
                        log "CPU $i: permissions restored for $cstate/disable"
                        restored_count=$((restored_count + 1))
                    else
                        warn "CPU $i: unable to restore permissions for $cstate/disable"
                    fi
                fi
                
                if [[ -f "$name_file" ]]; then
                    total_count=$((total_count + 1))
                    if chmod 666 "$name_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$name_file" 2>/dev/null; then
                        log "CPU $i: permissions restored for $cstate/name"
                        restored_count=$((restored_count + 1))
                    else
                        warn "CPU $i: unable to restore permissions for $cstate/name"
                    fi
                fi
            done
        fi
    done
    
    log "C-states permissions restoration completed: $restored_count/$total_count"
    return $((total_count - restored_count))
}

# Restore IRQ permissions
restore_irq_permissions() {
    log "Restoring IRQ permissions..."
    
    local restored_count=0
    local total_count=0
    
    if [[ -d "/proc/irq" ]]; then
        for irq_dir in /proc/irq/*/; do
            if [[ -d "$irq_dir" ]]; then
                local irq_num=$(basename "$irq_dir")
                
                # Sysfs files for IRQ
                local irq_files=(
                    "smp_affinity"
                    "smp_affinity_list"
                    "affinity_hint"
                )
                
                for file in "${irq_files[@]}"; do
                    local target_file="/proc/irq/$irq_num/$file"
                    if [[ -f "$target_file" ]]; then
                        total_count=$((total_count + 1))
                        if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                            log "IRQ $irq_num: permissions restored for $file"
                            restored_count=$((restored_count + 1))
                        else
                            warn "IRQ $irq_num: unable to restore permissions for $file"
                        fi
                    fi
                done
            fi
        done
    fi
    
    log "IRQ permissions restoration completed: $restored_count/$total_count"
    return $((total_count - restored_count))
}

# Restore governor to performance
restore_governor_performance() {
    log "Restoring governor to performance..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local restored_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            # Verify if file is writable
            if [[ -w "$governor_file" ]]; then
                if echo "performance" > "$governor_file" 2>/dev/null; then
                    log "CPU $i: governor restored to performance"
                    restored_count=$((restored_count + 1))
                else
                    warn "CPU $i: unable to restore governor to performance"
                fi
            else
                warn "CPU $i: governor file not writable"
            fi
        fi
    done
    
    log "Governor restoration completed: $restored_count cores"
    return $((num_cores - restored_count))
}

# Restore C-states disabled
restore_cstates_disabled() {
    log "Restoring C-states disabled..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local disabled_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            # Disable C3 state (if present)
            if [[ -f "${cpu_path}/state3/disable" ]]; then
                if [[ -w "${cpu_path}/state3/disable" ]]; then
                    if echo 1 > "${cpu_path}/state3/disable" 2>/dev/null; then
                        log "CPU $i: C3 state restored disabled"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: unable to restore C3 state disabled"
                    fi
                else
                    warn "CPU $i: C3 state file not writable"
                fi
            fi
            
            # Disable C6 state (if present)
            if [[ -f "${cpu_path}/state4/disable" ]]; then
                if [[ -w "${cpu_path}/state4/disable" ]]; then
                    if echo 1 > "${cpu_path}/state4/disable" 2>/dev/null; then
                        log "CPU $i: C6 state restored disabled"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: unable to restore C6 state disabled"
                    fi
                else
                    warn "CPU $i: C6 state file not writable"
                fi
            fi
        fi
    done
    
    log "C-states restoration completed: $disabled_count states"
    return 0
}

# Complete restoration via Runtime Permission Manager
restore_via_runtime_manager() {
    log "Complete restoration via Runtime Permission Manager..."
    
    if [[ -x "/usr/local/bin/olms-runtime-permissions" ]]; then
        sudo /usr/local/bin/olms-runtime-permissions
        log "Runtime Permission Manager executed for complete restoration"
        return 0
    else
        warn "Runtime Permission Manager not found or not executable"
        return 1
    fi
}

# Continuous monitoring
monitor_system() {
    log "=== OLMS SYSTEM MONITOR ==="
    log "Continuous monitoring of sysfs permissions and RT status"
    log "Check interval: ${MONITOR_INTERVAL} seconds"
    
    local check_count=0
    
    while true; do
        check_count=$((check_count + 1))
        log "Check #$check_count"
        
        # Check permissions
        local cpu_ok=true
        local cstate_ok=true
        local irq_ok=true
        local governor_ok=true
        local cstate_status_ok=true
        
        # Check CPU permissions
        if ! check_cpu_permissions; then
            cpu_ok=false
        fi
        
        # Check C-states permissions
        if ! check_cstate_permissions; then
            cstate_ok=false
        fi
        
        # Check IRQ permissions
        if ! check_irq_permissions; then
            irq_ok=false
        fi
        
        # Check governor status
        if ! check_governor_status; then
            governor_ok=false
        fi
        
        # Check C-states status
        if ! check_cstate_status; then
            cstate_status_ok=false
        fi
        
        # Restoration if needed
        local restore_needed=false
        
        if [[ "$cpu_ok" == "false" ]] || [[ "$cstate_ok" == "false" ]] || [[ "$irq_ok" == "false" ]]; then
            warn "Incorrect sysfs permissions, attempting restoration..."
            restore_via_runtime_manager
            restore_needed=true
        fi
        
        if [[ "$governor_ok" == "false" ]]; then
            warn "Incorrect governors, attempting restoration..."
            restore_governor_performance
            restore_needed=true
        fi
        
        if [[ "$cstate_status_ok" == "false" ]]; then
            warn "C-states not correctly disabled, attempting restoration..."
            restore_cstates_disabled
            restore_needed=true
        fi
        
        if [[ "$restore_needed" == "true" ]]; then
            log "Restoration completed, new verification in progress..."
            
            # New verification after restoration
            sleep 2
            
            local retry_count=0
            local all_ok=false
            
            while [[ $retry_count -lt $MAX_RETRIES ]] && [[ "$all_ok" == "false" ]]; do
                retry_count=$((retry_count + 1))
                log "Post-restoration verification (attempt $retry_count/$MAX_RETRIES)"
                
                cpu_ok=true
                cstate_ok=true
                irq_ok=true
                governor_ok=true
                cstate_status_ok=true
                
                if ! check_cpu_permissions; then cpu_ok=false; fi
                if ! check_cstate_permissions; then cstate_ok=false; fi
                if ! check_irq_permissions; then irq_ok=false; fi
                if ! check_governor_status; then governor_ok=false; fi
                if ! check_cstate_status; then cstate_status_ok=false; fi
                
                if [[ "$cpu_ok" == "true" ]] && [[ "$cstate_ok" == "true" ]] && [[ "$irq_ok" == "true" ]] && [[ "$governor_ok" == "true" ]] && [[ "$cstate_status_ok" == "true" ]]; then
                    all_ok=true
                    log "Post-restoration verification: OK"
                else
                    warn "Post-restoration verification: FAILED, new attempt..."
                    restore_via_runtime_manager
                    restore_governor_performance
                    restore_cstates_disabled
                    sleep 2
                fi
            done
            
            if [[ "$all_ok" == "false" ]]; then
                error "Post-restoration verification: FAILED after $MAX_RETRIES attempts"
                error "Manually check sysfs permissions"
            fi
        else
            log "All OK, no restoration needed"
        fi
        
        log "Check #$check_count completed"
        log "Next check in ${MONITOR_INTERVAL} seconds..."
        sleep "$MONITOR_INTERVAL"
    done
}

# Main function
main() {
    log "=== OLMS SYSTEM MONITOR ==="
    log "Continuous monitoring and automatic restoration of sysfs permissions"
    
    # Verify that the script is executed as root (required for sysfs modifications)
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be executed as root to modify sysfs files"
        error "Run: sudo $0"
        exit 1
    fi
    
    detect_user_environment
    monitor_system
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
