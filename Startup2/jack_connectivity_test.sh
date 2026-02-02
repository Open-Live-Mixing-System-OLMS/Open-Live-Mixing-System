#!/bin/bash

# JACK Connectivity Diagnostic Script
# Versione: 1.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/jack_connectivity_test.log"
TARGET_USER="${TARGET_USER:-francesco_ssh}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")

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
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Test 1: Verifica processi JACK
test_jack_processes() {
    log "=== TEST 1: Verifica processi JACK ==="
    
    local jack_pids=$(pgrep -f "jackd" 2>/dev/null || true)
    if [[ -n "$jack_pids" ]]; then
        log "Processi JACK trovati: $jack_pids"
        for pid in $jack_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                log "PID $pid: attivo"
                local cmd=$(ps -p "$pid" -o cmd --no-headers 2>/dev/null || echo "unknown")
                log "  Comando: $cmd"
            else
                warn "PID $pid: non attivo"
            fi
        done
        return 0
    else
        warn "Nessun processo JACK trovato"
        return 1
    fi
}

# Test 2: Verifica socket JACK
test_jack_sockets() {
    log "=== TEST 2: Verifica socket JACK ==="
    
    local socket_found=false
    local socket_dirs=(
        "/dev/shm/jack-olms-*"
        "/dev/shm/jack-*"
        "/tmp/jack-olms-*"
        "/tmp/jack-*"
    )
    
    for socket_pattern in "${socket_dirs[@]}"; do
        for socket_dir in $socket_pattern; do
            if [[ -d "$socket_dir" ]]; then
                log "Socket JACK trovato: $socket_dir"
                socket_found=true
                
                # Verifica permessi
                local perms=$(ls -ld "$socket_dir" | awk '{print $1}')
                log "  Permessi: $perms"
                
                # Verifica contenuto
                if [[ -d "$socket_dir" ]]; then
                    local contents=$(ls -la "$socket_dir" 2>/dev/null || echo "vuoto")
                    log "  Contenuto: $contents"
                fi
            fi
        done
    done
    
    if [[ "$socket_found" == "false" ]]; then
        warn "Nessun socket JACK trovato"
        return 1
    fi
    
    return 0
}

