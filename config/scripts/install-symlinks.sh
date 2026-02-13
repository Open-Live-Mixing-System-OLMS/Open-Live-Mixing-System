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

# OLMS Symlink Installation Script
# 
# This script creates symlinks for system configuration files
# to enable centralized management of OLMS configuration.

set -e

# Importa le funzioni di gestione dei percorsi
source "$(dirname "${BASH_SOURCE[0]}")/../Startup2/olms-path-utils.sh"

# Inizializza i percorsi OLMS
init_olms_paths

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored status messages
print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] $1${NC}"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to create directory if it doesn't exist
create_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        print_status "Creating directory: $dir"
        sudo mkdir -p "$dir"
    fi
}

# Function to backup existing file
backup_existing_file() {
    local file="$1"
    if [ -f "$file" ] && [ ! -L "$file" ]; then
        local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "Backing up existing file: $file → $backup_file"
        sudo cp "$file" "$backup_file"
    fi
}

# Function to create symlink
create_symlink() {
    local source="$1"
    local target="$2"
    
    # Check if source exists
    if [ ! -f "$source" ]; then
        print_error "Source file does not exist: $source"
        return 1
    fi
    
    # Backup existing file if it exists and is not a symlink
    backup_existing_file "$target"
    
    # Remove existing symlink or file
    if [ -L "$target" ] || [ -f "$target" ]; then
        print_status "Removing existing symlink/file: $target"
        sudo rm -f "$target"
    fi
    
    # Create the symlink
    print_status "Creating symlink: $target → $source"
    sudo ln -sf "$source" "$target"
    
    # Verify the symlink was created successfully
    if [ -L "$target" ]; then
        print_success "Symlink created successfully: $target"
        return 0
    else
        print_error "Failed to create symlink: $target"
        return 1
    fi
}

# Function to setup audio group
setup_audio_group() {
    local username="$1"
    
    print_status "Setting up audio group for user: $username"
    
    # Check if audio group exists, create if not
    if ! getent group audio >/dev/null; then
        print_status "Creating audio group..."
        sudo groupadd audio
        print_success "Audio group created"
    else
        print_status "Audio group already exists"
    fi
    
    # Add user to audio group if not already a member
    if ! groups "$username" | grep -q "audio"; then
        print_status "Adding user $username to audio group..."
        sudo usermod -aG audio "$username"
        print_success "User $username added to audio group"
    else
        print_status "User $username is already in audio group"
    fi
}

# Function to install realtime privileges symlink
install_realtime_privileges() {
    local script_dir="$(get_olms_path "startup_dir")"
    local config_dir="$(get_olms_path "config_dir")"
    local realtime_source="$config_dir/realtime/99-realtime.conf"
    local realtime_target="/etc/security/limits.d/99-realtime.conf"
    
    print_status "Installing realtime privileges symlink..."
    
    # Create limits directory
    create_directory "/etc/security/limits.d/"
    
    # Create the symlink
    if create_symlink "$realtime_source" "$realtime_target"; then
        print_success "Realtime privileges symlink installed successfully"
        return 0
    else
        print_error "Failed to install realtime privileges symlink"
        return 1
    fi
}

