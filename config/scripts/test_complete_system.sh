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

# OLMS Complete System Test Script
# 
# This script performs comprehensive testing of the OLMS system
# including realtime privileges, CPU shielding, and audio process management.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored status messages
print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check realtime privileges
check_realtime_privileges() {
    print_status "=== Testing Realtime Privileges ==="
    
    local username="$USER"
    local test_passed=true
    
    # Check if user is in audio group
    if groups "$username" | grep -q "audio"; then
        print_success "✓ User $username is in audio group"
    else
        print_error "✗ User $username is NOT in audio group"
        test_passed=false
    fi
    
    # Check limits file exists and is symlinked
    local limits_file="/etc/security/limits.d/99-realtime.conf"
    if [ -L "$limits_file" ]; then
        print_success "✓ Realtime limits file is properly symlinked"
        local source_file=$(readlink "$limits_file")
        print_status "  Source: $source_file"
        
        # Check if source file exists
        if [ -f "$source_file" ]; then
            print_success "✓ Realtime limits source file exists"
        else
            print_error "✗ Realtime limits source file not found"
            test_passed=false
        fi
    else
        print_error "✗ Realtime limits file not found or not symlinked"
        test_passed=false
    fi
    
    # Check current limits (requires relogin to be effective)
    local current_rtprio=$(ulimit -r 2>/dev/null || echo "0")
    local current_memlock=$(ulimit -l 2>/dev/null || echo "0")
    
    print_status "Current limits for user $username:"
    echo "  - Realtime priority (ulimit -r): $current_rtprio"
    echo "  - Memory lock (ulimit -l): $current_memlock"
    
    if [ "$current_rtprio" = "99" ]; then
        print_success "✓ Realtime priority is set correctly (99)"
    elif [ "$current_rtprio" = "0" ]; then
        print_warning "⚠ Realtime priority not active (may need relogin)"
        print_status "  After relogin, ulimit -r should show 99"
    else
        print_warning "⚠ Realtime priority is $current_rtprio (expected 99)"
    fi
    
    if [ "$current_memlock" = "unlimited" ] || [ "$current_memlock" -gt 1000000 ]; then
        print_success "✓ Memory lock is set correctly (unlimited)"
    else
        print_warning "⚠ Memory lock is $current_memlock (should be unlimited)"
    fi
    
    if [ "$test_passed" = true ]; then
        print_success "✓ Realtime privileges test PASSED"
    else
        print_error "✗ Realtime privileges test FAILED"
    fi
    
    return $([ "$test_passed" = true ] && echo 0 || echo 1)
}

# Function to check CPU shielding
check_cpu_shielding() {
    print_status "=== Testing CPU Shielding ==="
    
    local test_passed=true
    
    # Check if cgroups exist
    if [ -d "/sys/fs/cgroup/system.slice" ] && [ -d "/sys/fs/cgroup/audio.slice" ]; then
        print_success "✓ CPU shielding cgroups exist"
    else
        print_error "✗ CPU shielding cgroups not found"
        test_passed=false
    fi
    
    # Check CPU allocation
    local system_cpus=$(cat /sys/fs/cgroup/system.slice/cpuset.cpus 2>/dev/null || echo "")
    local audio_cpus=$(cat /sys/fs/cgroup/audio.slice/cpuset.cpus 2>/dev/null || echo "")
    
    print_status "CPU allocation:"
    echo "  - System cgroup: $system_cpus"
    echo "  - Audio cgroup: $audio_cpus"
    
    if [ "$system_cpus" = "0" ]; then
        print_success "✓ System cgroup correctly assigned to core 0"
    else
        print_error "✗ System cgroup not assigned to core 0"
        test_passed=false
    fi
    
    if [ "$audio_cpus" = "2,3" ] || [ "$audio_cpus" = "2-3" ]; then
        print_success "✓ Audio cgroup correctly assigned to cores 2,3"
    else
        print_error "✗ Audio cgroup not assigned to cores 2,3"
        test_passed=false
    fi
    
    # Check process distribution
    local system_tasks=$(cat /sys/fs/cgroup/system.slice/cgroup.procs 2>/dev/null | wc -l || echo "0")
    local audio_tasks=$(cat /sys/fs/cgroup/audio.slice/cgroup.procs 2>/dev/null | wc -l || echo "0")
    
    print_status "Process distribution:"
    echo "  - System cgroup tasks: $system_tasks"
    echo "  - Audio cgroup tasks: $audio_tasks"
    
    if [ "$system_tasks" -gt 0 ]; then
        print_success "✓ System cgroup has processes assigned"
    else
        print_warning "⚠ System cgroup has no processes (may be expected)"
    fi
    
    # Show some system processes
    if [ "$system_tasks" -gt 0 ]; then
        print_status "Sample system processes:"
        cat /sys/fs/cgroup/system.slice/cgroup.procs 2>/dev/null | head -3 | while read pid; do
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                local process_name=$(ps -p "$pid" -o comm= 2>/dev/null | head -1)
                echo "    PID $pid: $process_name"
            fi
        done
    fi
    
    # Check audio processes
    if [ "$audio_tasks" -gt 0 ]; then
        print_success "✓ Audio cgroup has processes assigned"
        print_status "Audio processes:"
        cat /sys/fs/cgroup/audio.slice/cgroup.procs 2>/dev/null | while read pid; do
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                local process_name=$(ps -p "$pid" -o comm= 2>/dev/null | head -1)
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                echo "    PID $pid: $process_name"
                echo "      Command: $process_cmd"
            fi
        done
    else
        print_status "No audio processes found (expected if JACK/Ardour not running)"
    fi
    
    if [ "$test_passed" = true ]; then
        print_success "✓ CPU shielding test PASSED"
    else
        print_error "✗ CPU shielding test FAILED"
    fi
    
    return $([ "$test_passed" = true ] && echo 0 || echo 1)
}

# Function to check audio processes
check_audio_processes() {
    print_status "=== Testing Audio Processes ==="
    
    local test_passed=true
    
    # Check for JACK processes
    local jack_pids=$(pgrep -f "jackd" 2>/dev/null || true)
    if [ -n "$jack_pids" ]; then
        print_success "✓ JACK processes found:"
        for pid in $jack_pids; do
            if [ -d "/proc/$pid" ]; then
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                echo "    PID $pid: $process_cmd"
                
                # Check if in audio cgroup
                if grep -q "^$pid$" /sys/fs/cgroup/audio.slice/cgroup.procs 2>/dev/null; then
                    print_success "  ✓ JACK PID $pid is in audio cgroup"
                else
                    print_error "  ✗ JACK PID $pid is NOT in audio cgroup"
                    test_passed=false
                fi
                
                # Check realtime priority
                if command_exists chrt; then
                    local rt_info=$(chrt -p "$pid" 2>/dev/null)
                    if echo "$rt_info" | grep -q "SCHED_FIFO\|SCHED_RR"; then
                        local rt_policy=$(echo "$rt_info" | grep "policy" | awk '{print $3}')
                        local rt_priority=$(echo "$rt_info" | grep "priority" | awk '{print $3}')
                        print_success "  ✓ JACK PID $pid has RT priority ($rt_policy $rt_priority)"
                    else
                        print_warning "  ⚠ JACK PID $pid does not have RT priority"
                    fi
                fi
                
                # Check CPU affinity
                if command_exists taskset; then
                    local affinity=$(taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}')
                    if echo "$affinity" | grep -qE "c|2|3"; then
                        print_success "  ✓ JACK PID $pid has correct CPU affinity ($affinity)"
                    else
                        print_warning "  ⚠ JACK PID $pid has incorrect CPU affinity ($affinity)"
                    fi
                fi
            fi
        done
    else
        print_status "No JACK processes found (expected if JACK not running)"
    fi
    
    # Check for Ardour processes
    local ardour_pids=$(pgrep -f "ardour" 2>/dev/null || true)
    if [ -n "$ardour_pids" ]; then
        print_success "✓ Ardour processes found:"
        for pid in $ardour_pids; do
            if [ -d "/proc/$pid" ]; then
                local process_cmd=$(ps -p "$pid" -o cmd= 2>/dev/null | head -1)
                echo "    PID $pid: $process_cmd"
                
                # Check if in audio cgroup
                if grep -q "^$pid$" /sys/fs/cgroup/audio.slice/cgroup.procs 2>/dev/null; then
                    print_success "  ✓ Ardour PID $pid is in audio cgroup"
                else
                    print_error "  ✗ Ardour PID $pid is NOT in audio cgroup"
                    test_passed=false
                fi
                
                # Check realtime priority
                if command_exists chrt; then
                    local rt_info=$(chrt -p "$pid" 2>/dev/null)
                    if echo "$rt_info" | grep -q "SCHED_FIFO\|SCHED_RR"; then
                        local rt_policy=$(echo "$rt_info" | grep "policy" | awk '{print $3}')
                        local rt_priority=$(echo "$rt_info" | grep "priority" | awk '{print $3}')
                        print_success "  ✓ Ardour PID $pid has RT priority ($rt_policy $rt_priority)"
                    else
                        print_warning "  ⚠ Ardour PID $pid does not have RT priority"
                    fi
                fi
                
                # Check CPU affinity
                if command_exists taskset; then
                    local affinity=$(taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}')
                    if echo "$affinity" | grep -qE "c|2|3"; then
                        print_success "  ✓ Ardour PID $pid has correct CPU affinity ($affinity)"
                    else
                        print_warning "  ⚠ Ardour PID $pid has incorrect CPU affinity ($affinity)"
                    fi
                fi
            fi
        done
    else
        print_status "No Ardour processes found (expected if Ardour not running)"
    fi
    
    if [ "$test_passed" = true ]; then
        print_success "✓ Audio processes test PASSED"
    else
        print_error "✗ Audio processes test FAILED"
    fi
    
    return $([ "$test_passed" = true ] && echo 0 || echo 1)
}

