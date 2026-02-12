#!/bin/bash
# OLMS JACK Setup Script
# Configures JACK for optimal performance with OLMS
# Addresses the "Dummy" problem by implementing the expert strategy

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# User and system detection
detect_user_environment() {
    # Intelligent home path management to handle sudo execution
    if [[ "$EUID" -eq 0 ]]; then
        # If we are root, we need to determine the actual user
        if [[ -n "${SUDO_USER:-}" ]]; then
            # Executed with sudo, use original user
            ACTUAL_USER="$SUDO_USER"
            ACTUAL_HOME=$(eval echo ~$SUDO_USER)
        elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
            # Executed as root but USER is set to a non-root user
            ACTUAL_USER="$USER"
            ACTUAL_HOME=$(eval echo ~$USER)
        else
            # Executed directly as root
            ACTUAL_USER="root"
            ACTUAL_HOME="/root"
        fi
    else
        # Executed as normal user
        ACTUAL_USER="$(whoami)"
        ACTUAL_HOME="$HOME"
    fi
    
    ACTUAL_UID=$(id -u "$ACTUAL_USER")
    
    log "Detected user environment:"
    log "  User: $ACTUAL_USER"
    log "  UID: $ACTUAL_UID"
    log "  Home: $ACTUAL_HOME"
    
    # Verify user exists and has necessary permissions
    if ! id "$ACTUAL_USER" >/dev/null 2>&1; then
        error "User $ACTUAL_USER does not exist"
        exit 1
    fi
    
    # Verify user has a home directory
    if [[ ! -d "$ACTUAL_HOME" ]]; then
        warn "Home directory $ACTUAL_HOME does not exist, creating..."
        mkdir -p "$ACTUAL_HOME"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME"
    fi
}

# Create necessary directories
create_directories() {
    log "Creating necessary directories..."
    
    # OLMS directories
    mkdir -p "$ACTUAL_HOME/.olms"
    mkdir -p "$ACTUAL_HOME/Progetti/OLMS-Core"
    
    # NOTE: We don't create custom JACK directories
    # JACK2 puts files directly in /dev/shm/ with jack_olms prefix
    # The /dev/shm directory is already managed by the system
    
    # Set correct permissions
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.olms" 2>/dev/null || true
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/Progetti/OLMS-Core" 2>/dev/null || true
    
    log "Directories created successfully"
}

# Generate JACK Udev rules
generate_jack_rules() {
    log "Generating JACK Udev rules for $ACTUAL_USER..."
    
    local jack_rules_file="/etc/udev/rules.d/99-olms-jack-sockets.rules"
    
    # JACK rules content
    cat > "$jack_rules_file" << EOF
# OLMS JACK Socket Permissions
# Automatically generated for user $ACTUAL_USER
# Allows user $ACTUAL_USER to manage JACK sockets without sudo

# Permissions for JACK sockets in /dev/shm (modern pattern)
KERNEL=="jack_*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="jack-shm-*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for legacy JACK sockets (legacy pattern used by some JACK scripts)
KERNEL=="jack-*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for JACK sockets in /tmp
KERNEL=="jack_*", SUBSYSTEM=="misc", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for JACK directory for compatibility
KERNEL=="jack-*", SUBSYSTEM=="misc", MODE="0777", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "JACK Udev rules generated in $jack_rules_file"
}

# Generate realtime limits configuration
generate_realtime_limits() {
    log "Generating realtime limits for $ACTUAL_USER..."
    
    local limits_file="/etc/security/limits.d/99-olms-realtime.conf"
    
    # Realtime limits content
    cat > "$limits_file" << EOF
# OLMS Real-Time User Limits
# Automatically generated for user $ACTUAL_USER

# Limits for realtime users
@$ACTUAL_USER soft rtprio 99
@$ACTUAL_USER hard rtprio 99
@$ACTUAL_USER soft memlock unlimited
@$ACTUAL_USER hard memlock unlimited

# Limits for audio group
@audio soft rtprio 99
@audio hard rtprio 99
@audio soft memlock unlimited
@audio hard memlock unlimited

# Specific limits for user
$ACTUAL_USER soft rtprio 99
$ACTUAL_USER hard rtprio 99
$ACTUAL_USER soft memlock unlimited
$ACTUAL_USER hard memlock unlimited
EOF

    log "Realtime limits generated in $limits_file"
}

