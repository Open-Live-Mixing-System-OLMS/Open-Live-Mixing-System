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

# OLMS Startup2 - Universal System

## Overview

The startup2 process has been made **universal** to work with any Linux user, eliminating all hardcoded references to the "francesco_ssh" user.

## What Has Been Modified

### 1. Universal Variables

Replaced all hardcoded occurrences with dynamic variables:

- `francesco_ssh` → `$(whoami)`
- `/home/francesco_ssh` → `$HOME`
- `1000` → `$(id -u)`

### 2. Intelligent Sudo Execution Management

Implemented advanced logic to properly handle execution with `sudo`:

```bash
# Actual user detection
if [[ "$EUID" -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" ]]; then
        ACTUAL_USER="$SUDO_USER"
        ACTUAL_HOME=$(eval echo ~$SUDO_USER)
    elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
        ACTUAL_USER="$USER"
        ACTUAL_HOME=$(eval echo ~$USER)
    else
        ACTUAL_USER="root"
        ACTUAL_HOME="/root"
    fi
else
    ACTUAL_USER="$(whoami)"
    ACTUAL_HOME="$HOME"
fi
```

### 3. Intelligent Log File Management

Fixed the logging problem when the script is executed with sudo:

- Log files now always point to the correct home directory
- Automatic write permission management
- Fallback to temporary paths if necessary

### 4. Universal Environment Variables

Updated all environment variables to use `ACTUAL_USER` and `ACTUAL_HOME`:

```bash
export TARGET_USER="$ACTUAL_USER"
export TARGET_UID=$(id -u "$ACTUAL_USER")
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
export XAUTHORITY="$ACTUAL_HOME/.Xauthority"
```

## New Scripts: OLMS Bootstrap

### `olms-bootstrap.sh`

Universal configuration script that automatically generates:

1. **USB Udev Rules** (`/etc/udev/rules.d/99-olms-usb-permissions.rules`)
   - Permissions for USB audio devices
   - Configuration specific to the current user

2. **JACK Udev Rules** (`/etc/udev/rules.d/99-olms-jack-sockets.rules`)
   - Permissions for JACK sockets
   - Socket file access without sudo

3. **Realtime Limits** (`/etc/security/limits.d/99-olms-realtime.conf`)
   - Realtime priority (rtprio 99)
   - Unlimited memory locking
   - Configuration for audio and realtime groups

4. **RT Kernel Configuration** (`/etc/sysctl.d/99-olms-rt.conf`)
   - Kernel parameters for real-time audio
   - IRQ and scheduling configuration

5. **User Group Configuration**
   - Adding user to necessary groups (audio, realtime, plugdev)

## How to Use the Universal System

### 1. Initial Configuration (First Use)

```bash
# Run as root to configure the system
sudo ./olms-bootstrap.sh

# Follow on-screen instructions
# Restart user session after configuration
```

### 2. System Startup

```bash
# Test mode (with graphical interface)
sudo ./olms-orchestrator.sh --test

# Headless mode (without graphical interface)
sudo ./olms-orchestrator.sh
```

### 3. For Different Users

The system now works automatically for any user:

```bash
# User alice
sudo -u alice ./olms-bootstrap.sh
sudo -u alice ./olms-orchestrator.sh --test

# User bob
sudo -u bob ./olms-bootstrap.sh
sudo -u bob ./olms-orchestrator.sh --test
```

## Modified Files

### Main Scripts
- `olms-orchestrator.sh` - Main script with intelligent sudo management
- `phase0-audio-cleanup.sh` - Audio cleanup with intelligent sudo management

### Secondary Scripts (updated with sed)
- All scripts in the Startup2 folder have universal variables

### New Files
- `olms-bootstrap.sh` - Universal configuration script
- `UNIVERSAL_SYSTEM_GUIDE.md` - This guide

## Advantages of the Universal System

✅ **Multi-user**: Works with any Linux user  
✅ **Sudo Compatibility**: Properly handles execution with sudo  
✅ **Auto-configuration**: Bootstrap script automatically configures the system  
✅ **Documentation**: Complete guide for use and configuration  
✅ **Maintenance**: Easy to update and
**Soluzione**: Eseguire `./olms-bootstrap.sh` come root

### Problema: "Permessi USB negati"
**Causa**: Regole udev non configurate  
**Soluzione**: Eseguire `./olms-bootstrap.sh` come root

## Contatto e Supporto

Per problemi o domande:
- Controllare prima questo documento
- Verificare che `./olms-bootstrap.sh` sia stato eseguito
- Controllare i log in `~/.olms/olms-orchestrator.log`