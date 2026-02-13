# Copyright (C) 2024 Francesco Nano <tua@email.com>
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

# OLMS Orchestrator Launcher
# Double-click this script to start the OLMS system
# This script clears the terminal and runs the orchestrator with sudo privileges

# Use the orchestrator's built-in path detection
# The orchestrator has its own path detection system, so we don't need olms-path-utils.sh

# Debug: show current directory and user
echo "Debug - Current environment:"
echo "  Current directory: $(pwd)"
echo "  Script directory: $(dirname "${BASH_SOURCE[0]}")"
echo "  Current user: $(whoami)"
echo "  HOME: $HOME"
echo ""

# Verify that the script exists before executing it
if [[ ! -f "Startup/olms-orchestrator.sh" ]]; then
    echo "ERROR: olms-orchestrator.sh script does not exist in Startup directory"
    echo "Please check that you are in the correct directory."
    exit 1
fi

clear && sudo ./Startup/olms-orchestrator.sh