# Generate kernel RT configuration
generate_kernel_config() {
    log "Generating kernel RT configuration..."
    
    local kernel_config_file="/etc/sysctl.d/99-olms-rt.conf"
    
    # Kernel configuration content
    cat > "$kernel_config_file" << EOF
# OLMS Real-Time Kernel Parameters
# Automatically generated for user $ACTUAL_USER

# Base RT parameters
kernel.sched_rt_runtime_us = 950000
kernel.sched_rt_period_us = 1000000

# CPU migration (if supported)
kernel.sched_migration_cost_ns = 500000

# Wakeup granularity (if supported)
kernel.sched_wakeup_granularity_ns = 1000000

# Disable deep C-states (if supported)
kernel.sched_mc_power_savings = 0
EOF

    log "Kernel RT configuration generated in $kernel_config_file"
}

# Generate taskset/chrt and /proc access permissions
generate_taskset_chrt_permissions() {
    log "Generating taskset/chrt and /proc access permissions for $ACTUAL_USER..."
    
    local taskset_chrt_rules="/etc/udev/rules.d/99-olms-taskset-chrt.rules"
    
    # taskset/chrt rules content
    cat > "$taskset_chrt_rules" << EOF
# OLMS taskset/chrt Permissions
# Automatically generated for user $ACTUAL_USER
# Allows user $ACTUAL_USER to use taskset and chrt without sudo

# Permissions for taskset (CPU affinity)
KERNEL=="cpu*", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for chrt (scheduling)
KERNEL=="sched*", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for sched_setscheduler
KERNEL=="sched_setscheduler", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for sched_getscheduler
KERNEL=="sched_getscheduler", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for sched_getparam
KERNEL=="sched_getparam", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for sched_setparam
KERNEL=="sched_setparam", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "taskset/chrt rules generated in $taskset_chrt_rules"
    
    # Add rules for /proc file access (necessary for new implementation)
    local proc_rules="/etc/udev/rules.d/99-olms-proc-access.rules"
    
    cat > "$proc_rules" << EOF
# OLMS /proc Access Permissions
# Automatically generated for user $ACTUAL_USER
# Allows user $ACTUAL_USER to access /proc files for CPU affinity and scheduling

# Permissions for /proc/*/cpuset (CPU affinity)
KERNEL=="cpuset", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for /proc/*/sched* (scheduling)
KERNEL=="sched*", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permissions for /proc/*/status (process status)
KERNEL=="status", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "/proc access rules generated in $proc_rules"
}

# Configure PAM to load RT limits
configure_pam_limits() {
    log "Configuring PAM to load RT limits..."
    
    # PAM files to modify
    local pam_sudo="/etc/pam.d/sudo"
    local pam_common_session="/etc/pam.d/common-session"
    
    # Verify and add PAM rule for sudo
    if [[ -f "$pam_sudo" ]]; then
        if ! grep -q "pam_limits.so" "$pam_sudo"; then
            log "Adding PAM rule to $pam_sudo"
            echo "session required pam_limits.so" >> "$pam_sudo"
        else
            log "PAM rule already present in $pam_sudo"
        fi
    else
        warn "PAM file $pam_sudo not found"
    fi
    
    # Verify and add PAM rule for common-session
    if [[ -f "$pam_common_session" ]]; then
        if ! grep -q "pam_limits.so" "$pam_common_session"; then
            log "Adding PAM rule to $pam_common_session"
            echo "session required pam_limits.so" >> "$pam_common_session"
        else
            log "PAM rule already present in $pam_common_session"
        fi
    else
        warn "PAM file $pam_common_session not found"
    fi
    
    log "PAM configuration completed"
}

