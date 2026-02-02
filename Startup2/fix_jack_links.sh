#!/bin/bash

# JACK Links Fix Script
# Versione: 1.0

set -euo pipefail

# Configurazione
TARGET_USER="${TARGET_USER:-francesco_ssh}"
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")
ACTUAL_SOCKET="/dev/shm/jack-olms-0"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Crea tutti i link simbolici necessari
create_jack_links() {
    log "Creazione link simbolici JACK completi..."
    
    # JACK usa effettivamente il socket: /dev/shm/jack_olms_0 (con underscore)
    local actual_jack_socket="/dev/shm/jack_olms_0"
    
    # Crea la directory socket se non esiste
    sudo mkdir -p "$actual_jack_socket"
    sudo chmod -R 777 "$actual_jack_socket"
    
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
            sudo ln -sfn "$actual_jack_socket" "$link_path" 2>/dev/null || true
            log "Creato link: $link_path -> $actual_jack_socket"
        else
            log "Link già esistente: $link_path"
        fi
    done
    
    # Verifica tutti i link
    log "Verifica link completi..."
    local all_links=(
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-${TARGET_UID}"
        "/dev/shm/jack-0/default"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-${TARGET_UID}"
        "/tmp/jack-0/default"
        "/dev/shm/jack-default_${TARGET_UID}_0"
        "/tmp/jack-default_${TARGET_UID}_0"
    )
    
    local working_links=0
    for link in "${all_links[@]}"; do
        if [[ -L "$link" ]] && [[ -S "$(readlink "$link" 2>/dev/null || echo "")" ]]; then
            log "✓ Link funzionante: $link"
            working_links=$((working_links + 1))
        else
            warn "✗ Link non funzionante: $link"
        fi
    done
    
    log "Link funzionanti: $working_links/${#all_links[@]}"
    
    if [[ $working_links -eq ${#all_links[@]} ]]; then
        log "✅ Tutti i link JACK sono stati creati correttamente"
        return 0
    else
        warn "⚠️  Alcuni link non sono funzionanti"
        return 1
    fi
}

# Imposta permessi corretti
set_permissions() {
    log "Impostazione permessi JACK..."
    
    # Permessi per tutte le directory socket
    sudo chmod -R 777 /dev/shm/jack-* 2>/dev/null || true
    sudo chmod -R 777 /tmp/jack-* 2>/dev/null || true
    sudo chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
    
    log "Permessi impostati su tutte le directory socket"
}

# Test connettività dopo il fix
test_connectivity() {
    log "Test connettività JACK dopo il fix..."
    
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
        warn "❌ Connettività JACK ancora fallita"
        return 1
    fi
}

# Funzione principale
main() {
    log "=== JACK LINKS FIX SCRIPT ==="
    log "Utente target: $TARGET_USER (UID: $TARGET_UID)"
    log "Socket directory: $ACTUAL_SOCKET"
    
    # Crea link
    if ! create_jack_links; then
        error "Errore nella creazione dei link"
        exit 1
    fi
    
    # Imposta permessi
    set_permissions
    
    # Test connettività
    if test_connectivity; then
        log "✅ Fix completato con successo"
    else
        warn "⚠️  Fix parziale - potrebbero essere necessarie ulteriori azioni"
    fi
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi