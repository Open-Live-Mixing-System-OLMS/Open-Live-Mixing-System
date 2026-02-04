#!/bin/bash

# Audio Output Diagnostic Script
# Diagnostica per problemi di output audio su scheda USB
# Versione: 1.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-audio-diagnostic.log"
ARD_SESSION_PATH="/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"
ARD_USER="francesco_ssh"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
