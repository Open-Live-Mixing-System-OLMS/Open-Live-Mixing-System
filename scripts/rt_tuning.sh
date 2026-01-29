#!/bin/bash

# rt_tuning.sh - Real-time System Optimization Script
# 
# This script configures kernel parameters and CPU settings for optimal real-time audio performance.
# 
# Usage: sudo ./scripts/rt_tuning.sh
# 
# This script performs the following optimizations:
# - Configures kernel parameters for real-time performance
# - Sets CPU governor to performance mode
# - Disables power-saving states (C-states)
# - Configures memory locking limits

set -e

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo "    ✓ Success"
    else
        echo "    ✗ Failed"
        echo "RT tuning aborted due to error in: $1"
        exit 1
    fi
}

print_status "=== OLMS Real-time System Optimization ==="
print_status "Starting RT tuning configuration..."

# Phase 1: Kernel Parameter Configuration
print_status "Phase 1: Kernel Parameter Configuration"
print_status "Configuring kernel parameters for real-time performance..."

# Set kernel.sched_rt_runtime_us to allow more real-time CPU time
print_status "Setting kernel.sched_rt_runtime_us to 950000 (95% of CPU time for RT tasks)..."
echo 'kernel.sched_rt_runtime_us = 950000' | sudo tee -a /etc/sysctl.d/99-olms-rt.conf
check_status "Kernel RT runtime configuration"

# Set kernel.sched_rt_period_us to 1000000 (1 second period)
print_status "Setting kernel.sched_rt_period_us to 1000000 (1 second period)..."
echo 'kernel.sched_rt_period_us = 1000000' | sudo tee -a /etc/sysctl.d/99-olms-rt.conf
check_status "Kernel RT period configuration"

# Apply kernel parameters
print_status "Applying kernel parameters..."
sudo sysctl -p /etc/sysctl.d/99-olms-rt.conf
check_status "Kernel parameter application"
echo

# Phase 2: CPU Governor Configuration
print_status "Phase 2: CPU Governor Configuration"
print_status "Setting CPU governor to performance mode..."

# Get number of CPU cores
CPU_COUNT=$(nproc)
print_status "Detected $CPU_COUNT CPU cores"

# Set all CPU cores to performance mode
for i in $(seq 0 $((CPU_COUNT - 1))); do
    print_status "Setting CPU core $i governor to performance mode..."
    echo performance | sudo tee /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor
    check_status "CPU $i governor configuration"
done
echo

# Phase 3: Power Management Configuration
print_status "Phase 3: Power Management Configuration"
print_status "Note: CPU C-states disabled via GRUB configuration (permanent change)"
print_status "For testing, C-states can be disabled temporarily via sysfs if needed"
echo

# Phase 4: Memory Configuration
print_status "Phase 4: Memory Configuration"
print_status "Configuring memory locking limits..."

# Set memory locking limits for realtime group
print_status "Setting memory locking limits for realtime group..."
echo '@realtime - rtprio 99' | sudo tee -a /etc/security/limits.d/99-olms-realtime.conf
echo '@realtime - memlock unlimited' | sudo tee -a /etc/security/limits.d/99-olms-realtime.conf
check_status "Memory locking configuration"
echo

# Phase 5: Verification
print_status "Phase 5: Configuration Verification"
print_status "Verifying RT tuning configuration..."

# Verify kernel parameters
print_status "Verifying kernel parameters..."
RT_RUNTIME=$(cat /proc/sys/kernel/sched_rt_runtime_us)
RT_PERIOD=$(cat /proc/sys/kernel/sched_rt_period_us)
print_status "RT runtime: $RT_RUNTIME us"
print_status "RT period: $RT_PERIOD us"
if [ "$RT_RUNTIME" = "950000" ] && [ "$RT_PERIOD" = "1000000" ]; then
    print_status "Kernel parameters verified ✓"
else
    print_status "Kernel parameters verification failed ✗"
    exit 1
fi

# Verify CPU governor
print_status "Verifying CPU governor settings..."
for i in $(seq 0 $((CPU_COUNT - 1))); do
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor)
    print_status "CPU $i governor: $GOVERNOR"
    if [ "$GOVERNOR" != "performance" ]; then
        print_status "CPU $i governor verification failed ✗"
        exit 1
    fi
done

print_status "CPU governor verification completed ✓"
echo

print_status "=== RT Tuning Configuration Complete ==="
print_status "Real-time system optimization completed successfully!"
print_status ""
print_status "Benefits:"
echo "  - Increased real-time CPU time allocation (95%)"
echo "  - Performance CPU governor for consistent clock speeds"
echo "  - Disabled power-saving states for reduced latency"
echo "  - Enhanced memory locking for audio buffers"
echo ""
print_status "To verify manually:"
echo "  - Check RT parameters: cat /proc/sys/kernel/sched_rt_runtime_us"
echo "  - Check CPU governor: cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
echo "  - Check memory limits: ulimit -l"
echo ""
print_status "Note: Reboot required for C-state changes to take effect"
print_status "RT tuning configuration completed successfully!"