#!/bin/bash

# X11 Diagnostic Script for OLMS
# 
# Questo script verifica che l'ambiente X11 sia correttamente configurato
# prima di procedere con l'avvio di Ardour. Blocca lo startup se rileva
# problemi con X11, evitando fallimenti silenziosi.

set -e

# Function to print status messages
print_status() {
    echo "[$(date '+%H:%M:%S')] $1" >&2
}

# Function to print error messages
print_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

# Function to print warning messages
print_warning() {
    echo "[$(date '+%H:%M:%S')] WARNING: $1" >&2
}

# Function to check if X11 is accessible
check_x11_accessibility() {
    print_status "Checking X11 accessibility..."
    
    # Check if DISPLAY is set
    if [ -z "$DISPLAY" ]; then
        print_error "DISPLAY environment variable is not set"
        return 1
    fi
    
    print_status "DISPLAY is set to: $DISPLAY"
    
    # Check if XAUTHORITY is set
    if [ -z "$XAUTHORITY" ]; then
        print_warning "XAUTHORITY environment variable is not set, using default"
        export XAUTHORITY="$HOME/.Xauthority"
    fi
    
    print_status "XAUTHORITY is set to: $XAUTHORITY"
    
    # Check if XDG_RUNTIME_DIR is set
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        print_warning "XDG_RUNTIME_DIR environment variable is not set, using default"
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi
    
    print_status "XDG_RUNTIME_DIR is set to: $XDG_RUNTIME_DIR"
    
    # Test X11 connection with timeout
    print_status "Testing X11 connection with timeout..."
    if timeout 5 xset q >/dev/null 2>&1; then
        print_status "X11 connection test passed ✓"
        return 0
    else
        print_error "X11 connection test failed"
        print_error "DISPLAY: $DISPLAY"
        print_error "XAUTHORITY: $XAUTHORITY"
        print_error "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
        return 1
    fi
}

# Function to check X11 permissions
check_x11_permissions() {
    print_status "Checking X11 permissions..."
    
    # Check if user can access X server
    if ! xset q >/dev/null 2>&1; then
        print_error "Cannot access X server"
        print_error "This may be due to missing X11 permissions or incorrect DISPLAY/XAUTHORITY"
        return 1
    fi
    
    # Check if XAUTHORITY file exists and is readable
    if [ -n "$XAUTHORITY" ] && [ ! -f "$XAUTHORITY" ]; then
        print_warning "XAUTHORITY file does not exist: $XAUTHORITY"
        print_warning "This may cause issues with X11 authentication"
    elif [ -n "$XAUTHORITY" ] && [ ! -r "$XAUTHORITY" ]; then
        print_error "XAUTHORITY file is not readable: $XAUTHORITY"
        return 1
    fi
    
    # Check if XDG_RUNTIME_DIR exists and is writable
    if [ -n "$XDG_RUNTIME_DIR" ] && [ ! -d "$XDG_RUNTIME_DIR" ]; then
        print_warning "XDG_RUNTIME_DIR does not exist: $XDG_RUNTIME_DIR"
    elif [ -n "$XDG_RUNTIME_DIR" ] && [ ! -w "$XDG_RUNTIME_DIR" ]; then
        print_warning "XDG_RUNTIME_DIR is not writable: $XDG_RUNTIME_DIR"
    fi
    
    print_status "X11 permissions check completed ✓"
    return 0
}

# Function to check X11 display availability
check_x11_display_availability() {
    print_status "Checking X11 display availability..."
    
    # Check if display socket exists
    local display_num=$(echo "$DISPLAY" | sed 's/.*:\([0-9]*\).*/\1/')
    local socket_path="/tmp/.X11-unix/X$display_num"
    
    if [ -S "$socket_path" ]; then
        print_status "X11 socket found at: $socket_path ✓"
    else
        print_warning "X11 socket not found at: $socket_path"
        print_warning "This may indicate that the X server is not running or not accessible"
    fi
    
    # Check for Wayland session
    if [ -n "$WAYLAND_DISPLAY" ]; then
        print_status "Wayland session detected: $WAYLAND_DISPLAY"
        print_status "Checking for XWayland compatibility..."
        
        # Check if XWayland is available
        if xset q >/dev/null 2>&1; then
            print_status "XWayland is working correctly ✓"
        else
            print_error "XWayland is not working correctly"
            print_error "Wayland session may not support X11 applications"
            return 1
        fi
    else
        print_status "No Wayland session detected, using native X11"
    fi
    
    return 0
}

# Function to check X11 user context
check_x11_user_context() {
    print_status "Checking X11 user context..."
    
    # Check if we're running as root and need to access user's X server
    if [ "$EUID" -eq 0 ]; then
        print_status "Running as root, checking user X11 access..."
        
        # Check if SUDO_USER is set
        if [ -z "$SUDO_USER" ]; then
            print_error "SUDO_USER is not set, cannot determine original user"
            return 1
        fi
        
        print_status "Original user: $SUDO_USER"
        
        # Check if root can access user's X server
        if ! sudo -u "$SUDO_USER" xset q >/dev/null 2>&1; then
            print_error "Root cannot access $SUDO_USER's X server"
            print_error "This will prevent Ardour from starting with GUI"
            print_error "Run: xhost +si:localuser:root in the user's X session"
            return 1
        fi
        
        print_status "Root can access user's X server ✓"
    else
        print_status "Running as regular user, checking X11 access..."
        
        if ! xset q >/dev/null 2>&1; then
            print_error "Cannot access X server as current user"
            return 1
        fi
        
        print_status "User can access X server ✓"
    fi
    
    return 0
}

# Function to check X11 environment variables
check_x11_environment_variables() {
    print_status "Checking X11 environment variables..."
    
    # Check for common X11 environment variables
    local required_vars="DISPLAY"
    local optional_vars="XAUTHORITY XDG_RUNTIME_DIR WAYLAND_DISPLAY"
    
    for var in $required_vars; do
        if [ -z "${!var}" ]; then
            print_error "Required environment variable $var is not set"
            return 1
        else
            print_status "$var is set to: ${!var}"
        fi
    done
    
    for var in $optional_vars; do
        if [ -n "${!var}" ]; then
            print_status "$var is set to: ${!var}"
        else
            print_status "$var is not set (optional)"
        fi
    done
    
    return 0
}

# Function to check X11 display resolution and capabilities
check_x11_display_capabilities() {
    print_status "Checking X11 display capabilities..."
    
    # Check display resolution
    if command -v xdpyinfo >/dev/null 2>&1; then
        local resolution=$(xdpyinfo | grep "dimensions:" | awk '{print $2}')
        if [ -n "$resolution" ]; then
            print_status "Display resolution: $resolution"
        fi
        
        # Check color depth
        local depth=$(xdpyinfo | grep "default depth of root window:" | awk '{print $5}')
        if [ -n "$depth" ]; then
            print_status "Display color depth: $depth bits"
        fi
        
        # Check for GLX extension (needed for some audio plugins)
        if xdpyinfo | grep -q "GLX"; then
            print_status "GLX extension available ✓"
        else
            print_warning "GLX extension not available - some audio plugins may not work"
        fi
    else
        print_warning "xdpyinfo not available, cannot check display capabilities"
    fi
    
    return 0
}

# Function to check X11 session type
check_x11_session_type() {
    print_status "Checking X11 session type..."
    
    # Check for desktop environment
    if [ -n "$DESKTOP_SESSION" ]; then
        print_status "Desktop session: $DESKTOP_SESSION"
    fi
    
    # Check for window manager
    if [ -n "$WINDOW_MANAGER" ]; then
        print_status "Window manager: $WINDOW_MANAGER"
    fi
    
    # Check for session type
    if [ -n "$XDG_SESSION_TYPE" ]; then
        print_status "Session type: $XDG_SESSION_TYPE"
    fi
    
    # Check for session desktop
    if [ -n "$XDG_SESSION_DESKTOP" ]; then
        print_status "Session desktop: $XDG_SESSION_DESKTOP"
    fi
    
    return 0
}

# Function to run comprehensive X11 diagnostic
run_x11_diagnostic() {
    print_status "=== X11 Diagnostic Check ==="
    
    local diagnostic_passed=true
    
    # Check X11 accessibility
    if ! check_x11_accessibility; then
        diagnostic_passed=false
    fi
    
    # Check X11 permissions
    if ! check_x11_permissions; then
        diagnostic_passed=false
    fi
    
    # Check X11 display availability
    if ! check_x11_display_availability; then
        diagnostic_passed=false
    fi
    
    # Check X11 user context
    if ! check_x11_user_context; then
        diagnostic_passed=false
    fi
    
    # Check X11 environment variables
    if ! check_x11_environment_variables; then
        diagnostic_passed=false
    fi
    
    # Check X11 display capabilities
    if ! check_x11_display_capabilities; then
        diagnostic_passed=false
    fi
    
    # Check X11 session type
    if ! check_x11_session_type; then
        diagnostic_passed=false
    fi
    
    if [ "$diagnostic_passed" = true ]; then
        print_status "=== X11 Diagnostic Check PASSED ==="
        print_status "X11 environment is ready for Ardour startup"
        return 0
    else
        print_error "=== X11 Diagnostic Check FAILED ==="
        print_error "X11 environment is not ready for Ardour startup"
        print_error "Please fix the issues above before proceeding"
        return 1
    fi
}

# Function to show help
show_help() {
    echo "X11 Diagnostic Script for OLMS"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --help, -h     Show this help message"
    echo "  --verbose, -v  Show verbose output"
    echo ""
    echo "This script verifies that the X11 environment is correctly configured"
    echo "before proceeding with Ardour startup. It will exit with error code 1"
    echo "if any X11 issues are detected, preventing silent startup failures."
}

# Parse command line arguments
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run the diagnostic
if [ "$VERBOSE" = true ]; then
    run_x11_diagnostic
else
    # Run with reduced output for integration into startup scripts
    run_x11_diagnostic 2>&1 | grep -E "(ERROR|WARNING|PASSED|FAILED)"
fi