# Generate Udev DMA Latency rules
generate_dma_latency_rules() {
    log "Generating Udev DMA Latency rules for $ACTUAL_USER..."
    
    local dma_rules_file="/etc/udev/rules.d/99-olms-dma-latency.rules"
    
    # DMA Latency rules content
    cat > "$dma_rules_file" << EOF
# OLMS DMA Latency Permissions
# Automatically generated for user $ACTUAL_USER
# Allows user $ACTUAL_USER to prevent CPU from going into power saving

# Permissions for /dev/cpu_dma_latency (prevents deep C-states)
KERNEL=="cpu_dma_latency", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "DMA Latency rules generated in $dma_rules_file"
}

# Configure user groups
configure_user_groups() {
    log "Configuring user groups for $ACTUAL_USER..."
    
    # Add user to necessary groups
    local groups=("audio" "realtime" "plugdev")
    
    for group in "${groups[@]}"; do
        if getent group "$group" >/dev/null 2>&1; then
            if ! groups "$ACTUAL_USER" | grep -q "\b$group\b"; then
                log "Adding user $ACTUAL_USER to group $group"
                usermod -a -G "$group" "$ACTUAL_USER" 2>/dev/null || warn "Unable to add $ACTUAL_USER to group $group (might require restart)"
            else
                log "User $ACTUAL_USER already in group $group"
            fi
        else
            log "Group $group does not exist, creating..."
            groupadd "$group" 2>/dev/null || warn "Unable to create group $group"
            usermod -a -G "$group" "$ACTUAL_USER" 2>/dev/null || warn "Unable to add $ACTUAL_USER to group $group"
        fi
    done
}

# Configure USB audio volume to 100% for complete signal pass-through
configure_audio_volume() {
    log "Configuring USB audio volume to 100% for complete signal pass-through..."
    
    # Find available USB audio devices
    local usb_devices=$(aplay -l 2>/dev/null | grep -i "USB Audio" | grep -o "card [0-9]*" | cut -d' ' -f2)
    
    if [[ -z "$usb_devices" ]]; then
        log "No USB audio devices found"
        return 0
    fi
    
    for card_num in $usb_devices; do
        log "Configuring volume for USB audio card: card $card_num"
        
        # Set PCM volume to 100% for complete signal pass-through
        if amixer -c "$card_num" set PCM 100% unmute >/dev/null 2>&1; then
            log "✅ PCM volume set to 100% for card $card_num"
        else
            warn "⚠️ Unable to set PCM volume for card $card_num"
        fi
        
        # Set Master volume to 100% for complete signal pass-through
        if amixer -c "$card_num" set Master 100% unmute >/dev/null 2>&1; then
            log "✅ Master volume set to 100% for card $card_num"
        else
            warn "⚠️ Unable to set Master volume for card $card_num"
        fi
        
        # Set Digital volume to 100% if available
        if amixer -c "$card_num" set Digital 100% unmute >/dev/null 2>&1; then
            log "✅ Digital volume set to 100% for card $card_num"
        else
            log "Digital volume not available for card $card_num (optional)"
        fi
    done
    
    log "USB audio volume configuration completed"
}

# Install Runtime Permission Manager
install_runtime_permission_manager() {
    log "Installing Runtime Permission Manager..."
    
    local runtime_script="$ACTUAL_HOME/.olms/olms-runtime-permissions.sh"
    local system_script="/usr/local/bin/olms-runtime-permissions"
    
    # Copy script to user's home directory
    if [[ -f "$SCRIPT_DIR/olms-runtime-permissions.sh" ]]; then
        cp "$SCRIPT_DIR/olms-runtime-permissions.sh" "$runtime_script"
        chmod +x "$runtime_script"
        log "Runtime Permission Manager installed in $runtime_script"
    else
        warn "Runtime Permission Manager script not found in $SCRIPT_DIR"
    fi
    
    # Copy script to system (requires sudo)
    if [[ -f "$SCRIPT_DIR/olms-runtime-permissions.sh" ]]; then
        cp "$SCRIPT_DIR/olms-runtime-permissions.sh" "$system_script"
        chmod +x "$system_script"
        log "Runtime Permission Manager installed in $system_script"
    fi
    
    # Configure automatic startup
    configure_autostart
}

# Configure automatic startup
configure_autostart() {
    log "Configuring automatic startup..."
    
    # Create systemd script (if available)
    if command -v systemctl >/dev/null 2>&1; then
        create_systemd_service
    fi
    
    # Create rc.local script (fallback)
    create_rc_local_script
    
    log "Autostart configuration completed"
}

