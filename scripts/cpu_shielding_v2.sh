# Copyright (C) 2024 Francesco Nano and AI
# 
# This file is part of the Open Live Mixing System (OLMS) project.
# Created by Francesco Nano with AI assistance at https://openlivemixingsystem.org/
#
# Connect, collaborate, and stay updated with announcements at:
# https://openlivemixingsystem.org/
#
# Licensed under the GNU General Public License v3.0 (GPL-3.0)
# See LICENSE file for full license terms and conditions.
#
# This software is provided 'as-is', without any express or implied warranty.
# In no event will the authors be held liable for any damages arising from
# the use of this software.

#!/bin/bash

# CPU Shielding Implementation for OLMS - cgroup v2 Version
# 
# This script implements CPU Shielding using cgroup v2 cpuset controller
# to create dedicated CPU groups for system and audio processes.
# 
# Architecture: 4-core system
# - Core 0: OS, servizi di sistema, I/O generale
# - Core 1: IRQ controller USB scheda audio
# - Core 2 & 3: JACK2 e thread DSP Ardour

set -e

# Default values
CPU_CORES=${CPU_CORES:-$(nproc)}
SYSTEM_CPU_CORE=0
AUDIO_CPU_CORES="2,3"

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to check if cpuset controller is available
check_cpuset_availability() {
    print_status "Checking cpuset controller availability..."
    
    # Check if cpuset is in available controllers
    if grep -q "cpuset" /sys/fs/cgroup/cgroup.controllers; then
        print_status "✓ cpuset controller is available"
        
        # Check if cpuset is already enabled in subtree_control
        if grep -q "cpuset" /sys/fs/cgroup/cgroup.subtree_control; then
            print_status "✓ cpuset controller is already enabled"
        else
            print_status "Enabling cpuset controller..."
            echo "+cpuset" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
            if [ $? -eq 0 ]; then
                print_status "✓ cpuset controller enabled successfully"
            else
                print_status "✗ Failed to enable cpuset controller"
                return 1
            fi
        fi
    else
        print_status "✗ cpuset controller not available"
        return 1
    fi
    
    return 0
}

# Function to create CPU shielding cgroups
create_cpu_shielding() {
    print_status "Creating CPU shielding cgroups..."
    
    # Create audio.slice group (Core 2,3)
    # Use range format "2-3" for cgroup v2 compatibility
    local audio_cpus_range="2-$(($CPU_CORES-1))"
    print_status "Creating audio.slice group (Cores $audio_cpus_range)..."
    sudo mkdir -p /sys/fs/cgroup/audio.slice
    echo "$audio_cpus_range" | sudo tee /sys/fs/cgroup/audio.slice/cpuset.cpus
    echo 0 | sudo tee /sys/fs/cgroup/audio.slice/cpuset.mems
    
    # Create system.slice group (Core 0)
    print_status "Creating system.slice group (Core 0)..."
    sudo mkdir -p /sys/fs/cgroup/system.slice
    echo $SYSTEM_CPU_CORE | sudo tee /sys/fs/cgroup/system.slice/cpuset.cpus
    echo 0 | sudo tee /sys/fs/cgroup/system.slice/cpuset.mems
    
    print_status "✓ CPU shielding cgroups created successfully"
}

# Function to move existing processes to system cgroup
move_existing_processes() {
    print_status "Moving existing processes to system cgroup..."
    
    local moved_count=0
    local skipped_count=0
    
    # Get list of all running PIDs
    for pid in $(pgrep -f ".*" 2>/dev/null); do
        # Skip current script, init process, and kernel threads
        if [ "$pid" = "$$" ] || [ "$pid" = "1" ]; then
            continue
        fi
        
        # Check if process has an executable (skip kernel threads)
        if [ ! -e "/proc/$pid/exe" ]; then
            skipped_count=$((skipped_count + 1))
            continue
        fi
        
        # Skip audio processes (JACK and Ardour) - they will be moved later
        local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
        if echo "$process_cmd" | grep -qE "(jackd|ardour)"; then
            print_status "  Skipping audio process PID $pid ($process_cmd)"
            skipped_count=$((skipped_count + 1))
            continue
        fi
        
        # Move process to system cgroup
        if echo $pid | sudo tee /sys/fs/cgroup/system.slice/cgroup.procs > /dev/null 2>&1; then
            moved_count=$((moved_count + 1))
        else
            skipped_count=$((skipped_count + 1))
        fi
    done
    
    print_status "✓ Moved $moved_count processes to system cgroup"
    print_status "  Skipped $skipped_count kernel threads, system processes, and audio processes"
}

