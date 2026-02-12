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

# OLMS Orchestrator Launcher - Test Mode
# Double-click this script to start the OLMS system in test mode with graphical interface
# Usage: ./_olms-launcher-test.sh
# This script clears the terminal and runs the orchestrator with sudo privileges in test mode

# Intelligent home path management to handle sudo execution
if [[ "$EUID" -eq 0 ]]; then
    # If we are root, we need to determine the actual user
    if [[ -n "${SUDO_USER:-}" ]]; then
        # Executed with sudo, use original user
        ACTUAL_HOME=$(eval echo ~$SUDO_USER)
    elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
        # Executed as root but USER is set to a non-root user
        ACTUAL_HOME=$(eval echo ~$USER)
    else
        # Executed directly as root
        ACTUAL_HOME="/root"
    fi
else
    # Executed as normal user
    ACTUAL_HOME="$HOME"
fi

clear && sudo "$ACTUAL_HOME/Progetti/OLMS-Core/Startup2/olms-orchestrator.sh" --test