# Create systemd service for Runtime Permission Manager
create_systemd_service() {
    log "Creating systemd service for Runtime Permission Manager..."
    
    local service_file="/etc/systemd/system/olms-runtime-permissions.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=OLMS Runtime Permission Manager
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/olms-runtime-permissions
RemainAfterExit=yes
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Enable service
    systemctl daemon-reload
    systemctl enable olms-runtime-permissions.service
    
    log "Systemd service created and enabled: $service_file"
}

# Create rc.local script for startup (fallback)
create_rc_local_script() {
    log "Creating rc.local script for Runtime Permission Manager..."
    
    local rc_local="/etc/rc.local"
    local script_content="#!/bin/bash
# OLMS Runtime Permission Manager - Startup execution
if [ -x /usr/local/bin/olms-runtime-permissions ]; then
    /usr/local/bin/olms-runtime-permissions
fi
exit 0"
    
    # If rc.local exists, add script call
    if [[ -f "$rc_local" ]]; then
        # Verify that the call is not already present
        if ! grep -q "olms-runtime-permissions" "$rc_local"; then
            # Add call before exit 0
            sed -i '/^exit 0$/i\
# OLMS Runtime Permission Manager\
if [ -x /usr/local/bin/olms-runtime-permissions ]; then\
    /usr/local/bin/olms-runtime-permissions\
fi' "$rc_local"
            log "Runtime Permission Manager call added to $rc_local"
        else
            log "Runtime Permission Manager call already present in $rc_local"
        fi
    else
        # Create rc.local
        echo "$script_content" > "$rc_local"
        chmod +x "$rc_local"
        log "rc.local file created with Runtime Permission Manager: $rc_local"
    fi
}

# Verify and apply configurations
apply_configurations() {
    log "Applying configurations..."
    
    # Apply realtime limits
    if [[ -f "/etc/security/limits.d/99-olms-realtime.conf" ]]; then
        log "Realtime limits applied (requires session restart)"
    fi
    
    # Apply kernel configuration
    if [[ -f "/etc/sysctl.d/99-olms-rt.conf" ]]; then
        log "Applying kernel parameters..."
        # Use || true to avoid set -e interrupting if a parameter is unknown to the kernel
        sysctl -p "/etc/sysctl.d/99-olms-rt.conf" || warn "Some sysctl parameters were not applied."
        
        # Verify that the main parameters have been applied correctly
        local rt_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
        local rt_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "0")
        
        if [[ "$rt_runtime" == "950000" ]] && [[ "$rt_period" == "1000000" ]]; then
            log "RT kernel configuration applied"
            log "✅ Verified RT kernel parameters: runtime=$rt_runtime, period=$rt_period"
        else
            warn "⚠️ Unable to fully apply RT kernel configuration"
        fi
    fi
    
    # Apply sysfs rules
    if command -v systemd-tmpfiles >/dev/null 2>&1; then
        log "Apply sysfs rules via tmpfiles..."
        systemd-tmpfiles --create /etc/tmpfiles.d/olms-cpu.conf || warn "tmpfiles error"
    fi
    
    # Reload udev rules
    if command -v udevadm >/dev/null 2>&1; then
        log "Reload udev rules..."
        udevadm control --reload-rules
        udevadm trigger
    fi
    
    # Configure USB audio volume to 100% for complete signal pass-through
    configure_audio_volume
    
    # Install Runtime Permission Manager
    install_runtime_permission_manager
    
    # CRITICAL: Explicit X11 call before the end
    configure_x11_environment
}

