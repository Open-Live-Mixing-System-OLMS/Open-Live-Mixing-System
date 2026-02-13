#!/bin/bash

# OLMS Path Utilities
# Shared library for relative path resolution
# Version: 1.0

# Detect OLMS-Core root directory from any script location
get_olms_core_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # If we're in Startup2, go up one level to OLMS-Core root
    if [[ "$script_dir" == */Startup2 ]]; then
        echo "$script_dir/.."
    else
        # Search for OLMS-Core markers by traversing up directory tree
        local current="$script_dir"
        while [[ "$current" != "/" ]]; do
            if [[ -f "$current/OLMS_specs.md" ]] && [[ -d "$current/Startup2" ]]; then
                echo "$current"
                return 0
            fi
            current="$(dirname "$current")"
        done
        # Final fallback to home directory (maintains compatibility)
        echo "$HOME/Progetti/OLMS-Core"
    fi
}

# Initialize OLMS environment variables
init_olms_paths() {
    # Get the OLMS-Core root directory
    local olms_root="$(get_olms_core_root)"
    
    # Set environment variables
    export OLMS_CORE_ROOT="$olms_root"
    export OLMS_ENGINE_DIR="$olms_root/engine"
    export OLMS_CONFIG_DIR="$olms_root/config"
    export OLMS_STARTUP_DIR="$olms_root/Startup2"
    export OLMS_TEST_DIR="$olms_root/test"
    
    # Session paths
    export OLMS_SESSION_TEMPLATE_DIR="$olms_root/engine/session-template"
    export OLMS_SESSION_DIR="$olms_root/engine/session-template/OLMS-POC"
    export OLMS_SESSION_FILE="$olms_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
    
    # Configuration paths
    export OLMS_REALTIME_CONFIG_DIR="$olms_root/config/realtime"
    export OLMS_SYSTEMD_CONFIG_DIR="$olms_root/config/systemd"
    export OLMS_SCRIPTS_CONFIG_DIR="$olms_root/config/scripts"
    
    # Log directory
    export OLMS_LOG_DIR="$olms_root/logs"
    
    # Create necessary directories
    mkdir -p "$OLMS_LOG_DIR" 2>/dev/null || true
    
    # Debug logging (can be enabled with OLMS_DEBUG=1)
    if [[ "${OLMS_DEBUG:-}" == "1" ]]; then
        echo "OLMS Path Resolution Debug:"
        echo "  OLMS_CORE_ROOT: $OLMS_CORE_ROOT"
        echo "  OLMS_ENGINE_DIR: $OLMS_ENGINE_DIR"
        echo "  OLMS_CONFIG_DIR: $OLMS_CONFIG_DIR"
        echo "  OLMS_STARTUP_DIR: $OLMS_STARTUP_DIR"
        echo "  OLMS_SESSION_FILE: $OLMS_SESSION_FILE"
    fi
}

# Helper functions for consistent path resolution
olms_path() {
    echo "$OLMS_CORE_ROOT/$1"
}

engine_path() {
    echo "$OLMS_ENGINE_DIR/$1"
}

config_path() {
    echo "$OLMS_CONFIG_DIR/$1"
}

startup_path() {
    echo "$OLMS_STARTUP_DIR/$1"
}

test_path() {
    echo "$OLMS_TEST_DIR/$1"
}

session_path() {
