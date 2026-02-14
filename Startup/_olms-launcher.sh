#!/bin/bash

# OLMS Orchestrator Launcher
# Double-click this script to start the OLMS system
# This script clears the terminal and runs the orchestrator with sudo privileges

# === USER CONFIGURATION SECTION ===
# Set these variables if you know your optimal audio settings to skip detection phases
# Leave them empty to use automatic detection (default behavior)

# Audio device (e.g., "hw:1", "hw:0", "dummy")
# Find your device with: aplay -l or arecord -l
# Leave empty for automatic detection (recommended)
OLMS_AUDIO_DEVICE=""

# Buffer configuration (e.g., "64:3", "32:2", "128:2")
# Format: buffer_size:periods
# Default: 64 samples, 3 cycles (periods)
OLMS_BUFFER_CONFIG="64:3"

# Bit depth (e.g., "24", "32", "16")
# Default: 32-bit for optimal performance
OLMS_BIT_DEPTH="32"

# === END USER CONFIGURATION SECTION ===

# Use the orchestrator's built-in path detection
# The orchestrator has its own path detection system, so we don't need olms-path-utils.sh

# Debug: show current directory and user
echo "Debug - Current environment:"
echo "  Current directory: $(pwd)"
echo "  Script directory: $(dirname "${BASH_SOURCE[0]}")"
echo "  Current user: $(whoami)"
echo "  HOME: $HOME"
echo ""

# Show configuration status
if [[ -n "$OLMS_AUDIO_DEVICE" ]] && [[ -n "$OLMS_BUFFER_CONFIG" ]] && [[ -n "$OLMS_BIT_DEPTH" ]]; then
    echo "🎯 CUSTOM CONFIGURATION DETECTED:"
    echo "  Audio Device: $OLMS_AUDIO_DEVICE"
    echo "  Buffer Config: $OLMS_BUFFER_CONFIG"
    echo "  Bit Depth: $OLMS_BIT_DEPTH"
    echo "  Mode: Fast startup (skipping detection phases)"
    echo ""
else
    echo "⚙️  AUTOMATIC DETECTION MODE:"
    echo "  All settings will be automatically detected"
    echo "  Mode: Standard startup with detection"
    echo ""
fi

# Verify that the script exists before executing it
if [[ ! -f "Startup/olms-orchestrator.sh" ]]; then
    echo "ERROR: olms-orchestrator.sh script does not exist in Startup directory"
    echo "Please check that you are in the correct directory."
    exit 1
fi

# Pass configuration variables to orchestrator
export OLMS_AUDIO_DEVICE="$OLMS_AUDIO_DEVICE"
export OLMS_BUFFER_CONFIG="$OLMS_BUFFER_CONFIG"
export OLMS_BIT_DEPTH="$OLMS_BIT_DEPTH"

clear && sudo OLMS_AUDIO_DEVICE="$OLMS_AUDIO_DEVICE" OLMS_BUFFER_CONFIG="$OLMS_BUFFER_CONFIG" OLMS_BIT_DEPTH="$OLMS_BIT_DEPTH" ./Startup/olms-orchestrator.sh
