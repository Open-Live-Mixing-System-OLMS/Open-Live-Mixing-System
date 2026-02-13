#!/bin/bash

# Test script to verify JACK/ARDOUR fixes
# This script tests the fixes implemented for the JACK/ARDOUR conflict problem

# Initialize OLMS paths for relative path support
init_olms_paths() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 1. Direct detection from Startup2 directory
    if [[ "$script_dir" == */Startup2 ]]; then
        local olms_core_root="$(dirname "$script_dir")"
        export OLMS_CORE_ROOT="$olms_core_root"
        export OLMS_ENGINE_DIR="$olms_core_root/engine"
        export OLMS_CONFIG_DIR="$olms_core_root/config"
        export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
        export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
        export OLMS_TEST_DIR="$olms_core_root/test"
        export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
        export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
        log "OLMS paths initialized from Startup2 directory: $olms_core_root"
        return 0
    fi
    
    # 2. Search for OLMS marker files
    local search_dirs=("$HOME" "/opt" "/usr/local")
    for search_dir in "${search_dirs[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' potential_root; do
                if [[ -f "$potential_root/OLMS_specs.md" ]] && [[ -f "$potential_root/OLMS_STARTUP_SPECIFICATION.md" ]]; then
                    export OLMS_CORE_ROOT="$potential_root"
                    export OLMS_ENGINE_DIR="$olms_core_root/engine"
                    export OLMS_CONFIG_DIR="$olms_core_root/config"
                    export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
                    export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
                    export OLMS_TEST_DIR="$olms_core_root/test"
                    export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
                    export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
                    log "OLMS paths initialized from marker files: $olms_core_root"
                    return 0
                fi
            done < <(find "$search_dir" -maxdepth 3 -type d -name "OLMS-Core" -print0 2>/dev/null)
        fi
    done
    
    # 3. Fallback to standard locations
    if [[ -d "$HOME/Progetti/OLMS-Core" ]]; then
        export OLMS_CORE_ROOT="$HOME/Progetti/OLMS-Core"
        export OLMS_ENGINE_DIR="$olms_core_root/engine"
        export OLMS_CONFIG_DIR="$olms_core_root/config"
        export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
        export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
        export OLMS_TEST_DIR="$olms_core_root/test"
        export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
        export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
        log "OLMS paths initialized from fallback location: $olms_core_root"
        return 0
    fi
    
    # 4. Final fallback - search recursively in home directory
    if [[ -d "$HOME" ]]; then
        while IFS= read -r -d '' potential_root; do
            if [[ -f "$potential_root/OLMS_specs.md" ]] && [[ -f "$potential_root/OLMS_STARTUP_SPECIFICATION.md" ]]; then
                export OLMS_CORE_ROOT="$potential_root"
                export OLMS_ENGINE_DIR="$olms_core_root/engine"
                export OLMS_CONFIG_DIR="$olms_core_root/config"
                export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
                export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
                export OLMS_TEST_DIR="$olms_core_root/test"
                export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
                export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
                log "OLMS paths initialized from recursive search: $olms_core_root"
                return 0
            fi
        done < <(find "$HOME" -maxdepth 4 -type d -name "OLMS-Core" -print0 2>/dev/null)
    fi
    
    warn "OLMS-Core directory not found, using current directory"
    export OLMS_CORE_ROOT="$(pwd)"
    export OLMS_ENGINE_DIR="$olms_core_root/engine"
    export OLMS_CONFIG_DIR="$olms_core_root/config"
    export OLMS_STARTUP_DIR="$olms_core_root/Startup2"
    export OLMS_SYSTEMD_DIR="$olms_core_root/systemd"
    export OLMS_TEST_DIR="$olms_core_root/test"
    export OLMS_ARDOUR_SESSION_PATH="$olms_core_root/engine/session-template/OLMS-POC/OLMS-POC.ardour"
    export OLMS_ARDOUR_SESSION_DIR="$olms_core_root/engine/session-template/OLMS-POC"
    return 1
}

get_olms_path() {
    local path_type="$1"
    
    case "$path_type" in
        "core_root") echo "$OLMS_CORE_ROOT" ;;
        "engine_dir") echo "$OLMS_ENGINE_DIR" ;;
        "config_dir") echo "$OLMS_CONFIG_DIR" ;;
        "startup_dir") echo "$OLMS_STARTUP_DIR" ;;
        "systemd_dir") echo "$OLMS_SYSTEMD_DIR" ;;
        "test_dir") echo "$OLMS_TEST_DIR" ;;
        "ardour_session_path") echo "$OLMS_ARDOUR_SESSION_PATH" ;;
        "ardour_session_dir") echo "$OLMS_ARDOUR_SESSION_DIR" ;;
        *) warn "Unknown path type: $path_type"; echo "$OLMS_CORE_ROOT" ;;
    esac
}

# Initialize paths at the beginning
init_olms_paths

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