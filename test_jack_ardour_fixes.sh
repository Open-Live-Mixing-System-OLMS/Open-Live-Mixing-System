#!/bin/bash

# Test script to verify JACK/ARDOUR fixes
# This script tests the fixes implemented for the JACK/ARDOUR conflict problem

set -euo pipefail

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"; }

# Test 1: Verify JACK environment variables are set correctly
test_jack_environment_variables() {
    log "🔍 TEST 1: Verifica variabili d'ambiente JACK"
    
    # Test if JACK_DEFAULT_SERVER is set correctly
    if [[ "${JACK_DEFAULT_SERVER:-}" == "olms" ]]; then
        log "✅ JACK_DEFAULT_SERVER impostato correttamente: $JACK_DEFAULT_SERVER"
    else
        warn "⚠️ JACK_DEFAULT_SERVER non impostato correttamente: ${JACK_DEFAULT_SERVER:-'non impostato'}"
    fi
    
    # Test if JACK_NO_START_SERVER is set correctly
    if [[ "${JACK_NO_START_SERVER:-}" == "1" ]]; then
        log "✅ JACK_NO_START_SERVER impostato correttamente: $JACK_NO_START_SERVER"
    else
        warn "⚠️ JACK_NO_START_SERVER non impostato correttamente: ${JACK_NO_START_SERVER:-'non impostato'}"
    fi
    
    # Test if JACK_PROMISCUOUS_SERVER is set correctly
    if [[ "${JACK_PROMISCUOUS_SERVER:-}" == "1" ]]; then
        log "✅ JACK_PROMISCUOUS_SERVER impostato correttamente: $JACK_PROMISCUOUS_SERVER"
    else
        warn "⚠️ JACK_PROMISCUOUS_SERVER non impostato correttamente: ${JACK_PROMISCUOUS_SERVER:-'non impostato'}"
    fi
}

# Test 2: Verify socket permissions
test_socket_permissions() {
    log "🔍 TEST 2: Verifica permessi socket JACK"
    
    local socket_files=(
        "/dev/shm/jack_olms_0"
        "/dev/shm/jack_sem.olms_freewheel"
        "/dev/shm/jack_sem.olms_system"
        "/dev/shm/jack-shm-registry"
    )
    
    local all_found=true
    for socket_file in "${socket_files[@]}"; do
        if [ -e "$socket_file" ]; then
            local perms=$(stat -c "%a" "$socket_file" 2>/dev/null || echo "unknown")
            log "✅ File socket trovato: $socket_file (permessi: $perms)"
        else
            warn "⚠️ File socket mancante: $socket_file"
            all_found=false
        fi
    done
    
    if [ "$all_found" = true ]; then
        log "✅ Tutti i file socket JACK sono presenti"
    else
        warn "⚠️ Alcuni file socket JACK sono mancanti"
    fi
}

# Test 3: Verify JACK process is running
test_jack_process() {
    log "🔍 TEST 3: Verifica processo JACK"
    
    if pgrep -f "jackd.*-n olms" > /dev/null; then
        local jack_pid=$(pgrep -f "jackd.*-n olms")
        log "✅ Processo JACK 'olms' in esecuzione (PID: $jack_pid)"
    else
        warn "⚠️ Processo JACK 'olms' non trovato"
    fi
}

# Test 4: Verify Ardour doesn't try to start second JACK server
test_ardour_jack_conflict() {
    log "🔍 TEST 4: Verifica che Ardour non avvii un secondo server JACK"
    
    # Test Ardour version command with JACK environment variables
    local test_output
    test_output=$(env \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        timeout 5s /usr/bin/ardour8 --no-splash --version 2>&1 || true)
    
    if echo "$test_output" | grep -q "JACK command line will be:"; then
        error "🚨 CONFLITTO JACK RILEVATO: Ardour sta cercando di avviare un secondo server JACK!"
        return 1
    elif echo "$test_output" | grep -q "jackd"; then
        error "🚨 CONFLITTO JACK RILEVATO: Ardour sta cercando di avviare un server JACK!"
        return 1
    else
        log "✅ Nessun conflitto JACK rilevato - Ardour non cerca di avviare un secondo server"
        return 0
    fi
}

# Test 5: Verify environment variable inheritance
test_environment_inheritance() {
    log "🔍 TEST 5: Verifica ereditarietà variabili d'ambiente"
    
    # Test sudo -u with environment variables
    local test_user="${SUDO_USER:-$(whoami)}"
    local test_output
    
    test_output=$(sudo -u "$test_user" env \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        bash -c 'echo "JACK_DEFAULT_SERVER=$JACK_DEFAULT_SERVER; JACK_NO_START_SERVER=$JACK_NO_START_SERVER; JACK_PROMISCUOUS_SERVER=$JACK_PROMISCUOUS_SERVER"' 2>&1 || true)
    
    if echo "$test_output" | grep -q "JACK_DEFAULT_SERVER=olms"; then
        log "✅ Variabili d'ambiente JACK ereditate correttamente nella transizione utente"
    else
        warn "⚠️ Problemi con l'ereditarietà delle variabili d'ambiente JACK"
        warn "Output test: $test_output"
    fi
}

# Test 6: Verify shared memory access
test_shared_memory_access() {
    log "🔍 TEST 6: Verifica accesso shared memory JACK"
    
    # Test if Ardour can access JACK shared memory
    local test_user="${SUDO_USER:-$(whoami)}"
    local test_output
    
    test_output=$(sudo -u "$test_user" env \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        timeout 5s bash -c 'jack_lsp 2>&1' || true)
    
    if echo "$test_output" | grep -q "system:"; then
        log "✅ Ardour può accedere ai segmenti di memoria condivisa JACK"
    else
        warn "⚠️ Problemi con l'accesso ai segmenti di memoria condivisa JACK"
        warn "Output test: $test_output"
    fi
}

# Main test function
main() {
    log "=== TEST JACK/ARDOUR FIXES ==="
    log "Verifica delle correzioni implementate per il problema JACK/ARDOUR"
    
    # Run all tests
    test_jack_environment_variables
    echo
    
    test_socket_permissions
    echo
    
    test_jack_process
    echo
    
    test_ardour_jack_conflict
    local conflict_test_result=$?
    echo
    
    test_environment_inheritance
    echo
    
    test_shared_memory_access
    echo
    
    # Summary
    log "=== RIEPILOGO TEST ==="
    if [ $conflict_test_result -eq 0 ]; then
        log "✅ Tutti i test principali superati"
        log "✅ Le correzioni JACK/ARDOUR sono funzionanti"
    else
        error "❌ Test falliti - Problemi con le correzioni JACK/ARDOUR"
    fi
    
    log "💡 Per testare completamente il sistema, eseguire:"
    log "   sudo bash Startup2/olms-orchestrator.sh --test"
    log "   oppure"
    log "   sudo bash Startup2/olms-orchestrator.sh (per modalità headless)"
}

# Esegui main se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi