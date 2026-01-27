#!/bin/bash

# OLMS Manual Startup Script for Testing
# 
# This script emulates the systemd service startup sequence for development and testing.
# 
# IMPORTANT: This script must be kept synchronized with the systemd service files!
# 
# Synchronization Requirements:
# - Any changes to script paths, parameters, or execution order in this script
#   MUST be reflected in the corresponding systemd service files:
#   - systemd/olms-rt-tuning.service
#   - systemd/olms-irq-pinning.service
#   - systemd/ardour.service
#   - systemd/olms-affinity.service
#   - systemd/olms-disk-guard.service
#
# File Path Requirements:
# - Scripts must be installed to /usr/bin/ for both testing and production use
# - Current expected paths:
#   - /usr/bin/rt_tuning.sh
#   - /usr/bin/irq_pinning.sh
#   - /usr/bin/ardour_launcher.sh
#   - /usr/bin/olms-apply-affinity
#   - /usr/bin/disk_guard.sh
#
# MODES:
# - Testing Mode (default): Launches Ardour with GUI for development and monitoring
# - Production Mode (--prod): Launches Ardour headless for automated operation
# - Virtual Mode (--virtual): Uses virtual audio backend when no hardware is available
#
# Usage: ./scripts/olms-startup.sh [OPTIONS]
# OPTIONS:
#   --test, -t     Launch in testing mode with GUI (default)
#   --prod, -p     Launch in production mode (headless)
#   --virtual, -v  Force virtual audio backend (no hardware required)
#   --help, -h     Show help message

set -e

# Default values
MODE="test"
FORCE_VIRTUAL=false

# Function to show help
show_help() {
    echo "OLMS Manual Startup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --test, -t     Launch in testing mode with GUI (default)"
    echo "  --prod, -p     Launch in production mode (headless)"
    echo "  --virtual, -v  Force virtual audio backend (no hardware required)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "MODES:"
    echo "  Testing Mode: Launches Ardour with GUI for development and monitoring"
    echo "  Production Mode: Launches Ardour headless for automated operation"
    echo "  Virtual Mode: Uses virtual audio backend when no hardware is available"
    echo ""
    echo "Examples:"
    echo "  $0                   # Launch in testing mode with GUI"
    echo "  $0 --prod            # Launch in production mode (headless)"
    echo "  $0 --virtual         # Launch with virtual audio (no hardware)"
    echo "  $0 --test --virtual  # Launch testing mode with virtual audio"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test)
            MODE="test"
            shift
            ;;
        -p|--prod)
            MODE="prod"
            shift
            ;;
        -v|--virtual)
            FORCE_VIRTUAL=true
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

echo "=== OLMS Manual Startup Script ==="
echo "Starting OLMS system in $MODE mode..."
if [ "$FORCE_VIRTUAL" = true ]; then
    echo "Virtual audio mode enabled (no hardware required)"
fi
echo

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
if [ -f "/usr/bin/rt_tuning.sh" ]; then
    sudo /usr/bin/rt_tuning.sh
    check_status "RT Tuning"
else
    print_status "Warning: rt_tuning.sh not found in /usr/bin/, skipping RT tuning"
fi
echo

print_status "Phase 2: Hardware IRQ Pinning"
print_status "Executing irq_pinning.sh..."
if [ -f "/usr/bin/irq_pinning.sh" ]; then
    sudo /usr/bin/irq_pinning.sh
    check_status "IRQ Pinning"
else
    print_status "Warning: irq_pinning.sh not found in /usr/bin/, skipping IRQ pinning"
fi
echo

print_status "Phase 3: Audio Core Startup"
if [ "$MODE" = "prod" ]; then
    print_status "Starting JACK and Ardour in production mode (headless)..."
else
    print_status "Starting JACK and Ardour in testing mode (with GUI)..."
fi
if [ "$FORCE_VIRTUAL" = true ]; then
    print_status "Using virtual audio backend (no hardware required)"
fi

# Build ardour_launcher.sh arguments
ARD_ARGS=""
if [ "$MODE" = "prod" ]; then
    ARD_ARGS="--prod"
elif [ "$MODE" = "test" ]; then
    ARD_ARGS="--test"
fi

if [ "$FORCE_VIRTUAL" = true ]; then
    ARD_ARGS="$ARD_ARGS --virtual"
fi

if [ -f "/usr/bin/ardour_launcher.sh" ]; then
    sudo /usr/bin/ardour_launcher.sh $ARD_ARGS
    check_status "Audio Core Startup"
else
    print_status "Warning: ardour_launcher.sh not found in /usr/bin/, skipping audio core startup"
fi
echo

print_status "Phase 4: CPU Affinity Configuration"
print_status "Executing olms-apply-affinity..."
if [ -f "/usr/bin/olms-apply-affinity" ]; then
    sudo /usr/bin/olms-apply-affinity
    check_status "CPU Affinity"
else
    print_status "Warning: olms-apply-affinity not found in /usr/bin/, skipping CPU affinity"
fi
echo

print_status "Phase 5: Disk Protection"
print_status "Starting disk_guard.sh in background..."
if [ -f "/usr/bin/disk_guard.sh" ]; then
    sudo /usr/bin/disk_guard.sh &
    DISK_GUARD_PID=$!
    echo "    ✓ Disk guard started with PID: $DISK_GUARD_PID"
else
    print_status "Warning: disk_guard.sh not found in /usr/bin/, skipping disk protection"
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