# Function to install systemd service symlinks
install_systemd_services() {
    local script_dir="$(get_olms_path "startup_dir")"
    local config_dir="$(get_olms_path "config_dir")"
    local systemd_source_dir="$config_dir/systemd"
    
    print_status "Installing systemd service symlinks..."
    
    # Check if systemd source directory exists
    if [ ! -d "$systemd_source_dir" ]; then
        print_warning "Systemd source directory not found: $systemd_source_dir"
        return 0
    fi
    
    # Create systemd system directory
    create_directory "/etc/systemd/system/"
    
    # Install each service file
    for service_file in "$systemd_source_dir"/*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file")
            local service_target="/etc/systemd/system/$service_name"
            
            if create_symlink "$service_file" "$service_target"; then
                print_success "Installed service: $service_name"
            else
                print_error "Failed to install service: $service_name"
            fi
        fi
    done
    
    # Reload systemd daemon
    print_status "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    print_success "Systemd daemon reloaded"
}

# Function to verify installation
verify_installation() {
    local username="$1"
    
    print_status "Verifying installation..."
    
    # Check realtime privileges symlink
    local realtime_target="/etc/security/limits.d/99-realtime.conf"
    if [ -L "$realtime_target" ]; then
        print_success "✓ Realtime privileges symlink exists"
        print_status "  Target: $(readlink "$realtime_target")"
    else
        print_error "✗ Realtime privileges symlink missing"
    fi
    
    # Check audio group membership
    if groups "$username" | grep -q "audio"; then
        print_success "✓ User $username is in audio group"
    else
        print_error "✗ User $username is NOT in audio group"
    fi
    
    # Check limits file contents
    if [ -L "$realtime_target" ]; then
        local source_file=$(readlink "$realtime_target")
        if [ -f "$source_file" ]; then
            print_success "✓ Realtime privileges source file exists"
            print_status "  Source: $source_file"
            
            # Show key configuration lines
            print_status "Key configuration:"
            grep -E "^@audio.*rtprio|^@audio.*memlock" "$source_file" | head -3 | while read line; do
                echo "    $line"
            done
        else
            print_error "✗ Realtime privileges source file not found"
        fi
    fi
    
    print_status ""
    print_status "IMPORTANT: You must log out and log back in for the changes to take effect."
    print_status ""
    print_status "After relogin, verify the configuration with:"
    echo "  ulimit -r  # Should show 99 (realtime priority)"
    echo "  ulimit -l  # Should show unlimited (memory lock)"
    echo "  groups $username  # Should include 'audio'"
    echo ""
    print_status "To test the configuration, run:"
    echo "  ./scripts/olms-apply-affinity.sh --test"
}

# Function to show help
show_help() {
    echo "OLMS Symlink Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --user USERNAME    Specify username for audio group (default: current user)"
    echo "  --remove           Remove installed symlinks"
    echo "  --verify           Verify installation without making changes"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Install with current user"
    echo "  $0 --user john               # Install for user 'john'"
    echo "  sudo $0 --user john          # Install with root privileges"
    echo "  $0 --verify                  # Verify installation"
    echo "  $0 --remove                  # Remove symlinks"
}

# Function to remove symlinks
remove_symlinks() {
    print_status "Removing OLMS symlinks..."
    
    # Remove realtime privileges symlink
    local realtime_target="/etc/security/limits.d/99-realtime.conf"
    if [ -L "$realtime_target" ]; then
        print_status "Removing realtime privileges symlink: $realtime_target"
        sudo rm -f "$realtime_target"
        print_success "Realtime privileges symlink removed"
    else
        print_status "Realtime privileges symlink not found"
    fi
    
    # Remove systemd service symlinks
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_dir="$(dirname "$script_dir")"
    local systemd_source_dir="$config_dir/systemd"
    
    if [ -d "$systemd_source_dir" ]; then
        for service_file in "$systemd_source_dir"/*.service; do
            if [ -f "$service_file" ]; then
                local service_name=$(basename "$service_file")
                local service_target="/etc/systemd/system/$service_name"
                
                if [ -L "$service_target" ]; then
                    print_status "Removing service symlink: $service_target"
                    sudo rm -f "$service_target"
                    print_success "Service symlink removed: $service_name"
                fi
            fi
        done
        
        # Reload systemd daemon
        print_status "Reloading systemd daemon..."
        sudo systemctl daemon-reload
        print_success "Systemd daemon reloaded"
    fi
    
    print_success "All symlinks removed successfully"
}

# Main execution
main() {
    local username="$USER"
    local action="install"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --user)
                username="$2"
                shift 2
                ;;
            --remove)
                action="remove"
                shift
                ;;
            --verify)
                action="verify"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    print_status "=== OLMS Symlink Installation ==="
    print_status "Action: $action"
    print_status "User: $username"
    print_status "Working directory: $(pwd)"
    print_status ""
    
    # Check if running as root for system operations
    if ! check_root; then
        print_warning "Some operations require root privileges and will prompt for sudo"
    fi
    
    case "$action" in
        install)
            # Setup audio group
            setup_audio_group "$username"
            
            # Install symlinks
            install_realtime_privileges
            install_systemd_services
            
            # Verify installation
            verify_installation "$username"
            
            print_status ""
            print_success "=== Installation Complete ==="
            print_status "Please log out and log back in for the changes to take effect."
            ;;
            
        remove)
            remove_symlinks
            print_status ""
            print_success "=== Removal Complete ==="
            ;;
            
        verify)
            verify_installation "$username"
            print_status ""
            print_success "=== Verification Complete ==="
            ;;
    esac
}

# Run main function
main "$@"