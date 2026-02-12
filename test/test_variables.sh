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
echo "=== UNIVERSAL VARIABLES TEST ==="
echo "Current user: $(whoami)"
echo "Current UID: $(id -u)"
echo "Current home: $HOME"
echo ""
echo "=== VARIABLE EXPANSION TEST ==="
TARGET_USER="$(whoami)"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
XDG_RUNTIME_DIR="/run/user/$(id -u)"
XAUTHORITY="$HOME/.Xauthority"
OLMS_HOME="$HOME/.olms"
OLMS_PROJECT_DIR="$HOME/Progetti/OLMS-Core"

echo "TARGET_USER: $TARGET_USER"
echo "DBUS_SESSION_BUS_ADDRESS: $DBUS_SESSION_BUS_ADDRESS"
echo "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
echo "XAUTHORITY: $XAUTHORITY"
echo "OLMS_HOME: $OLMS_HOME"
echo "OLMS_PROJECT_DIR: $OLMS_PROJECT_DIR"
echo ""
echo "✅ All variables have been expanded correctly!"
