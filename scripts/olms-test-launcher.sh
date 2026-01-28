#!/bin/bash

# OLMS Test Launcher Script
# 
# This script launches the Ardour launcher in test mode and provides feedback.

set -e

print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

print_status "=== OLMS Test Launcher ==="
print_status "Avvio script Ardour in modalità test..."

# Get the absolute path to the OLMS-Core directory
OLMS_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check if the ardour_launcher.sh script exists
if [ ! -f "$OLMS_CORE_DIR/scripts/ardour_launcher.sh" ]; then
    print_status "Errore: script ardour_launcher.sh non trovato in $OLMS_CORE_DIR/scripts/"
    exit 1
fi

# Make sure the script is executable
chmod +x "$OLMS_CORE_DIR/scripts/ardour_launcher.sh"

# Launch the Ardour script in test mode
print_status "Esecuzione: $OLMS_CORE_DIR/scripts/ardour_launcher.sh --test"
print_status "Monitorando l'output..."

"$OLMS_CORE_DIR/scripts/ardour_launcher.sh" "$@"

print_status "=== Fine esecuzione ==="
echo "Premi INVIO per chiudere..."
read