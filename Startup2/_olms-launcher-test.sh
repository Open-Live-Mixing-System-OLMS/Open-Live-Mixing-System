#!/bin/bash

# OLMS Orchestrator Launcher - Test Mode
# Double-click this script to start the OLMS system in test mode with graphical interface
# Usage: ./_olms-launcher-test.sh
# This script clears the terminal and runs the orchestrator with sudo privileges in test mode

# Gestione intelligente del percorso home per gestire anche l'esecuzione con sudo
if [[ "$EUID" -eq 0 ]]; then
    # Se siamo root, dobbiamo determinare l'utente effettivo
    if [[ -n "${SUDO_USER:-}" ]]; then
        # Eseguito con sudo, usa l'utente originale
        ACTUAL_HOME=$(eval echo ~$SUDO_USER)
    elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
        # Eseguito come root ma USER è impostato a un utente non root
        ACTUAL_HOME=$(eval echo ~$USER)
    else
        # Eseguito direttamente come root
        ACTUAL_HOME="/root"
    fi
else
    # Eseguito come utente normale
    ACTUAL_HOME="$HOME"
fi

clear && sudo "$ACTUAL_HOME/Progetti/OLMS-Core/Startup2/olms-orchestrator.sh" --test
