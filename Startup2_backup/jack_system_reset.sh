#!/bin/bash

# JACK System Reset Script
# Versione: 1.0
# Scopo: Ripristinare rapidamente il sistema JACK in caso di problemi di connettività

set -euo pipefail

# Configurazione
TARGET_USER="${TARGET_USER:-francesco_ssh}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")
ACTUAL_SOCKET="/dev/shm/jack_olms_0"

# Colori
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

# Termina tutti i processi JACK
kill_jack_processes() {
    log "Terminazione processi JACK..."
    
    # Termina processi jackd
    sudo pkill -f jackd 2>/dev/null || true
    sleep 1
    
    # Verifica che i processi siano terminati
    if pgrep -f jackd >/dev/null 2>&1; then
        warn "Alcuni processi JACK sono ancora attivi, terminazione forzata..."
        sudo pkill -9 -f jackd 2>/dev/null || true
        sleep 1
    fi
    
    log "Processi JACK terminati"
}

# Pulisce i socket e i link corrotti
cleanup_jack_files() {
    log "Pulizia socket e link JACK..."
    
    # Rimuovi link corrotti
    sudo rm -f /tmp/jack-default_1000_0 /tmp/jack-olms-1000 2>/dev/null || true
    sudo rm -rf /dev/shm/jack-0 /tmp/jack-0 /dev/shm/jack_db-0 2>/dev/null || true
    
    # Rimuovi file di log temporanei
    sudo rm -f /tmp/jack.pid /tmp/jack_connectivity_test.log /tmp/jack_startup.log 2>/dev/null || true
    
    log "File JACK puliti"
}

# Crea i link simbolici necessari
create_jack_links() {
    log "Creazione link simbolici JACK..."
    
    # Crea la directory socket se non esiste
    sudo mkdir -p "$ACTUAL_SOCKET"
    sudo chmod -R 777 "$ACTUAL_SOCKET"
    
    # Link da creare che puntano al socket reale di JACK
    local links_to_create=(
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
        "/dev/shm/jack-default_${TARGET_UID}_0"
        "/tmp/jack-default_${TARGET_UID}_0"
    )
    
    for link_path in "${links_to_create[@]}"; do
        local link_dir=$(dirname "$link_path")
        sudo mkdir -p "$link_dir"
        
        if [[ ! -L "$link_path" ]]; then
            sudo ln -sfn "$ACTUAL_SOCKET" "$link_path" 2>/dev/null || true
            log "Creato link: $link_path -> $ACTUAL_SOCKET"
        else
            log "Link già esistente: $link_path"
        fi
    done
    
    # Imposta permessi corretti
    sudo chmod -R 777 /dev/shm/jack-* /tmp/jack-* 2>/dev/null || true
    sudo chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
    
    log "Link JACK creati e configurati"
}

# Verifica la connettività JACK
verify_connectivity() {
    log "Verifica connettività JACK..."
    
    # Test con diversi path
    local test_paths=(
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
    )
    
    local connectivity_working=false
    
    for test_path in "${test_paths[@]}"; do
        if [[ -d "$test_path" ]]; then
            if sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="$test_path" jack_lsp >/dev/null 2>&1; then
                log "✅ Connettività JACK OK con path: $test_path"
                connectivity_working=true
                break
            else
                warn "❌ Connettività JACK FALLITA con path: $test_path"
            fi
        fi
    done
    
    if [[ "$connectivity_working" == "true" ]]; then
        log "✅ Connettività JACK ripristinata"
        return 0
    else
        warn "⚠️  Connettività JACK ancora fallita"
        return 1
    fi
}

# Avvia il server JACK
start_jack_server() {
    log "Avvio server JACK..."
    
    # Avvia JACK in background
    sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms jackd -d alsa -d hw:1 -r 48000 -p 1024 -n 2 -s -S >/dev/null 2>&1 &
    local jack_pid=$!
    
    # Attendi che JACK si avvii
    sleep 3
    
    # Verifica che JACK sia attivo
    if kill -0 $jack_pid 2>/dev/null; then
        log "✅ Server JACK avviato (PID: $jack_pid)"
        return 0
    else
        error "❌ Impossibile avviare il server JACK"
        return 1
    fi
}

# Test finale completo
final_test() {
    log "Test finale completo..."
    
    # Test connettività
    if ! verify_connectivity; then
        error "❌ Test connettività fallito"
        return 1
    fi
    
    # Test jack_lsp
    if ! sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
        error "❌ Test jack_lsp fallito"
        return 1
    fi
    
    # Test jack_control
    if ! sudo -u "$TARGET_USER" -E JACK_DEFAULT_SERVER=olms jack_control status >/dev/null 2>&1; then
        error "❌ Test jack_control fallito"
        return 1
    fi
    
    log "✅ Tutti i test superati"
    return 0
}

# Funzione principale
main() {
    log "=== JACK SYSTEM RESET SCRIPT ==="
    log "Utente target: $TARGET_USER (UID: $TARGET_UID)"
    log "Socket directory: $ACTUAL_SOCKET"
    
    # Passo 1: Termina processi JACK
    kill_jack_processes
    
    # Passo 2: Pulizia file
    cleanup_jack_files
    
    # Passo 3: Crea link
    create_jack_links
    
    # Passo 4: Avvia server JACK
    if ! start_jack_server; then
        error "Impossibile avviare il server JACK"
        exit 1
    fi
    
    # Passo 5: Test finale
    if final_test; then
        log "✅ JACK System Reset completato con successo"
        log "Il sistema JACK è ora funzionante e pronto all'uso"
    else
        error "❌ JACK System Reset fallito"
        error "Controllare i log per ulteriori dettagli"
        exit 1
    fi
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi