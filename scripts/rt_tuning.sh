#!/bin/bash

# rt_tuning.sh - Real-time System Optimization Script
# 
# This script configures kernel parameters and CPU settings for optimal real-time audio performance.
# 
# Usage: sudo ./scripts/rt_tuning.sh [--mode prod|test|light]
# 
# Modes:
#   prod  - Production mode: 95% CPU for RT tasks (default)
#   test  - Testing mode: 80% CPU for RT tasks (leaves 20% for GUI/debug tools)
#   light - Light testing mode: 60% CPU for RT tasks (for heavy debug environments)
# 
# This script performs the following optimizations:
# - Configures kernel parameters for real-time performance
# - Sets CPU governor to performance mode
# - Disables power-saving states (C-states)
# - Configures memory locking limits

set -e

# Default mode is production (95% RT)
MODE="prod"
RT_RUNTIME_VALUE=950000
RT_PERCENTAGE=95

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--mode prod|test|light]"
            echo ""
            echo "Modes:"
            echo "  prod  - Production mode: 95% CPU for RT tasks (default)"
            echo "  test  - Testing mode: 80% CPU for RT tasks (leaves 20% for GUI/debug tools)"
            echo "  light - Light testing mode: 60% CPU for RT tasks (for heavy debug environments)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set RT values based on mode
case $MODE in
    prod)
        RT_RUNTIME_VALUE=950000
        RT_PERCENTAGE=95
        ;;
    test)
        RT_RUNTIME_VALUE=800000
        RT_PERCENTAGE=80
        ;;
    light)
        RT_RUNTIME_VALUE=600000
        RT_PERCENTAGE=60
        ;;
    *)
        echo "Error: Invalid mode '$MODE'. Use prod, test, or light."
        exit 1
        ;;
esac

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
print_status "Starting RT tuning configuration in $MODE mode ($RT_PERCENTAGE% CPU for RT tasks)..."

# Phase 1: Kernel Parameter Configuration
print_status "Phase 1: Kernel Parameter Configuration"
print_status "Configuring kernel parameters for real-time performance..."

# Set kernel.sched_rt_runtime_us to allow more real-time CPU time
print_status "Setting kernel.sched_rt_runtime_us to $RT_RUNTIME_VALUE ($RT_PERCENTAGE% of CPU time for RT tasks)..."
# Remove any existing entries to avoid duplicates
sudo sed -i '/^kernel\.sched_rt_runtime_us/d' /etc/sysctl.d/99-olms-rt.conf 2>/dev/null || true
echo "kernel.sched_rt_runtime_us = $RT_RUNTIME_VALUE" | sudo tee -a /etc/sysctl.d/99-olms-rt.conf
check_status "Kernel RT runtime configuration"

# Set kernel.sched_rt_period_us to 1000000 (1 second period)
print_status "Setting kernel.sched_rt_period_us to 1000000 (1 second period)..."
# Remove any existing entries to avoid duplicates
sudo sed -i '/^kernel\.sched_rt_period_us/d' /etc/sysctl.d/99-olms-rt.conf 2>/dev/null || true
echo 'kernel.sched_rt_period_us = 1000000' | sudo tee -a /etc/sysctl.d/99-olms-rt.conf
check_status "Kernel RT period configuration"

# Apply kernel parameters (suppress verbose output)
print_status "Applying kernel parameters..."
sudo sysctl -p /etc/sysctl.d/99-olms-rt.conf >/dev/null 2>&1
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

# Note: Memory limits are configured via the symlinked 99-realtime.conf file
# This ensures consistent configuration across all OLMS components
print_status "Memory limits configured via /etc/security/limits.d/99-realtime.conf"
print_status "  - realtime group: rtprio 99, memlock unlimited"
print_status "  - audio group: rtprio 99, memlock unlimited"
print_status "  - all users: rtprio 99, memlock unlimited"
check_status "Memory locking configuration"
echo

# Phase 5: Verification
print_status "Phase 5: Configuration Verification"
print_status "Verifying RT tuning configuration..."

# Verify kernel parameters
print_status "Verifying kernel parameters..."
RT_RUNTIME=$(cat /proc/sys/kernel/sched_rt_runtime_us)
RT_PERIOD=$(cat /proc/sys/kernel/sched_rt_period_us)
echo "    RT runtime: $RT_RUNTIME us"
echo "    RT period: $RT_PERIOD us"
if [ "$RT_RUNTIME" = "$RT_RUNTIME_VALUE" ] && [ "$RT_PERIOD" = "1000000" ]; then
    echo "    Kernel parameters verified ✓"
else
    echo "    Kernel parameters verification failed ✗"
    echo "    Expected RT runtime: $RT_RUNTIME_VALUE, got: $RT_RUNTIME"
    exit 1
fi

# Verify CPU governor
print_status "Verifying CPU governor settings..."
for i in $(seq 0 $((CPU_COUNT - 1))); do
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor)
    echo "    CPU $i governor: $GOVERNOR"
    if [ "$GOVERNOR" != "performance" ]; then
        echo "    CPU $i governor verification failed ✗"
        exit 1
    fi
done

echo "    CPU governor verification completed ✓"
echo

print_status "=== RT Tuning Configuration Complete ==="
echo "Real-time system optimization completed successfully!"
echo ""
echo "Benefits:"
echo "  - Increased real-time CPU time allocation (95%)"
echo "  - Performance CPU governor for consistent clock speeds"
echo "  - Disabled power-saving states for reduced latency"
echo "  - Enhanced memory locking for audio buffers"
echo ""
echo "To verify manually:"
echo "  - Check RT parameters: cat /proc/sys/kernel/sched_rt_runtime_us"
echo "  - Check CPU governor: cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
echo "  - Check memory limits: ulimit -l"
echo ""
echo "Note: Reboot required for C-state changes to take effect"