#!/bin/bash

# OLMS Test Startup Script
# Versione modificata per testing locale che usa gli script nella directory corrente

set -e

echo "=== OLMS Test Startup Script ==="
echo "Starting OLMS system in testing mode..."
echo

# Get absolute path to current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        echo "Startup aborted due to error in: $1"
        exit 1
    fi
}

print_status "Phase 1: RT Optimization"
print_status "Executing rt_tuning.sh..."
if [ -f "$SCRIPT_DIR/scripts/rt_tuning.sh" ]; then
    sudo "$SCRIPT_DIR/scripts/rt_tuning.sh"
    check_status "RT Tuning"
else
    print_status "Warning: rt_tuning.sh not found in $SCRIPT_DIR/scripts/, skipping RT tuning"
fi
echo

print_status "Phase 2: Hardware IRQ Pinning"
print_status "Executing irq_pinning.sh..."
if [ -f "$SCRIPT_DIR/scripts/irq_pinning.sh" ]; then
    sudo "$SCRIPT_DIR/scripts/irq_pinning.sh"
    check_status "IRQ Pinning"
else
    print_status "Warning: irq_pinning.sh not found in $SCRIPT_DIR/scripts/, skipping IRQ pinning"
fi
echo

print_status "Phase 3: Audio Core Startup"
print_status "Starting JACK and Ardour in testing mode (with GUI)..."
if [ -f "$SCRIPT_DIR/scripts/ardour_launcher.sh" ]; then
    sudo "$SCRIPT_DIR/scripts/ardour_launcher.sh" --test
    check_status "Audio Core Startup"
else
    print_status "Warning: ardour_launcher.sh not found in $SCRIPT_DIR/scripts/, skipping audio core startup"
fi
echo

print_status "Phase 4: CPU Affinity Configuration"
print_status "Executing olms-apply-affinity..."
if [ -f "$SCRIPT_DIR/scripts/olms-apply-affinity" ]; then
    sudo "$SCRIPT_DIR/scripts/olms-apply-affinity"
    check_status "CPU Affinity"
else
    print_status "Warning: olms-apply-affinity not found in $SCRIPT_DIR/scripts/, skipping CPU affinity"
fi
echo

print_status "Phase 5: Disk Protection"
print_status "Starting disk_guard.sh in background..."
if [ -f "$SCRIPT_DIR/scripts/disk_guard.sh" ]; then
    sudo "$SCRIPT_DIR/scripts/disk_guard.sh" &
    DISK_GUARD_PID=$!
    echo "    ✓ Disk guard started with PID: $DISK_GUARD_PID"
else
    print_status "Warning: disk_guard.sh not found in $SCRIPT_DIR/scripts/, skipping disk protection"
fi
echo

print_status "Startup sequence completed!"
echo
print_status "System Status:"
echo "  - RT optimizations applied"
echo "  - Hardware IRQ pinned"
echo "  - JACK and Ardour running"
echo "  - CPU affinity configured"
echo "  - Disk protection active"
echo
print_status "To monitor the system:"
echo "  - Check JACK status: jack_control status"
echo "  - Monitor logs: journalctl -f -u ardour.service"
echo "  - Check disk space: df -h"
echo
print_status "To stop the system:"
echo "  - Stop Ardour: pkill -f ardour"
echo "  - Stop JACK: pkill jackd"
echo "  - Stop disk guard: kill $DISK_GUARD_PID"
echo
print_status "Manual startup script completed successfully!"
