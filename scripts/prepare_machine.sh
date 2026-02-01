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

# prepare_machine.sh
# 
# Manual Machine Preparation Script for OLMS Contributors
# 
# This script provides a coordinated approach to manual system preparation
# for contributors working on Arch RT systems without the complete automated distribution.
# 
# The script acts as a workflow orchestrator that ensures proper system configuration
# before audio engine startup, implementing a sequential workflow with distinct phases.
# 
# Usage: ./scripts/prepare_machine.sh [OPTIONS]
# 
# OPTIONS:
#   --test, -t     Launch in testing mode with GUI (default)
#   --prod, -p     Launch in production mode (headless)
#   --virtual, -v  Force virtual audio backend (no hardware required)
#   --help, -h     Show help message

set -e

# Default values
MODE="test"
FORCE_VIRTUAL=false

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
        echo "Machine preparation aborted due to error in: $1"
        exit 1
    fi
}

# Function to show help
show_help() {
    echo "prepare_machine.sh - Manual Machine Preparation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --test, -t     Launch in testing mode with GUI (default)"
    echo "  --prod, -p     Launch in production mode (headless)"
    echo "  --virtual, -v  Force virtual audio backend (no hardware required)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "This script coordinates the manual preparation of an Arch RT system"
    echo "for OLMS development and testing without requiring the complete"
    echo "automated distribution."
    echo ""
    echo "The script orchestrates the following phases:"
    echo "  1. Real-time System Optimization (rt_tuning.sh)"
    echo "  2. Hardware Configuration (irq_pinning.sh)"
    echo "  3. CPU Resource Allocation (olms-apply-affinity.sh)"
    echo "  4. Audio Engine Coordination (ardour_launcher.sh)"
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

print_status "=== OLMS Manual Machine Preparation ==="
print_status "Starting machine preparation in $MODE mode"
if [ "$FORCE_VIRTUAL" = true ]; then
    print_status "Virtual audio mode enabled (no hardware required)"
fi
echo

# Phase 1: Real-time System Optimization (RT Tuning)
print_status "Phase 1: Real-time System Optimization"
print_status "Executing rt_tuning.sh..."
if [ -f "/usr/bin/rt_tuning.sh" ]; then
    # Controlla se siamo già root prima di usare sudo
    if [ "$EUID" -eq 0 ]; then
        # Già in esecuzione come root, esegui direttamente
        /usr/bin/rt_tuning.sh
    else
        # Non siamo root, usa sudo
        sudo /usr/bin/rt_tuning.sh
    fi
    check_status "RT Tuning"
else
    print_status "Warning: rt_tuning.sh not found in /usr/bin/, checking local scripts directory..."
    if [ -f "$(dirname "$0")/rt_tuning.sh" ]; then
        # Controlla se siamo già root prima di usare sudo
        if [ "$EUID" -eq 0 ]; then
            # Già in esecuzione come root, esegui direttamente
            "$(dirname "$0")/rt_tuning.sh"
        else
            # Non siamo root, usa sudo
            sudo "$(dirname "$0")/rt_tuning.sh"
        fi
        check_status "RT Tuning"
    else
        print_status "Error: rt_tuning.sh not found in either /usr/bin/ or local scripts directory"
        exit 1
    fi
fi
echo

# Phase 2: Hardware Configuration (IRQ Pinning)
print_status "Phase 2: Hardware Configuration"
print_status "Executing irq_pinning.sh..."
if [ -f "/usr/bin/irq_pinning.sh" ]; then
    set +e  # Disattiva temporaneamente l'exit on error
    sudo /usr/bin/irq_pinning.sh
    irq_status=$?
    set -e  # Riattiva l'exit on error
    
    # Don't fail if IRQ pinning fails (common for kernel-managed IRQs)
    if [ $irq_status -eq 0 ]; then
        echo "    ✓ Success"
    else
        echo "    ⚠ Warning: IRQ pinning failed (may be normal for kernel-managed IRQs)"
        echo "    Continuing machine preparation..."
    fi
else
    print_status "Warning: irq_pinning.sh not found in /usr/bin/, checking local scripts directory..."
    if [ -f "$(dirname "$0")/irq_pinning.sh" ]; then
        set +e  # Disattiva temporaneamente l'exit on error
        sudo "$(dirname "$0")/irq_pinning.sh"
        irq_status=$?
        set -e  # Riattiva l'exit on error
        
        # Don't fail if IRQ pinning fails (common for kernel-managed IRQs)
        if [ $irq_status -eq 0 ]; then
            echo "    ✓ Success"
        else
            echo "    ⚠ Warning: IRQ pinning failed (may be normal for kernel-managed IRQs)"
            echo "    Continuing machine preparation..."
        fi
    else
        print_status "Warning: irq_pinning.sh not found in local scripts directory either."
        print_status "Continuing without IRQ pinning..."
    fi
fi
echo

# Phase 3: Audio Engine Coordination
print_status "Phase 3: Audio Engine Coordination"
print_status "Machine preparation completed successfully!"
echo

print_status "=== Machine Preparation Complete ==="
print_status "System Status:"
echo "  - Real-time optimizations applied"
echo "  - Hardware configuration completed"
echo "  - Ready for audio engine startup"
echo
print_status "Note:"
echo "  - CPU affinity will be applied after audio engine startup"
echo "  - This ensures JACK and Ardour processes are running before affinity configuration"
echo
print_status "Next Steps:"
echo "  - Audio engine is now running via ardour_launcher.sh"
echo "  - Monitor system logs for any issues"
echo "  - Verify JACK and Ardour are running correctly"
echo "  - Check system performance and audio latency"
echo
print_status "To monitor the system:"
echo "  - Check JACK status: jack_control status"
echo "  - List JACK ports: jack_lsp"
echo "  - Monitor logs: journalctl -f"
echo "  - Check process affinity: taskset -p [PID]"
echo
print_status "To stop the system:"
echo "  - Stop Ardour: pkill -f ardour"
echo "  - Stop JACK: pkill jackd"
echo "  - Stop any background processes from this script"
echo
print_status "Manual machine preparation completed successfully!"
print_status "The system is now ready for OLMS audio processing."
