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

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Loading ALSA Loopback module for virtual audio channels..."

# Load the snd-aloop module to create virtual ALSA loopback devices
# This creates two virtual sound cards (cards 0 and 1) by default.
# Each card has two devices, 0 and 1.
# Device 0 is for playback to capture, and Device 1 is for capture from playback.
sudo modprobe snd-aloop

echo "ALSA Loopback module loaded. Check with 'aplay -l' and 'arecord -l'"
echo "You may need to configure JACK or other audio applications to use these virtual devices."
