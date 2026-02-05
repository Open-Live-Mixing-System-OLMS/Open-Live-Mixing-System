#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting OLMS environment setup..."

# 1. Install necessary core packages and dependencies
echo "Installing/updating required packages..."
# Using --noconfirm to prevent interactive prompts, as this is a setup script.
sudo pacman -Syu --noconfirm alsa-utils ardour jack-example-tools pulseaudio-jack qjackctl nodejs npm git openssh libxcrypt-compat icu tar wget linux linux-headers dkms r8168-dkms r8168

# Note: alsabat is included in alsa-utils package for hardware-level latency testing
echo "✓ alsabat (ALSA Basic Audio Tester) included for hardware latency measurements"

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

# Install CPU affinity configuration script
echo "Installing CPU affinity configuration script..."
sudo cp scripts/olms-apply-affinity.sh /usr/bin/olms-apply-affinity
sudo chmod +x /usr/bin/olms-apply-affinity
echo "✓ CPU affinity configuration script installed"

# Install CPU shielding script
echo "Installing CPU shielding script..."
sudo cp scripts/cpu_shielding.sh /usr/bin/cpu_shielding
sudo chmod +x /usr/bin/cpu_shielding
echo "✓ CPU shielding script installed"

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

# 8. Install JACK socket permissions fix scripts
echo "Installing JACK socket permissions fix scripts..."
sudo cp Startup2/phase3-jack-init.sh /usr/bin/olms-jack-init
sudo cp Startup2/phase5-ardour-startup.sh /usr/bin/olms-ardour-startup
sudo cp Startup2/test_jack_stability.sh /usr/bin/olms-test-jack-stability
sudo chmod +x /usr/bin/olms-jack-init
sudo chmod +x /usr/bin/olms-ardour-startup
sudo chmod +x /usr/bin/olms-test-jack-stability
echo "✓ JACK socket permissions fix scripts installed"

# Install latency test script
echo "Installing latency test script..."
sudo cp scripts/olms-latency-test.sh /usr/bin/olms-latency-test
sudo chmod +x /usr/bin/olms-latency-test
echo "✓ Latency test script installed"

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to setup realtime privileges
setup_realtime_privileges() {
    print_status "Setting up realtime privileges..."
    
    # Create audio group if it doesn't exist
    if ! getent group audio >/dev/null; then
        print_status "Creating audio group..."
        sudo groupadd audio
    fi
    
    # Create realtime group if it doesn't exist
    if ! getent group realtime >/dev/null; then
        print_status "Creating realtime group..."
        sudo groupadd realtime
    fi
    
    # Add user to audio group if not already a member
    if ! groups $USER | grep -q "audio"; then
        print_status "Adding user to audio group..."
        sudo usermod -aG audio $USER
    fi
    
    # Add user to realtime group if not already a member
    if ! groups $USER | grep -q "realtime"; then
        print_status "Adding user to realtime group..."
        sudo usermod -aG realtime $USER
    fi
    
    # Create symlink for realtime privileges configuration
    print_status "Creating realtime privileges configuration..."
    sudo ln -sf /home/francesco_ssh/Progetti/OLMS-Core/config/realtime/99-realtime.conf /etc/security/limits.d/99-realtime.conf
    
    print_status "Realtime privileges setup completed!"
    print_status "Note: You may need to log out and log back in for group changes to take effect"
}

# Function to verify realtime privileges configuration
verify_realtime_privileges() {
    print_status "Verifying realtime privileges configuration..."
    
    # Check if user is in audio group
    if groups $USER | grep -q "audio"; then
        print_status "✓ User is in audio group"
    else
        print_status "✗ User is not in audio group"
        return 1
    fi
    
    # Check if user is in realtime group
    if groups $USER | grep -q "realtime"; then
        print_status "✓ User is in realtime group"
    else
        print_status "✗ User is not in realtime group"
        return 1
    fi
    
    # Check if realtime configuration file exists
    if [ -f "/etc/security/limits.d/99-realtime.conf" ]; then
        print_status "✓ Realtime configuration file exists"
    else
        print_status "✗ Realtime configuration file not found"
        return 1
    fi
    
    # Check current realtime priority limit
    local rt_limit=$(ulimit -r)
    print_status "Current realtime priority limit: $rt_limit"
    
    if [ "$rt_limit" -ge 99 ]; then
        print_status "✓ Realtime privileges are active"
        return 0
    else
        print_status "✗ Realtime privileges may not be fully active (limit: $rt_limit)"
        print_status "  Expected: 99, Got: $rt_limit"
        return 1
    fi
}

# Setup realtime privileges
print_status "Setting up realtime privileges..."
setup_realtime_privileges

# Verify realtime privileges
print_status "Verifying realtime privileges..."
if verify_realtime_privileges; then
    print_status "✓ Realtime privileges verification successful"
else
    print_status "✗ Realtime privileges verification failed"
    print_status "Please check the configuration and try again"
fi

echo "OLMS environment setup complete."
