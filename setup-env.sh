#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting OLMS environment setup..."

# 1. Install necessary core packages and dependencies
echo "Installing/updating required packages..."
# Using --noconfirm to prevent interactive prompts, as this is a setup script.
sudo pacman -Syu --noconfirm alsa-utils ardour jack-example-tools pulseaudio-jack qjackctl nodejs npm git openssh libxcrypt-compat icu tar wget linux linux-headers dkms r8168-dkms r8168

# 2. Configure OpenSSH for remote access
echo "Configuring OpenSSH..."
sudo systemctl enable --now sshd
sudo systemctl restart sshd

# 3. Create OLMS dedicated user
echo "Creating OLMS user 'olms'..."
if ! id "olms" &>/dev/null; then
    sudo useradd -r -s /bin/false olms
    echo "User 'olms' created."
else
    echo "User 'olms' already exists."
fi

# 4. Configure ALSA Loopback for virtual audio devices
echo "Configuring ALSA Loopback..."
sudo modprobe snd-aloop

# 5. Create project folder hierarchy
echo "Creating project folder hierarchy..."
mkdir -p PKGBUILD scripts engine/session-template engine/lua ui

# Create essential script placeholders as per specifications
echo "Creating essential script placeholders..."
touch scripts/rt_tuning.sh
touch scripts/ardour_launcher.sh
touch scripts/audio_virtual.sh
touch scripts/disk_guard.sh

# 6. Update Grub configuration after kernel/driver changes
echo "Updating Grub configuration..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

# 7. Enable OLMS systemd services
echo "Enabling OLMS systemd services..."
sudo systemctl enable olms-rt-tuning.service
sudo systemctl enable olms-irq-pinning.service
sudo systemctl enable ardour.service
sudo systemctl enable olms-affinity.service
sudo systemctl enable olms-disk-guard.service

echo "OLMS environment setup complete."