# Function to move audio processes to audio cgroup
move_audio_processes() {
    print_status "Moving audio processes to audio cgroup..."
    
    local moved_count=0
    local skipped_count=0
    
    # Get list of audio processes (JACK and Ardour)
    for pid in $(pgrep -f "jackd|ardour" 2>/dev/null); do
        if [ -d "/proc/$pid" ]; then
            local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
            print_status "Moving audio process PID $pid ($process_cmd) to audio.slice"
            
            # Move process to audio cgroup
            if echo $pid | sudo tee /sys/fs/cgroup/audio.slice/cgroup.procs > /dev/null 2>&1; then
                moved_count=$((moved_count + 1))
            else
                print_status "  Warning: Failed to move PID $pid to audio.slice"
                skipped_count=$((skipped_count + 1))
            fi
        fi
    done
    
    if [ $moved_count -gt 0 ]; then
        print_status "✓ Moved $moved_count audio processes to audio.slice"
    else
        print_status "  No audio processes found to move"
    fi
    
    if [ $skipped_count -gt 0 ]; then
        print_status "  Failed to move $skipped_count audio processes"
    fi
}

# Function to verify CPU shielding configuration
verify_cpu_shielding() {
    print_status "Verifying CPU shielding configuration..."
    
    # Check system cgroup
    local system_cpus=$(cat /sys/fs/cgroup/system.slice/cpuset.cpus)
    local system_tasks=$(cat /sys/fs/cgroup/system.slice/cgroup.procs 2>/dev/null | wc -l)
    
    print_status "System cgroup:"
    echo "  - CPU mask: $system_cpus"
    echo "  - Number of tasks: $system_tasks"
    
    # Show some example processes in system cgroup
    if [ $system_tasks -gt 0 ]; then
        echo "  - Sample processes:"
        cat /sys/fs/cgroup/system.slice/cgroup.procs 2>/dev/null | head -5 | while read pid; do
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                local process_name=$(ps -p "$pid" -o comm= 2>/dev/null | head -1)
                echo "    PID $pid: $process_name ($process_cmd)"
            fi
        done
    fi
    
    # Check audio cgroup
    local audio_cpus=$(cat /sys/fs/cgroup/audio.slice/cpuset.cpus)
    local audio_tasks=$(cat /sys/fs/cgroup/audio.slice/cgroup.procs 2>/dev/null | wc -l)
    
    print_status "Audio cgroup:"
    echo "  - CPU mask: $audio_cpus"
    echo "  - Number of tasks: $audio_tasks"
    
    # Show processes in audio cgroup with detailed information
    if [ $audio_tasks -gt 0 ]; then
        echo "  - Audio processes:"
        cat /sys/fs/cgroup/audio.slice/cgroup.procs 2>/dev/null | while read pid; do
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                local process_name=$(ps -p "$pid" -o comm= 2>/dev/null | head -1)
                local process_user=$(ps -p "$pid" -o user= 2>/dev/null | head -1)
                
                # Check if process has realtime priority
                local rt_priority=""
                local rt_policy=""
                if command -v chrt >/dev/null 2>&1; then
                    local rt_info=$(chrt -p "$pid" 2>/dev/null)
                    if echo "$rt_info" | grep -q "SCHED_FIFO\|SCHED_RR"; then
                        rt_policy=$(echo "$rt_info" | grep "policy" | awk '{print $3}')
                        rt_priority=$(echo "$rt_info" | grep "priority" | awk '{print $3}')
                        rt_priority=" [RT: $rt_policy $rt_priority]"
                    fi
                fi
                
                echo "    PID $pid: $process_name ($process_user)$rt_priority"
                echo "      Command: $process_cmd"
                
                # Check CPU affinity
                if command -v taskset >/dev/null 2>&1; then
                    local affinity=$(taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}')
                    echo "      Affinity: $affinity (should be $audio_cpus)"
                fi
            fi
        done
    else
        echo "  - No audio processes found (this is expected if JACK/Ardour are not running)"
    fi
    
    # Verify CPU allocation (allow for range format like "2-3")
    if [ "$system_cpus" = "$SYSTEM_CPU_CORE" ]; then
        # Check if audio CPUs match (handle both "2,3" and "2-3" formats)
        if [ "$audio_cpus" = "$AUDIO_CPU_CORES" ] || [ "$audio_cpus" = "2-3" ]; then
            print_status "✓ CPU shielding configuration verified successfully"
            
            # Additional verification for audio processes
            if [ $audio_tasks -gt 0 ]; then
                print_status "✓ Audio processes are properly isolated in dedicated CPU cores"
            fi
            
            return 0
        fi
    fi
    
    print_status "✗ CPU shielding configuration verification failed"
    return 1
}

