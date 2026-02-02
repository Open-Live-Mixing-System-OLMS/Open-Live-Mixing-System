#!/bin/bash

# OLMS Startup Orchestrator
# Gestisce l'intero processo di startup audio real-time
# Versione: 2.0

set -euo pipefail

# Configurazione base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/olms-orchestrator.log"
LOCK_FILE="/tmp/olms-startup.lock"
PID_FILE="/tmp/olms-startup.pid"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
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

# Funzione per verificare se un comando è disponibile
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Comando '$1' non trovato. Installare prima di procedere."
        exit 1
    fi
}

# Pulizia in caso di interruzione
cleanup() {
    # Aggiungo timeout per evitare blocchi
    (
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} Pulizia in corso..." | tee -a "$LOG_FILE"
        if [[ -f "$LOCK_FILE" ]]; then
            rm -f "$LOCK_FILE" 2>/dev/null || true
        fi
        if [[ -f "$PID_FILE" ]]; then
            rm -f "$PID_FILE" 2>/dev/null || true
        fi
    ) &
    local cleanup_pid=$!
    
    # Timeout di 5 secondi per la pulizia
    sleep 5
    if kill -0 $cleanup_pid 2>/dev/null; then
        kill $cleanup_pid 2>/dev/null || true
        wait $cleanup_pid 2>/dev/null || true
    fi
    
    exit 1
}

trap cleanup EXIT INT TERM

# Verifica lock file
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            error "Processo di startup già in esecuzione (PID: $lock_pid)"
            exit 1
        else
            warn "Lock file trovato ma processo non attivo, pulizia in corso..."
            rm -f "$LOCK_FILE" "$PID_FILE"
        fi
    fi
    
    # Crea lock file
    echo $$ > "$LOCK_FILE"
    echo $$ > "$PID_FILE"
    log "Lock file creato: $LOCK_FILE"
}

# Pulizia lock file per evitare conflitti con phase0-lock-management.sh
cleanup_lock_for_phase0() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ "$lock_pid" == "$$" ]]; then
            # Questo è il nostro lock file, rimuoviamolo temporaneamente per phase0
            rm -f "$LOCK_FILE" "$PID_FILE"
            log "Lock file rimosso temporaneamente per phase0-lock-management.sh"
        fi
    fi
}

# Ripristina lock file dopo phase0
restore_lock_after_phase0() {
    if [[ ! -f "$LOCK_FILE" ]]; then
        echo $$ > "$LOCK_FILE"
        echo $$ > "$PID_FILE"
        log "Lock file ripristinato dopo phase0"
    fi
}

# Fase 0: Pre-startup e gestione processi
phase0_pre_startup() {
    log "=== FASE 0: PRE-STARTUP E GESTIONE DEI PROCESSI ==="
    
    # Esegui cleanup audio
    log "Esecuzione cleanup audio environment..."
    if [[ -f "$SCRIPT_DIR/phase0-audio-cleanup.sh" ]]; then
        bash "$SCRIPT_DIR/phase0-audio-cleanup.sh"
    else
        error "Script phase0-audio-cleanup.sh non trovato"
        exit 1
    fi
    
    # Esegui lock file management
    log "Gestione lock file e processi..."
    cleanup_lock_for_phase0
    if [[ -f "$SCRIPT_DIR/phase0-lock-management.sh" ]]; then
        bash "$SCRIPT_DIR/phase0-lock-management.sh"
    else
        error "Script phase0-lock-management.sh non trovato"
        exit 1
    fi
    restore_lock_after_phase0
}

# Fase 1: Ottimizzazione sistema real-time
phase1_rt_optimization() {
    log "=== FASE 1: OTTIMIZZAZIONE SISTEMA REAL-TIME ==="
    
    if [[ -f "$SCRIPT_DIR/phase1-rt-optimization.sh" ]]; then
        bash "$SCRIPT_DIR/phase1-rt-optimization.sh"
    else
        error "Script phase1-rt-optimization.sh non trovato"
        exit 1
    fi
}

# Fase 2: JACK server initialization
phase2_jack_init() {
    log "=== FASE 2: JACK SERVER INITIALIZATION ==="
    
    if [[ -f "$SCRIPT_DIR/phase3-jack-init-fixed.sh" ]]; then
        # Esegui con timeout di 120 secondi per evitare blocchi
        timeout 120 bash "$SCRIPT_DIR/phase3-jack-init-fixed.sh" || {
            error "Fase 2 fallita o timeout superato"
            exit 1
        }
    else
        error "Script phase3-jack-init-fixed.sh non trovato"
        exit 1
    fi
}

# Fase 3: Configurazione hardware e IRQ pinning
phase3_hardware_config() {
    log "=== FASE 3: CONFIGURAZIONE HARDWARE & IRQ PINNING ==="
    
    # Debug: mostra l'EUID corrente
    info "Debug EUID: $EUID (0=root, altro=utente normale)"
    
    # Verifica che lo script sia eseguito come root per la fase hardware
    if [[ $EUID -ne 0 ]]; then
        error "Fase 3 richiede privilegi root. Eseguire con: sudo $0"
        error "Debug: EUID corrente è $EUID, ma è richiesto 0 (root)"
        exit 1
    fi
    
    if [[ -f "$SCRIPT_DIR/phase2-hardware-config.sh" ]]; then
        # Esegui con timeout di 60 secondi per evitare blocchi
        timeout 60 bash "$SCRIPT_DIR/phase2-hardware-config.sh" || {
            error "Fase 3 fallita o timeout superato"
            exit 1
        }
    else
        error "Script phase2-hardware-config.sh non trovato"
        exit 1
    fi
}

# Fase 4: X11 environment setup
phase4_x11_setup() {
    log "=== FASE 4: X11 ENVIRONMENT & DISPLAY MANAGEMENT ==="
    
    if [[ -f "$SCRIPT_DIR/phase4-x11-setup.sh" ]]; then
        bash "$SCRIPT_DIR/phase4-x11-setup.sh"
    else
        error "Script phase4-x11-setup.sh non trovato"
        exit 1
    fi
}

# Fase 5: Ardour DAW startup
phase5_ardour_startup() {
    log "=== FASE 5: ARDOUR DAW STARTUP ==="
    
    if [[ -f "$SCRIPT_DIR/phase5-ardour-startup.sh" ]]; then
        bash "$SCRIPT_DIR/phase5-ardour-startup.sh"
    else
        error "Script phase5-ardour-startup.sh non trovato"
        exit 1
    fi
}

# Fase 6: CPU affinity & resource allocation
phase6_cpu_affinity() {
    log "=== FASE 6: CPU AFFINITY & RESOURCE ALLOCATION ==="
    
    if [[ -f "$SCRIPT_DIR/phase6-cpu-affinity.sh" ]]; then
        bash "$SCRIPT_DIR/phase6-cpu-affinity.sh"
    else
        error "Script phase6-cpu-affinity.sh non trovato"
        exit 1
    fi
}

# Fase 7: System verification & monitoring
phase7_verification() {
    log "=== FASE 7: SYSTEM VERIFICATION & MONITORING ==="
    
    if [[ -f "$SCRIPT_DIR/phase7-verification.sh" ]]; then
        bash "$SCRIPT_DIR/phase7-verification.sh"
    else
        error "Script phase7-verification.sh non trovato"
        exit 1
    fi
}

# Fase 8: Final system state
phase8_final_state() {
    log "=== FASE 8: FINAL SYSTEM STATE & OPERATIONAL READINESS ==="
    
    if [[ -f "$SCRIPT_DIR/phase8-final-state.sh" ]]; then
        bash "$SCRIPT_DIR/phase8-final-state.sh"
    else
        error "Script phase8-final-state.sh non trovato"
        exit 1
    fi
}

# Funzione principale
main() {
    log "Avvio OLMS Startup Orchestrator v2.0"
    log "Script directory: $SCRIPT_DIR"
    log "Log file: $LOG_FILE"
    
    # Verifica comandi necessari
    check_command "pgrep"
    check_command "pkill"
    check_command "kill"
    check_command "taskset"
    check_command "chrt"
    check_command "sysctl"
    
    # Verifica lock file
    check_lock
    
    # Esegui tutte le fasi
    phase0_pre_startup
    phase1_rt_optimization
    phase2_jack_init
    phase3_hardware_config
    phase4_x11_setup
    phase5_ardour_startup
    phase6_cpu_affinity
    phase7_verification
    phase8_final_state
    
    log "=== STARTUP COMPLETATO CON SUCCESSO ==="
    log "OLMS è pronto per l'uso audio real-time"
    
    # Rimuovi trap di cleanup poiché l'esecuzione è completata con successo
    trap - EXIT INT TERM
    
    # Rimuovi lock file
    rm -f "$LOCK_FILE" "$PID_FILE"
}

# Esegui main se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi