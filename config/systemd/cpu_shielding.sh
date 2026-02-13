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

# CPU Shielding Implementation for OLMS
# 
# This script implements CPU Shielding using cpuset to create dedicated
# CPU groups for system and audio processes, ensuring optimal real-time
# audio performance by preventing CPU scheduling interference.
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

# Function to check if cpuset is available
check_cpuset_availability() {
    print_status "Checking cpuset availability..."
    
    # Check if cgroup cpuset is mounted
    if [ ! -d "/sys/fs/cgroup/cpuset" ]; then
        print_status "Mounting cpuset filesystem..."
        sudo mount -t cgroup -o cpuset cpuset /sys/fs/cgroup/cpuset
        if [ $? -eq 0 ]; then
            print_status "✓ cpuset filesystem mounted successfully"
        else
            print_status "✗ Failed to mount cpuset filesystem"
            return 1
        fi
    else
        print_status "✓ cpuset filesystem already mounted"
    fi
    
    return 0
}

# Function to create CPU shielding cpuset
create_cpu_shielding() {
    print_status "Creating CPU shielding cpuset..."
    
    # Create system cpuset (Core 0)
    print_status "Creating system cpuset (Core 0)..."
    sudo mkdir -p /sys/fs/cgroup/cpuset/system
    echo $SYSTEM_CPU_CORE | sudo tee /sys/fs/cgroup/cpuset/system/cpuset.cpus
    echo 0 | sudo tee /sys/fs/cgroup/cpuset/system/cpuset.mems
    
    # Create audio cpuset (Core 2,3)
    print_status "Creating audio cpuset (Core 2,3)..."
    sudo mkdir -p /sys/fs/cgroup/cpuset/audio
    echo "$AUDIO_CPU_CORES" | sudo tee /sys/fs/cgroup/cpuset/audio/cpuset.cpus
    echo 0 | sudo tee /sys/fs/cgroup/cpuset/audio/cpuset.mems
    
    print_status "✓ CPU shielding cpuset created successfully"
}

# Function to move existing processes to system cpuset
move_existing_processes() {
    print_status "Moving existing processes to system cpuset..."
    
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
        
        # Move process to system cpuset
        if echo $pid | sudo tee /sys/fs/cgroup/cpuset/system/tasks > /dev/null 2>&1; then
            moved_count=$((moved_count + 1))
        else
            skipped_count=$((skipped_count + 1))
        fi
    done
    
    print_status "✓ Moved $moved_count processes to system cpuset"
    print_status "  Skipped $skipped_count kernel threads and system processes"
}

# Function to verify CPU shielding configuration
verify_cpu_shielding() {
    print_status "Verifying CPU shielding configuration..."
    
    # Check system cpuset
    local system_cpus=$(cat /sys/fs/cgroup/cpuset/system/cpuset.cpus)
    local system_tasks=$(cat /sys/fs/cgroup/cpuset/system/tasks | wc -l)
    
    print_status "System cpuset:"
    echo "  - CPU mask: $system_cpus"
    echo "  - Number of tasks: $system_tasks"
    
    # Check audio cpuset
    local audio_cpus=$(cat /sys/fs/cgroup/cpuset/audio/cpuset.cpus)
    local audio_tasks=$(cat /sys/fs/cgroup/cpuset/audio/tasks | wc -l)
    
    print_status "Audio cpuset:"
    echo "  - CPU mask: $audio_cpus"
    echo "  - Number of tasks: $audio_tasks"
    
    # Verify CPU allocation
    if [ "$system_cpus" = "$SYSTEM_CPU_CORE" ] && [ "$audio_cpus" = "$AUDIO_CPU_CORES" ]; then
        print_status "✓ CPU shielding configuration verified successfully"
        return 0
    else
        print_status "✗ CPU shielding configuration verification failed"
        return 1
    fi
}

# Function to show help
show_help() {
    echo "CPU Shielding Implementation Script"
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

print_status "=== CPU Shielding Implementation ==="
print_status "System CPU core: $SYSTEM_CPU_CORE"
print_status "Audio CPU cores: $AUDIO_CPU_CORES"
print_status "Total CPU cores detected: $CPU_CORES"
echo

# Phase 1: Check cpuset availability
print_status "Phase 1: Checking cpuset availability"
if ! check_cpuset_availability; then
    print_status "Error: cpuset not available, cannot proceed with CPU shielding"
    exit 1
fi
echo

# Phase 2: Create CPU shielding cpuset
print_status "Phase 2: Creating CPU shielding cpuset"
create_cpu_shielding
echo

# Phase 3: Move existing processes
print_status "Phase 3: Moving existing processes to system cpuset"
move_existing_processes
echo

# Phase 4: Verify configuration
print_status "Phase 4: Verifying CPU shielding configuration"
if ! verify_cpu_shielding; then
    print_status "Error: CPU shielding verification failed"
    exit 1
fi
echo

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
echo "  cat /sys/fs/cgroup/cpuset/system/cpuset.cpus"
echo "  cat /sys/fs/cgroup/cpuset/audio/cpuset.cpus"
echo "  cat /sys/fs/cgroup/cpuset/system/tasks | wc -l"
echo "  cat /sys/fs/cgroup/cpuset/audio/tasks | wc -l"
echo
print_status "CPU shielding implementation completed successfully!"

# Keep the script running to maintain the configuration
trap "print_status 'CPU shielding configuration preserved'" EXIT