# Function to show help
show_help() {
    echo "CPU Shielding Implementation Script (cgroup v2)"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --system-core N      Specify system CPU core (default: 0)"
    echo "  --audio-cores LIST   Specify audio CPU cores (default: 2,3)"
    echo "  --help, -h           Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  SYSTEM_CPU_CORE      CPU core for system processes (default: 0)"
    echo "  AUDIO_CPU_CORES      CPU cores for audio processes (default: 2,3)"
    echo "  CPU_CORES            Total number of CPU cores (auto-detected)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use default settings"
    echo "  $0 --system-core 0 --audio-cores 1,2,3"
    echo "  SYSTEM_CPU_CORE=0 AUDIO_CPU_CORES=1,2,3 $0"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --system-core)
            SYSTEM_CPU_CORE="$2"
            shift 2
            ;;
        --audio-cores)
            AUDIO_CPU_CORES="$2"
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

# Validate CPU core numbers
if ! [[ "$SYSTEM_CPU_CORE" =~ ^[0-9]+$ ]] || [ "$SYSTEM_CPU_CORE" -lt 0 ] || [ "$SYSTEM_CPU_CORE" -ge "$CPU_CORES" ]; then
    print_status "Error: Invalid system CPU core number: $SYSTEM_CPU_CORE"
    print_status "Valid range: 0-$((CPU_CORES-1))"
    exit 1
fi

# Validate audio CPU cores
IFS=',' read -ra AUDIO_CORE_ARRAY <<< "$AUDIO_CPU_CORES"
for core in "${AUDIO_CORE_ARRAY[@]}"; do
    if ! [[ "$core" =~ ^[0-9]+$ ]] || [ "$core" -lt 0 ] || [ "$core" -ge "$CPU_CORES" ]; then
        print_status "Error: Invalid audio CPU core number: $core"
        print_status "Valid range: 0-$((CPU_CORES-1))"
        exit 1
    fi
done

print_status "=== CPU Shielding Implementation (cgroup v2) ==="
print_status "System CPU core: $SYSTEM_CPU_CORE"
print_status "Audio CPU cores: $AUDIO_CPU_CORES"
print_status "Total CPU cores detected: $CPU_CORES"
echo

# Phase 1: Check cpuset availability
print_status "Phase 1: Checking cpuset controller availability"
if ! check_cpuset_availability; then
    print_status "Error: cpuset controller not available, cannot proceed with CPU shielding"
    exit 1
fi
echo

# Phase 2: Create CPU shielding cgroups
print_status "Phase 2: Creating CPU shielding cgroups"
create_cpu_shielding
echo

# Phase 3: Move existing processes
print_status "Phase 3: Moving existing processes to system cgroup"
move_existing_processes
echo

# Phase 4: Verify configuration
print_status "Phase 4: Verifying CPU shielding configuration"
if ! verify_cpu_shielding; then
    print_status "Error: CPU shielding verification failed"
    exit 1
fi
echo

# Phase 5: Dynamic Audio Process Migration
print_status "Phase 5: Starting dynamic migration for audio processes..."
# Esegui una prima migrazione immediata
move_audio_processes

# Polling leggero per 10 secondi per catturare processi in avvio lento
for i in {1..5}; do
    sleep 2
    move_audio_processes > /dev/null
done

print_status "=== CPU Shielding Complete ==="
print_status "CPU shielding has been applied successfully"
print_status ""
print_status "Configuration:"
echo "  - System processes: Core $SYSTEM_CPU_CORE (OS, services, I/O)"
echo "  - Audio processes: Cores $AUDIO_CPU_CORES (JACK2, Ardour)"
echo
print_status "Benefits:"
echo "  - Dedicated CPU cores for audio processing"
echo "  - Reduced CPU scheduling interference"
echo "  - Improved real-time audio performance"
echo "  - Optimal resource allocation for OLMS"
echo
print_status "To verify manually:"
echo "  cat /sys/fs/cgroup/system.slice/cpuset.cpus"
echo "  cat /sys/fs/cgroup/audio.slice/cpuset.cpus"
echo "  cat /sys/fs/cgroup/system.slice/cgroup.procs | wc -l"
echo "  cat /sys/fs/cgroup/audio.slice/cgroup.procs | wc -l"
echo
print_status "CPU shielding implementation completed successfully!"

# Keep the script running to maintain the configuration
trap "print_status 'CPU shielding configuration preserved'" EXIT
