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

# OLMS Orchestrator Launcher - Test Mode
# Double-click this script to start the OLMS system in test mode with graphical interface
# Usage: ./_olms-launcher-test.sh
# This script clears the terminal and runs the orchestrator with sudo privileges in test mode

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
OLMS_BUFFER_CONFIG=""

# Bit depth (e.g., "24", "32", "16")
# Default: 32-bit for optimal performance
OLMS_BIT_DEPTH=""

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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify that the orchestrator script exists
if [[ ! -f "$SCRIPT_DIR/olms-orchestrator.sh" ]]; then
    echo "ERROR: olms-orchestrator.sh script does not exist in $SCRIPT_DIR"
    echo "Please check that you are in the correct directory."
    exit 1
fi

# Pass configuration variables to orchestrator
export OLMS_AUDIO_DEVICE="$OLMS_AUDIO_DEVICE"
export OLMS_BUFFER_CONFIG="$OLMS_BUFFER_CONFIG"
export OLMS_BIT_DEPTH="$OLMS_BIT_DEPTH"

# Change to the script directory and run the orchestrator
cd "$SCRIPT_DIR"
clear && sudo OLMS_AUDIO_DEVICE="$OLMS_AUDIO_DEVICE" OLMS_BUFFER_CONFIG="$OLMS_BUFFER_CONFIG" OLMS_BIT_DEPTH="$OLMS_BIT_DEPTH" ./olms-orchestrator.sh --test