# Configure X11 environment for root→user transition
configure_x11_environment() {
    log "Configuring X11 environment for root→user transition..."
    
    # Verify if an active X11 display exists
    local display_found=false
    local active_display=""
    
    # Search for active displays
    for i in {0..9}; do
        if [[ -S "/tmp/.X11-unix/X$i" ]]; then
            active_display=":$i"
            display_found=true
            break
        fi
    done
    
    if [[ "$display_found" == "false" ]]; then
        warn "No active X11 display found, creating virtual display..."
        # Create virtual display for compatibility
        active_display=":99"
    fi
    
    log "Active X11 display: $active_display"
    
    # Configure X11 environment variables
    local x11_env_file="/etc/profile.d/olms-x11.sh"
    
    cat > "$x11_env_file" << EOF
# OLMS X11 Environment Variables
# Automatically generated for user $ACTUAL_USER

export DISPLAY="$active_display"
export XAUTHORITY="$ACTUAL_HOME/.Xauthority"
export XDG_RUNTIME_DIR="/run/user/$ACTUAL_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$ACTUAL_UID/bus"
export JACK_DEFAULT_SERVER="olms"
export JACK_NO_START_SERVER=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_SESSION_DIR="/dev/shm/jack_olms_0"
EOF

    chmod +x "$x11_env_file"
    log "X11 environment variables configured in $x11_env_file"
    
    # Configure XAUTHORITY for root
    configure_xauthority_for_root
    
    # Configure xhost permissions
    configure_xhost_permissions
    
    log "X11 environment configured for root→user transition"
}

# Configure XAUTHORITY for root
configure_xauthority_for_root() {
    log "Configuring XAUTHORITY for root..."
    
    local user_xauth="$ACTUAL_HOME/.Xauthority"
    local root_xauth="/root/.Xauthority"
    
    # If user's .Xauthority exists, copy it for root
    if [[ -f "$user_xauth" ]]; then
        log "Copy .Xauthority from $user_xauth to $root_xauth"
        cp "$user_xauth" "$root_xauth"
        chown root:root "$root_xauth"
        chmod 600 "$root_xauth"
        log "✅ XAUTHORITY configured for root"
    else
        warn "⚠️ User .Xauthority file not found: $user_xauth"
        warn "⚠️ Root may not have access to the X11 display"
    fi
}

# Configure xhost permissions
configure_xhost_permissions() {
    log "Advanced xhost permissions configuration..."
    
    # Force DISPLAY if not set
    export DISPLAY=${DISPLAY:-:0}
    
    # Attempt to authorize root to connect to user's X server
    if command -v xhost >/dev/null 2>&1; then
        # Run xhost as real user, not as root, to open the port
        su - "$ACTUAL_USER" -c "DISPLAY=$DISPLAY xhost +si:localuser:root" || \
        warn "xhost failed to authorize root. Try manually as user: xhost +si:localuser:root"
    fi
}

