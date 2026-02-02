#!/bin/bash
# Test script for JACK Fixed-Path Socket Strategy
# Versione: 1.0

set -euo pipefail

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $1"
}

# Test 1: Verifica socket path e permessi
test_socket_permissions() {
    log "=== TEST 1: Socket Path and Permissions ==="
    
    # Trova il socket directory creato da JACK
    local socket_dirs=($(find /dev/shm -name "jack-*" -type d 2>/dev/null || true))
    
    if [ ${#socket_dirs[@]} -eq 0 ]; then
        warn "Nessun socket directory JACK trovato"
        return 1
    fi
    
    for socket_dir in "${socket_dirs[@]}"; do
        log "Verifica socket directory: $socket_dir"
        
        # Controlla permessi
        local perms=$(stat -c "%a" "$socket_dir" 2>/dev/null || echo "unknown")
        if [ "$perms" = "777" ]; then
            log "✅ Permessi corretti: $perms"
        else
            warn "Permessi non ottimali: $perms (atteso: 777)"
        fi
        
        # Controlla contenuto
        local socket_files=$(find "$socket_dir" -type s 2>/dev/null | wc -l)
        if [ "$socket_files" -gt 0 ]; then
            log "✅ Socket files trovati: $socket_files"
        else
            warn "Nessun socket file trovato in $socket_dir"
        fi
    done
    
    # Verifica symbolic links
    local user_uid=$(id -u "${TARGET_USER:-francesco_ssh}" 2>/dev/null || echo "1000")
    local user_socket="/dev/shm/jack-olms-${user_uid}"
    local default_socket="/dev/shm/jack-0/default"
    
    if [ -L "$user_socket" ]; then
        log "✅ Symbolic link utente trovato: $user_socket"
    else
        warn "Symbolic link utente mancante: $user_socket"
    fi
    
    if [ -L "$default_socket" ]; then
        log "✅ Symbolic link default trovato: $default_socket"
    else
        warn "Symbolic link default mancante: $default_socket"
    fi
    
    return 0
}

# Test 2: Verifica connettività JACK
test_jack_connectivity() {
    log "=== TEST 2: JACK Connectivity ==="
    
    # Test base connectivity
    if sudo -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
        log "✅ JACK connectivity base test passed"
    else
        warn "JACK connectivity base test failed"
        return 1
    fi
    
    # Test con utente specifico
    local target_user="${TARGET_USER:-francesco_ssh}"
    if sudo -u "$target_user" -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
        log "✅ JACK connectivity user test passed for $target_user"
    else
        warn "JACK connectivity user test failed for $target_user"
    fi
    
    # Conta porte disponibili
    local port_count=$(sudo -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | wc -l || echo "0")
    if [ "$port_count" -gt 0 ]; then
        log "✅ Porte JACK disponibili: $port_count"
    else
        warn "Nessuna porta JACK disponibile"
    fi
    
    return 0
}

# Test 3: Verifica stabilità processo
test_process_stability() {
    log "=== TEST 3: Process Stability ==="
    
    # Verifica PID JACK
    local jack_pid=$(cat /tmp/jack.pid 2>/dev/null || echo "")
    if [ -n "$jack_pid" ] && kill -0 "$jack_pid" 2>/dev/null; then
        log "✅ JACK PID attivo: $jack_pid"
        
        # Controlla stato processo
        local proc_status=$(ps -p "$jack_pid" -o state --no-headers 2>/dev/null || echo "unknown")
        if [ "$proc_status" = "S" ] || [ "$proc_status" = "R" ]; then
            log "✅ Stato processo JACK: $proc_status (running/sleeping)"
        else
            warn "Stato processo JACK: $proc_status"
        fi
    else
        warn "JACK PID non attivo o non trovato"
        return 1
    fi
    
    # Verifica assenza di segnali di terminazione
    local signal_count=$(grep -c "SIGINT\|SIGTERM\|killed" /tmp/jack_startup.log 2>/dev/null || echo "0")
    if [[ "$signal_count" == *"0"* ]]; then
        log "✅ Nessun segnale di terminazione rilevato"
    else
        warn "Rilevati $signal_count segnali di terminazione in /tmp/jack_startup.log"
    fi
    
    return 0
}

# Test 4: Verifica integrazione Ardour
test_ardour_integration() {
    log "=== TEST 4: Ardour Integration ==="
    
    # Verifica PID Ardour
    local ardour_pid=$(cat /tmp/ardour.pid 2>/dev/null || echo "")
    if [ -n "$ardour_pid" ] && kill -0 "$ardour_pid" 2>/dev/null; then
        log "✅ Ardour PID attivo: $ardour_pid"
    else
        warn "Ardour PID non attivo o non trovato"
        return 1
    fi
    
    # Verifica porte Ardour
    local ardour_ports=$(sudo -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | grep -i ardour | wc -l 2>/dev/null || echo "0")
    if [ "$ardour_ports" -gt 0 ]; then
        log "✅ Porte Ardour trovate: $ardour_ports"
    else
        warn "Nessuna porta Ardour trovata"
    fi
    
    # Verifica processi audio
    local audio_processes=$(pgrep -f "ardour|jack" 2>/dev/null | wc -l 2>/dev/null || echo "0")
    if [ "$audio_processes" -gt 0 ]; then
        log "✅ Processi audio attivi: $audio_processes"
    else
        warn "Nessun processo audio attivo"
    fi
    
    return 0
}

# Test 5: Verifica D-Bus isolation
test_dbus_isolation() {
    log "=== TEST 5: D-Bus Isolation ==="
    
    # Controlla se dbus-run-session è in esecuzione
    local dbus_session=$(pgrep -f "dbus-run-session" 2>/dev/null | wc -l 2>/dev/null || echo "0")
    if [ "$dbus_session" -gt 0 ]; then
        log "✅ D-Bus session isolation attiva: $dbus_session processi"
    else
        warn "D-Bus session isolation non rilevata"
    fi
    
    # Verifica che JACK non sia collegato al D-Bus di sistema
    local jack_dbus=$(ps aux | grep jackd | grep -v grep | grep -c "dbus" 2>/dev/null || echo "0")
    if [ "$jack_dbus" -eq 0 ]; then
        log "✅ JACK isolato dal D-Bus di sistema"
    else
        warn "JACK potrebbe essere collegato al D-Bus di sistema"
    fi
    
    return 0
}

# Test completo
run_all_tests() {
    log "=== JACK STABILITY TEST SUITE ==="
    log "Fixed-Path Socket Strategy Verification"
    log ""
    
    local tests_passed=0
    local total_tests=5
    
    # Esegui tutti i test
    if test_socket_permissions; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_jack_connectivity; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_process_stability; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_ardour_integration; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_dbus_isolation; then
        tests_passed=$((tests_passed + 1))
    fi
    
    # Riassunto risultati
    log ""
    log "=== RIEPILOGO TEST ==="
    log "Test passed: $tests_passed/$total_tests"
    
    if [ $tests_passed -eq $total_tests ]; then
        log "✅ TUTTI I TEST PASSATI - Sistema stabile"
        return 0
    else
        warn "⚠️  ALCUNI TEST FALLITI - Verificare i problemi"
        return 1
    fi
}

# Funzione principale
main() {
    # Imposta variabili ambiente
    export JACK_DEFAULT_SERVER="olms"
    export TARGET_USER="${TARGET_USER:-francesco_ssh}"
    
    # Esegui test
    run_all_tests
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi