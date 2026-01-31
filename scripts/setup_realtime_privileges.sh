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

# OLMS Realtime Privileges Setup Script
# 
# This script configures the system for optimal audio performance by setting up
# realtime privileges and memory locking for the current user.

set -e

print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to setup realtime privileges
setup_realtime_privileges() {
    local username="$1"
    local limits_file="/etc/security/limits.d/99-realtime.conf"
    
    print_status "Phase 1: Setting up realtime privileges for user: $username"
    
    # Create the limits directory if it doesn't exist
    print_status "Creating limits directory: /etc/security/limits.d/"
    sudo mkdir -p /etc/security/limits.d/
    
    # Create the realtime limits configuration
    print_status "Creating realtime privileges configuration file..."
    sudo tee "$limits_file" > /dev/null << EOF
# Realtime privileges for OLMS audio system
# This file configures realtime scheduling and memory locking for audio applications

# Grant realtime privileges to the realtime group
@realtime - rtprio 99
@realtime - memlock unlimited

# Also grant directly to the specified user (fallback)
$username - rtprio 99
$username - memlock unlimited
EOF
    
    print_status "✓ Realtime privileges configuration created at: $limits_file"
    print_status "Configuration contents:"
    sudo cat "$limits_file"
    print_status "Realtime privileges setup completed successfully"
}

# Function to add user to realtime group
add_user_to_realtime_group() {
    local username="$1"
    
    print_status "Configuring realtime group memberships..."
    
    # Check if realtime group exists, create if not
    if ! getent group realtime >/dev/null; then
        print_status "Creating realtime group..."
        sudo groupadd realtime
    fi
    
    # Add Target User
    print_status "Adding target user $username to realtime group..."
    sudo usermod -aG realtime "$username"
    
    # Add Root User (FIX CRITICO)
    # Questo assicura che gli script di avvio eseguiti come root superino i controlli
    print_status "Adding root to realtime group (for system services compatibility)..."
    sudo usermod -aG realtime root
    
    print_status "✓ Group memberships updated"
}

# Function to verify configuration
verify_configuration() {
    local username="$1"
    
    print_status "Verifying realtime privileges configuration..."
    
    # Check if user is in realtime group
    if groups "$username" | grep -q "realtime"; then
        print_status "✓ User $username is in realtime group"
    else
        print_status "✗ User $username is NOT in realtime group"
        return 1
    fi
    
    # Check limits file exists
    if [ -f "/etc/security/limits.d/99-realtime.conf" ]; then
        print_status "✓ Realtime limits file exists"
        
        # Show current limits
        print_status "Current limits for $username:"
        sudo -u "$username" bash -c 'ulimit -r; ulimit -l'
    else
        print_status "✗ Realtime limits file not found"
        return 1
    fi
    
    print_status "Realtime privileges configuration completed successfully!"
    print_status ""
    print_status "IMPORTANT: You must log out and log back in for the changes to take effect."
    print_status "After relogin, you can verify the configuration with:"
    echo "  ulimit -r  # Should show 98 (realtime priority)"
    echo "  ulimit -l  # Should show unlimited (memory lock)"
    echo ""
    print_status "To test the configuration, run:"
    echo "  ./scripts/ardour_launcher.sh --test"
}

# Main execution
main() {
    print_status "=== OLMS Realtime Privileges Setup ==="
    
    # Get username (either from argument or current user)
    local username="${1:-$USER}"
    
    print_status "Target user: $username"
    
    # Check if running as root for system configuration
    if ! check_root; then
        print_status "Note: Some operations require root privileges and will prompt for sudo"
    fi
    
    # Setup realtime privileges
    setup_realtime_privileges "$username"
    
    # Add user to realtime group
    add_user_to_realtime_group "$username"
    
    # Verify configuration
    verify_configuration "$username"
    
    print_status "=== Setup Complete ==="
    print_status "Please log out and log back in to activate the realtime privileges."
}

# Show help if requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "OLMS Realtime Privileges Setup Script"
    echo ""
    echo "Usage: $0 [USERNAME]"
    echo ""
    echo "This script configures realtime privileges for audio applications."
    echo "If no username is specified, it uses the current user."
    echo ""
    echo "Example:"
    echo "  $0                    # Configure for current user"
    echo "  $0 john               # Configure for user 'john'"
    echo "  sudo $0 john          # Configure with root privileges"
    exit 0
fi

# Run main function
main "$@"