# Final verification
verify_configuration() {
    log "Final verification..."
    
    # Verify user groups
    local groups_ok=true
    for group in "audio" "realtime"; do
        if groups "$ACTUAL_USER" | grep -q "\b$group\b"; then
            log "✅ Group $group: OK"
        else
            warn "⚠️ Group $group: NOT CONFIGURED"
            groups_ok=false
        fi
    done
    
    # Verify configuration files
    local config_files=(
        "/etc/udev/rules.d/99-olms-jack-sockets.rules"
        "/etc/security/limits.d/99-olms-realtime.conf"
        "/etc/sysctl.d/99-olms-rt.conf"
        "/etc/udev/rules.d/99-olms-taskset-chrt.rules"
        "/etc/udev/rules.d/99-olms-proc-access.rules"
        "/etc/udev/rules.d/99-olms-dma-latency.rules"
        "/etc/profile.d/olms-x11.sh"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "✅ File $file: OK"
        else
            warn "⚠️ File $file: NOT FOUND"
            groups_ok=false
        fi
    done
    
    # Verify user limits
    local current_rtprio=$(ulimit -r 2>/dev/null || echo "0")
    local current_memlock=$(ulimit -l 2>/dev/null || echo "0")
    
    log "Current limits: rtprio=$current_rtprio, memlock=${current_memlock}KB"
    
    # Verify X11 configuration
    log "Verifying X11 configuration..."
    if [[ -f "/etc/profile.d/olms-x11.sh" ]]; then
        log "✅ X11 environment variables: OK"
    else
        warn "⚠️ X11 environment variables: NOT CONFIGURED"
        groups_ok=false
    fi
    
    if [[ -f "/root/.Xauthority" ]]; then
        log "✅ XAUTHORITY root: OK"
    else
        warn "⚠️ XAUTHORITY root: NOT CONFIGURED"
        groups_ok=false
    fi
    
    if [[ "$groups_ok" == "true" ]]; then
        log "✅ Configuration completed successfully!"
        log "⚠️ Note: Some changes require user session restart"
    else
        warn "⚠️ Partial configuration - some changes may not be active"
    fi
}

# Main function
main() {
    log "=== OLMS JACK SETUP SCRIPT ==="
    log "JACK configuration for any Linux user"
    
    # Verify that the script is executed as root (required for system changes)
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be executed as root to modify system files"
        error "Run: sudo $0"
        exit 1
    fi
    
    detect_user_environment
    create_directories
    generate_jack_rules
    generate_realtime_limits
    generate_kernel_config
    generate_taskset_chrt_permissions
    configure_pam_limits
    generate_dma_latency_rules
    configure_user_groups
    apply_configurations
    verify_configuration
    
    log "=== JACK SETUP COMPLETED ==="
    log "User $ACTUAL_USER is now configured for JACK use"
    log "To activate all changes, run:"
    log "  - User session restart"
    log "  - System restart (optional but recommended)"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Funzione di pulizia JACK
cleanup_jack() {
    log "=== Pulizia JACK ==="
    
    # Termina processi JACK
    pkill -9 jackd 2>/dev/null || true
    pkill -9 jackdbus 2>/dev/null || true
    log "   Processi JACK terminati"
    
    # Pulisci socket
    sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    log "   Socket JACK rimossi"
    
    # Pulisci registri
    sudo rm -f /dev/shm/jack-shm-registry* 2>/dev/null || true
    log "   Registri JACK rimossi"
    
    log "Pulizia JACK completata"
}

# Funzione di verifica stato
check_status() {
    log "=== Stato Sistema JACK ==="
    
    # Verifica processi
    local jack_processes=$(pgrep -f "jackd\|jackdbus" || echo "")
    if [[ -n "$jack_processes" ]]; then
        log "Processi JACK attivi:"
        ps -p $jack_processes -o pid,cmd --no-headers 2>/dev/null || echo "   Nessun processo trovato"
    else
        log "Nessun processo JACK attivo"
    fi
    
    # Verifica socket
    local jack_sockets=$(find /dev/shm /tmp -name "*jack*" -type d 2>/dev/null || echo "")
    if [[ -n "$jack_sockets" ]]; then
        log "Socket JACK presenti:"
        echo "$jack_sockets" | while read -r socket; do
            log "   $socket"
        done
    else
        log "Nessun socket JACK trovato"
    fi
    
    # Verifica capabilities
    if command -v getcap >/dev/null 2>&1; then
        local capabilities=$(getcap /usr/bin/jackd 2>/dev/null || echo "Nessuna capability")
        log "Capabilities JACK: $capabilities"
    fi
    
    # Verifica limiti utente
    log "Limiti utente:"
    log "  rtprio: $(ulimit -r)"
    log "  memlock: $(ulimit -l)"
    log "  Gruppi: $(groups)"
}

# Help
show_help() {
    echo "OLMS JACK Setup Script"
    echo ""
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandi disponibili:"
    echo "  setup     Configura JACK per OLMS (default)"
    echo "  cleanup   Pulisce i processi e socket JACK"
    echo "  status    Mostra lo stato del sistema JACK"
    echo "  test      Esegue test di connessione JACK"
    echo "  help      Mostra questo aiuto"
    echo ""
    echo "Esempi:"
    echo "  sudo $0 setup    # Configura JACK"
    echo "  sudo $0 cleanup  # Pulisce JACK"
    echo "  $0 status        # Controlla stato"
}

# Main
main() {
    local command="${1:-setup}"
    
    case "$command" in
        "setup")
            setup_jack
            ;;
        "cleanup")
            cleanup_jack
            ;;
        "status")
            check_status
            ;;
        "test")
            if [[ -f "/etc/olms/jack/test.sh" ]]; then
                /etc/olms/jack/test.sh
            else
                error "Script di test non trovato. Eseguire prima 'setup'."
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Comando sconosciuto: $command"
            show_help
            exit 1
            ;;
    esac
}

# Esegui main se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi