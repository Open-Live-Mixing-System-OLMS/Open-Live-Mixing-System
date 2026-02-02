#!/bin/bash

# Fase 4: X11 Environment & Display Management
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
XAUTH_FILE=""
XDG_RUNTIME_DIR=""
DISPLAY=""

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

# Rilevamento display avanzato
detect_display() {
    log "Rilevamento display avanzato..."
    
    # Metodo 1: Socket files
    log "Metodo 1: Ricerca socket X11..."
    for i in {0..9}; do
        local socket="/tmp/.X11-unix/X$i"
        if [[ -S "$socket" ]]; then
            DISPLAY=":$i"
            log "Socket X11 trovato: $socket -> DISPLAY=$DISPLAY"
            return 0
        fi
    done
    
    # Metodo 2: xauth entries
    log "Metodo 2: Rilevamento xauth entries..."
    if command -v xauth >/dev/null 2>&1; then
        local xauth_entries=$(xauth list 2>/dev/null || true)
        if [[ -n "$xauth_entries" ]]; then
            log "Entries xauth trovate:"
            echo "$xauth_entries" | while read -r entry; do
                log "  $entry"
            done
            
            # Estrai display number
            local display_from_xauth=$(echo "$xauth_entries" | head -1 | awk '{print $1}' | grep -oE ':[0-9]+' || true)
            if [[ -n "$display_from_xauth" ]]; then
                DISPLAY="$display_from_xauth"
                log "DISPLAY estratto da xauth: $DISPLAY"
                return 0
            fi
        fi
    fi
    
    # Metodo 3: Valori comuni
    log "Metodo 3: Prova valori comuni..."
    local common_displays=(":0" ":1" ":2" ":3")
    for display in "${common_displays[@]}"; do
        if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
            DISPLAY="$display"
            log "DISPLAY trovato: $DISPLAY"
            return 0
        fi
    done
    
    # Metodo 4: Wayland/XWayland
    log "Metodo 4: Rilevamento Wayland/XWayland..."
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
        log "Sessione Wayland rilevata"
        
        # Fallback XWayland
        local xwayland_displays=(":0" ":1" ":2")
        for display in "${xwayland_displays[@]}"; do
            if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
                DISPLAY="$display"
                log "XWayland DISPLAY trovato: $DISPLAY"
                return 0
            fi
        done
    fi
    
    # Metodo 5: Ambienti nidificati (VNC, X2Go, ecc.)
    log "Metodo 5: Rilevamento ambienti nidificati..."
    local nested_displays=(":10" ":11" ":12" ":20" ":21")
    for display in "${nested_displays[@]}"; do
        if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
            DISPLAY="$display"
            log "Ambiente nidificato trovato: $DISPLAY"
            return 0
        fi
    done
    
    # Metodo 6: Rilevamento da processi attivi
    if detect_display_from_processes; then
        return 0
    fi
    
    warn "Nessun display X11 rilevato"
    return 1
}

# Metodo 6: Rilevamento display da processi attivi
detect_display_from_processes() {
    log "Metodo 6: Rilevamento display da processi attivi..."
    
    # Cerca processi X11 attivi
    local x_processes=$(ps aux | grep -E "(Xorg|X11|Xwayland)" | grep -v grep || true)
    if [[ -n "$x_processes" ]]; then
        log "Processi X11 trovati:"
        echo "$x_processes" | while read -r line; do
            log "  $line"
        done
        
        # Estrai display dai processi
        local display_from_proc=$(echo "$x_processes" | grep -oE ':[0-9]+' | head -1 || true)
        if [[ -n "$display_from_proc" ]]; then
            DISPLAY="$display_from_proc"
            log "DISPLAY estratto da processi: $DISPLAY"
            return 0
        fi
    fi
    
    # Cerca processi desktop/window manager
    local wm_processes=$(ps aux | grep -E "(gnome|kde|xfce|mate|cinnamon|lxde|openbox|i3|fluxbox)" | grep -v grep || true)
    if [[ -n "$wm_processes" ]]; then
        log "Processi window manager trovati:"
        echo "$wm_processes" | while read -r line; do
            log "  $line"
        done
        
        # Prova display comuni per ambienti desktop
        local desktop_displays=(":0" ":1")
        for display in "${desktop_displays[@]}"; do
            if [[ -S "/tmp/.X11-unix/X${display#:}" ]]; then
                DISPLAY="$display"
                log "DISPLAY trovato per ambiente desktop: $DISPLAY"
                return 0
            fi
        done
    fi
    
    return 1
}

# Configurazione XAUTHORITY
setup_xauthority() {
    log "Configurazione XAUTHORITY..."
    
    local current_user="${SUDO_USER:-$USER}"
    local home_dir="/home/$current_user"
    
    # Trova .Xauthority file
    if [[ -f "$home_dir/.Xauthority" ]]; then
        XAUTH_FILE="$home_dir/.Xauthority"
        log "XAUTHORITY trovato: $XAUTH_FILE"
    elif [[ -f "/root/.Xauthority" ]] && [[ "$EUID" -eq 0 ]]; then
        XAUTH_FILE="/root/.Xauthority"
        log "XAUTHORITY root trovato: $XAUTH_FILE"
    else
        warn "Nessun file .Xauthority trovato"
        return 1
    fi
    
    # Imposta variabile d'ambiente
    export XAUTHORITY="$XAUTH_FILE"
    log "XAUTHORITY impostato: $XAUTHORITY"
    
    # Concedi accesso root a file utente (se necessario)
    if [[ "$EUID" -eq 0 ]] && [[ "$current_user" != "root" ]]; then
        log "Concedendo accesso root al file .Xauthority utente..."
        if command -v xhost >/dev/null 2>&1; then
            xhost +si:localuser:root 2>/dev/null || warn "Impossibile concedere accesso xhost"
        fi
    fi
    
    return 0
}

# Configurazione XDG_RUNTIME_DIR e D-Bus
setup_xdg_runtime_dir() {
    log "Configurazione XDG_RUNTIME_DIR e D-Bus..."
    
    local current_user="${SUDO_USER:-$USER}"
    local user_id=$(id -u "$current_user" 2>/dev/null || echo "1000")
    
    XDG_RUNTIME_DIR="/run/user/$user_id"
    
    # Verifica esistenza directory
    if [[ -d "$XDG_RUNTIME_DIR" ]]; then
        export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
        log "XDG_RUNTIME_DIR impostato: $XDG_RUNTIME_DIR"
    else
        warn "XDG_RUNTIME_DIR non esiste: $XDG_RUNTIME_DIR"
        
        # Tentativo di creazione (se root)
        if [[ "$EUID" -eq 0 ]]; then
            mkdir -p "$XDG_RUNTIME_DIR"
            chown "$current_user:$current_user" "$XDG_RUNTIME_DIR"
            export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
            log "XDG_RUNTIME_DIR creato: $XDG_RUNTIME_DIR"
        fi
    fi
    
    # Setup D-Bus session per francesco_ssh
    setup_dbus_session "$current_user" "$user_id"
}

# Setup D-Bus session per utente specifico
setup_dbus_session() {
    local target_user="$1"
    local user_id="$2"
    
    log "Setup D-Bus session per utente: $target_user (UID: $user_id)"
    
    # Forza l'indirizzo se il socket esiste ma la variabile è vuota o malformata
    if [[ -S "/run/user/$user_id/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus"
        # IMPORTANTE: Esporta anche questa per app basate su vecchi toolkit
        export DBUS_SESSION_BUS_PID=$(pgrep -u "$target_user" dbus-daemon | head -n 1)
        log "D-Bus session già disponibile: $DBUS_SESSION_BUS_ADDRESS"
    else
        warn "D-Bus session non disponibile, tentativo di avvio..."
        
        # Se siamo root, prova ad avviare D-Bus per l'utente
        if [[ "$EUID" -eq 0 ]]; then
            log "Avvio D-Bus session per utente $target_user..."
            
            # Crea directory D-Bus se necessario
            sudo -u "$target_user" mkdir -p "/run/user/$user_id"
            
            # Avvia D-Bus session
            sudo -u "$target_user" dbus-launch --sh-syntax --exit-with-session > "/tmp/dbus_session_$user_id.env" 2>/dev/null || {
                warn "Impossibile avviare D-Bus session per $target_user"
                return 1
            }
            
            # Carica variabili d'ambiente D-Bus
            if [[ -f "/tmp/dbus_session_$user_id.env" ]]; then
                source "/tmp/dbus_session_$user_id.env"
                export DBUS_SESSION_BUS_ADDRESS
                log "D-Bus session avviato: $DBUS_SESSION_BUS_ADDRESS"
                
                # Cleanup file temporaneo
                rm -f "/tmp/dbus_session_$user_id.env"
            fi
        else
            warn "Non root, impossibile avviare D-Bus session"
        fi
    fi
    
    # Verifica D-Bus connectivity
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        log "D-Bus session address: $DBUS_SESSION_BUS_ADDRESS"
        
        # Test D-Bus connectivity (se disponibile) - eseguito come utente target
        if command -v dbus-send >/dev/null 2>&1; then
            if [[ "$EUID" -eq 0 ]]; then
                if sudo -u "$target_user" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
                    log "D-Bus connectivity verificata per l'utente $target_user"
                else
                    warn "D-Bus connectivity fallita per l'utente $target_user"
                fi
            else
                if dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
                    log "D-Bus connectivity verificata"
                else
                    warn "D-Bus connectivity fallita"
                fi
            fi
        fi
    else
        warn "D-Bus session address non impostato"
    fi
}

# Configurazione X11 permissions
setup_x11_permissions() {
    log "Configurazione X11 permissions..."
    
    local current_user="${SUDO_USER:-$USER}"
    
    # Root-to-user transition
    if [[ "$EUID" -eq 0 ]]; then
        log "Root detected, configurazione transizione utente..."
        
        # Preserva DISPLAY corretto durante sudo
        if [[ -n "$DISPLAY" ]]; then
            export DISPLAY="$DISPLAY"
            log "DISPLAY preservato: $DISPLAY"
        fi
        
        # Concedi accesso X11
        if command -v xhost >/dev/null 2>&1; then
            xhost +si:localuser:"$current_user" 2>/dev/null || warn "Impossibile concedere accesso X11 a $current_user"
        fi
    fi
    
    # Verifica DISPLAY
    if [[ -n "$DISPLAY" ]]; then
        export DISPLAY="$DISPLAY"
        log "DISPLAY impostato: $DISPLAY"
    else
        warn "DISPLAY non impostato"
    fi
}

# Setup Xvfb per modalità headless
setup_xvfb() {
    log "Setup Xvfb per modalità headless..."
    
    if ! command -v Xvfb >/dev/null 2>&1; then
        warn "Xvfb non disponibile"
        return 1
    fi
    
    # Trova display number libero
    local xvfb_display=""
    for i in {99..120}; do
        if ! [[ -S "/tmp/.X11-unix/X$i" ]]; then
            xvfb_display=":$i"
            break
        fi
    done
    
    if [[ -z "$xvfb_display" ]]; then
        warn "Nessun display number libero per Xvfb"
        return 1
    fi
    
    log "Avvio Xvfb su display: $xvfb_display"
    
    # Avvia Xvfb con parametri minimi
    Xvfb "$xvfb_display" -screen 0 1024x768x24 -nolisten tcp -nolisten unix &
    local xvfb_pid=$!
    
    # Attendi avvio
    sleep 2
    
    # Verifica avvio
    if kill -0 "$xvfb_pid" 2>/dev/null; then
        export DISPLAY="$xvfb_display"
        log "Xvfb avviato con successo (PID: $xvfb_pid, DISPLAY: $DISPLAY)"
        return 0
    else
        warn "Xvfb non avviato correttamente"
        return 1
    fi
}

# Verifica configurazione X11
verify_x11_setup() {
    log "Verifica configurazione X11..."
    
    # Verifica DISPLAY
    if [[ -n "${DISPLAY:-}" ]]; then
        log "DISPLAY: $DISPLAY"
    else
        warn "DISPLAY non impostato"
    fi
    
    # Verifica XAUTHORITY
    if [[ -n "${XAUTHORITY:-}" ]]; then
        log "XAUTHORITY: $XAUTHORITY"
    else
        warn "XAUTHORITY non impostato"
    fi
    
    # Verifica XDG_RUNTIME_DIR
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        log "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
    else
        warn "XDG_RUNTIME_DIR non impostato"
    fi
    
    # Test connessione X11 (se non in modalità headless)
    if [[ -n "${DISPLAY:-}" ]] && [[ "$DISPLAY" != *":99"* ]] && [[ "$DISPLAY" != *":100"* ]]; then
        if command -v xdpyinfo >/dev/null 2>&1; then
            if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
                log "Connessione X11 verificata"
            else
                warn "Connessione X11 fallita"
            fi
        fi
    fi
    
    # Debug X11 errors (aggiunto per troubleshooting)
    if [[ -f "/tmp/ardour_startup.log" ]]; then
        log "Controllo errori X11 in /tmp/ardour_startup.log..."
        local x11_errors=$(grep -i "display\|x11\|xcb\|qt" /tmp/ardour_startup.log 2>/dev/null || true)
        if [[ -n "$x11_errors" ]]; then
            warn "Errori X11 trovati in ardour_startup.log:"
            echo "$x11_errors" | while read -r line; do
                warn "  $line"
            done
        else
            log "Nessun errore X11 rilevato in ardour_startup.log"
        fi
    fi
}

# Funzione principale
main() {
    log "=== FASE 4: X11 ENVIRONMENT & DISPLAY MANAGEMENT ==="
    
    # Rilevamento display
    if ! detect_display; then
        warn "Display non rilevato, setup Xvfb..."
        if ! setup_xvfb; then
            warn "Xvfb non disponibile, continuo senza GUI"
        fi
    fi
    
    # Configurazione XAUTHORITY
    setup_xauthority
    
    # Configurazione XDG_RUNTIME_DIR
    setup_xdg_runtime_dir
    
    # Configurazione permissions
    setup_x11_permissions
    
    # Verifica setup
    verify_x11_setup
    
    log "Configurazione X11 completata"
    log "Ambiente X11 pronto: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY, XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi