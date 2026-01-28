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