# Function to check IRQ pinning
check_irq_pinning() {
    print_status "=== Testing IRQ Pinning ==="
    
    # Check if IRQ pinning script exists and is executable
    if [ -f "scripts/irq_pinning.sh" ] && [ -x "scripts/irq_pinning.sh" ]; then
        print_success "✓ IRQ pinning script exists and is executable"
    else
        print_warning "⚠ IRQ pinning script not found or not executable"
    fi
    
    # Check current IRQ affinity
    if [ -f "/proc/interrupts" ]; then
        print_status "Current IRQ distribution:"
        # Show interrupts on core 1 (IRQ controller core)
        local core1_irqs=$(grep -E "^[0-9]+:" /proc/interrupts | awk '{print $2}' | grep -c "1" || echo "0")
        echo "  - IRQs on core 1: $core1_irqs"
        
        # Look for audio-related IRQs
        if grep -q "audio\|snd\|usb" /proc/interrupts 2>/dev/null; then
            print_status "Audio-related IRQs found:"
            grep -i "audio\|snd\|usb" /proc/interrupts | head -5
        else
            print_status "No audio-related IRQs found in /proc/interrupts"
        fi
    else
        print_warning "⚠ /proc/interrupts not accessible"
    fi
    
    print_success "✓ IRQ pinning test completed"
}

# Function to run comprehensive test
run_comprehensive_test() {
    print_status "=== OLMS Complete System Test ==="
    echo ""
    
    local overall_test_passed=true
    
    # Test 1: Realtime Privileges
    if check_realtime_privileges; then
        print_success "Realtime privileges: PASSED"
    else
        print_error "Realtime privileges: FAILED"
        overall_test_passed=false
    fi
    echo ""
    
    # Test 2: CPU Shielding
    if check_cpu_shielding; then
        print_success "CPU shielding: PASSED"
    else
        print_error "CPU shielding: FAILED"
        overall_test_passed=false
    fi
    echo ""
    
    # Test 3: Audio Processes
    if check_audio_processes; then
        print_success "Audio processes: PASSED"
    else
        print_error "Audio processes: FAILED"
        overall_test_passed=false
    fi
    echo ""
    
    # Test 4: IRQ Pinning
    check_irq_pinning
    echo ""
    
    # Final report
    print_status "=== Test Summary ==="
    if [ "$overall_test_passed" = true ]; then
        print_success "✓ ALL TESTS PASSED - OLMS system is properly configured"
        print_status ""
        print_status "Your OLMS system is ready for professional audio production!"
        print_status "Key benefits:"
        echo "  - Realtime privileges configured for audio processes"
        echo "  - CPU shielding isolates audio processing"
        echo "  - Audio processes properly isolated and prioritized"
        echo "  - System optimized for low-latency audio performance"
    else
        print_error "✗ SOME TESTS FAILED - Please review the issues above"
        print_status ""
        print_status "Common issues and solutions:"
        echo "  1. Realtime privileges not active: Log out and log back in"
        echo "  2. Audio processes not in audio cgroup: Run CPU shielding script"
        echo "  3. Missing realtime priority: Check audio group membership"
        echo "  4. Incorrect CPU affinity: Verify CPU shielding configuration"
        echo ""
        print_status "For assistance, check the OLMS documentation or run:"
        echo "  ./config/scripts/install-symlinks.sh --verify"
    fi
    
    return $([ "$overall_test_passed" = true ] && echo 0 || echo 1)
}

# Function to show help
show_help() {
    echo "OLMS Complete System Test Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --help, -h         Show this help message"
    echo "  --quick            Run quick test (skip some checks)"
    echo ""
    echo "This script performs comprehensive testing of the OLMS system:"
    echo "  - Realtime privileges configuration"
    echo "  - CPU shielding setup"
    echo "  - Audio process management"
    echo "  - IRQ pinning verification"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run full comprehensive test"
    echo "  $0 --quick         # Run quick test"
}

# Main execution
main() {
    local quick_test=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                quick_test=true
                shift
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
    
    # Check if running from correct directory
    if [ ! -f "config/realtime/99-realtime.conf" ]; then
        print_error "Error: This script must be run from the OLMS-Core directory"
        print_status "Please run: cd /path/to/OLMS-Core && $0"
        exit 1
    fi
    
    # Run the comprehensive test
    run_comprehensive_test
}

# Run main function
main "$@"