# Test 3: Verifica link simbolici
test_socket_links() {
    log "=== TEST 3: Verifica link simbolici socket ==="
    
    local link_paths=(
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
        "/dev/shm/jack-default_${TARGET_UID}_0"
        "/tmp/jack-default_${TARGET_UID}_0"
    )
    
    local links_working=0
    local total_links=${#link_paths[@]}
    
    for link_path in "${link_paths[@]}"; do
        if [[ -L "$link_path" ]]; then
            local target=$(readlink "$link_path" 2>/dev/null || echo "unknown")
            if [[ -d "$target" ]]; then
                log "Link OK: $link_path -> $target"
                links_working=$((links_working + 1))
            else
                warn "Link rotto: $link_path -> $target"
            fi
        else
            warn "Link non esistente: $link_path"
        fi
    done
    
    log "Link simbolici: $links_working/$total_links funzionanti"
    
    if [[ $links_working -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 4: Test connettività JACK
test_jack_connectivity() {
    log "=== TEST 4: Test connettività JACK ==="
    
    # Test con jack_lsp
    if command -v jack_lsp >/dev/null 2>&1; then
        log "Test connettività con jack_lsp..."
        
        # Test come root
        if sudo -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="/dev/shm/jack-olms-0" jack_lsp >/dev/null 2>&1; then
            log "✅ Connettività JACK come root: OK"
        else
            warn "❌ Connettività JACK come root: FALLITA"
        fi
        
        # Test come utente target
        if sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="/dev/shm/jack-olms-0" jack_lsp >/dev/null 2>&1; then
            log "✅ Connettività JACK come utente $TARGET_USER: OK"
        else
            warn "❌ Connettività JACK come utente $TARGET_USER: FALLITA"
        fi
        
        # Test con diversi path di sessione
        local test_paths=(
            "/dev/shm/jack-olms-0"
            "/dev/shm/jack-olms-${TARGET_UID}"
            "/tmp/jack-olms-0"
            "/tmp/jack-olms-${TARGET_UID}"
        )
        
        for test_path in "${test_paths[@]}"; do
            if [[ -d "$test_path" ]]; then
                if sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="$test_path" jack_lsp >/dev/null 2>&1; then
                    log "✅ Connettività JACK con path $test_path: OK"
                else
                    warn "❌ Connettività JACK con path $test_path: FALLITA"
                fi
            fi
        done
        
        return 0
    else
        warn "jack_lsp non disponibile"
        return 1
    fi
}

# Test 5: Test connettività Ardour
test_ardour_connectivity() {
    log "=== TEST 5: Test connettività Ardour ==="
    
    # Verifica se Ardour è in esecuzione
    local ardour_pids=$(pgrep -f "ardour" 2>/dev/null || true)
    if [[ -n "$ardour_pids" ]]; then
        log "Processi Ardour trovati: $ardour_pids"
        
        # Test porte Ardour
        if command -v jack_lsp >/dev/null 2>&1; then
            local ardour_ports=$(jack_lsp 2>/dev/null | grep -i ardour || true)
            if [[ -n "$ardour_ports" ]]; then
                log "Porte Ardour trovate:"
                echo "$ardour_ports" | while read -r port; do
                    log "  $port"
                done
                return 0
            else
                warn "Nessuna porta Ardour trovata"
                return 1
            fi
        fi
    else
        warn "Nessun processo Ardour in esecuzione"
        return 1
    fi
}

# Test 6: Verifica permessi e accesso
test_permissions() {
    log "=== TEST 6: Verifica permessi e accesso ==="
    
    # Verifica permessi socket
    local socket_dirs=(
        "/dev/shm/jack-*"
        "/tmp/jack-*"
    )
    
    for socket_pattern in "${socket_dirs[@]}"; do
        for socket_dir in $socket_pattern; do
            if [[ -d "$socket_dir" ]]; then
                local perms=$(ls -ld "$socket_dir" | awk '{print $1}')
                log "Socket $socket_dir: permessi $perms"
                
                # Verifica se l'utente può accedere
                if sudo -u "$TARGET_USER" ls "$socket_dir" >/dev/null 2>&1; then
                    log "  Utente $TARGET_USER: accesso consentito"
                else
                    warn "  Utente $TARGET_USER: accesso negato"
                fi
            fi
        done
    done
    
    # Verifica jack-shm-registry
    if [[ -f "/dev/shm/jack-shm-registry" ]]; then
        local perms=$(ls -l "/dev/shm/jack-shm-registry" | awk '{print $1}')
        log "jack-shm-registry: permessi $perms"
    fi
}

# Test 7: Verifica variabili d'ambiente
test_environment_variables() {
    log "=== TEST 7: Verifica variabili d'ambiente ==="
    
    local env_vars=(
        "JACK_DEFAULT_SERVER"
        "JACK_NO_START_SERVER"
        "JACK_PROMISCUOUS_SERVER"
        "JACK_SESSION_DIR"
        "JACK_NO_AUDIO_RESERVATION"
    )
    
    for var in "${env_vars[@]}"; do
        local value=$(printenv "$var" 2>/dev/null || echo "not set")
        log "$var: $value"
    done
    
    # Verifica variabili per utente target
    log "Variabili d'ambiente per utente $TARGET_USER:"
    sudo -u "$TARGET_USER" env | grep -E "^JACK_" | while read -r line; do
        log "  $line"
    done
}

# Test 8: Verifica X11 access
test_x11_access() {
    log "=== TEST 8: Verifica X11 access ==="
    
    # Verifica DISPLAY
    local display="${DISPLAY:-:0}"
    log "DISPLAY: $display"
    
    # Verifica XAUTHORITY
    local xauth_file="/home/${TARGET_USER}/.Xauthority"
    if [[ -f "$xauth_file" ]]; then
        log "XAUTHORITY: $xauth_file (esiste)"
        if [[ -r "$xauth_file" ]]; then
            log "XAUTHORITY: leggibile"
        else
            warn "XAUTHORITY: non leggibile"
        fi
    else
        warn "XAUTHORITY: file non esistente"
    fi
    
    # Verifica X11 connection
    if command -v xdpyinfo >/dev/null 2>&1; then
        if xdpyinfo -display "$display" >/dev/null 2>&1; then
            log "Connessione X11: OK"
        else
            warn "Connessione X11: FALLITA"
        fi
    fi
}

# Report finale
generate_report() {
    log "=== REPORT FINALE ==="
    
    local total_tests=8
    local passed_tests=0
    
    # Conta test passati (basato sui log)
    local passed_count=$(grep -c "✅" "$LOG_FILE" 2>/dev/null || echo "0")
    local failed_count=$(grep -c "❌" "$LOG_FILE" 2>/dev/null || echo "0")
    local warning_count=$(grep -c "WARNING:" "$LOG_FILE" 2>/dev/null || echo "0")
    
    log "Riepilogo test:"
    log "  Test completati: $total_tests"
    log "  Test passati: $passed_count"
    log "  Test falliti: $failed_count"
    log "  Warning: $warning_count"
    
    if [[ $failed_count -eq 0 ]]; then
        log "✅ Tutti i test sono passati - JACK connectivity OK"
    else
        warn "❌ Alcuni test sono falliti - Problemi di connettività JACK"
    fi
    
    if [[ $warning_count -gt 5 ]]; then
        warn "⚠️  Numerosi warning rilevati - Controllare il log per dettagli"
    fi
    
    log "Log dettagliato: $LOG_FILE"
}

# Funzione principale
main() {
    log "=== JACK CONNECTIVITY DIAGNOSTIC SCRIPT ==="
    log "Utente target: $TARGET_USER (UID: $TARGET_UID)"
    log "Timestamp: $(date)"
    
    # Esegui tutti i test
    test_jack_processes
    test_jack_sockets
    test_socket_links
    test_jack_connectivity
    test_ardour_connectivity
    test_permissions
    test_environment_variables
    test_x11_access
    
    # Genera report
    generate_report
    
    log "Diagnostic script completato"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi