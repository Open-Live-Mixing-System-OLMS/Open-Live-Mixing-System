#!/bin/bash

# OLMS Startup Orchestrator
# Gestisce l'intero processo di startup audio real-time
# Versione: 2.0

set -euo pipefail

# Configurazione base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLMS_HOME="$HOME/.olms"
mkdir -p "$OLMS_HOME"
LOG_FILE="$OLMS_HOME/olms-orchestrator.log"
LOCK_FILE="$OLMS_HOME/olms-startup.lock"
PID_FILE="$OLMS_HOME/olms-startup.pid"

# Aggiornamento Log File in Orchestrator - Versione "aggressiva"
if [[ -f "/tmp/olms-orchestrator.log" ]]; then
    # Se il file in /tmp esiste ed è di un altro utente, lo ignoriamo del tutto
    # o usiamo un nome univoco per evitare il 'Permission denied'
    LOG_FILE="/tmp/olms-orchestrator-${USER}-$(date +%s).log"
fi

# Assicurati che il file di log sia scrivibile dall'utente corrente
if [[ ! -f "$LOG_FILE" ]]; then
    # Crea il file di log se non esiste
    touch "$LOG_FILE" 2>/dev/null || {
        # Se non possiamo creare il file nella home, usiamo un percorso alternativo
        LOG_FILE="/tmp/olms-orchestrator-${USER}-$(date +%s).log"
        warn "Impossibile creare il file di log nella home directory, uso: $LOG_FILE"
    }
elif [[ ! -w "$LOG_FILE" ]]; then
    # Se il file esiste ma non è scrivibile, creane uno nuovo con timestamp univoco
    LOG_FILE="/tmp/olms-orchestrator-${USER}-$(date +%s).log"
    warn "Il file di log esistente non è scrivibile, uso: $LOG_FILE"
fi

# Parsing argomenti
MODE="headless"  # default
if [[ "${1:-}" == "--test" ]]; then
    MODE="test"
    shift
fi

# Variabili d'ambiente per l'approccio "tutto come stesso utente"
export TARGET_USER="francesco_ssh"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export XDG_RUNTIME_DIR="/run/user/1000"
export DISPLAY=":0"
export XAUTHORITY="/home/francesco_ssh/.Xauthority"

# Variabili JACK per coerenza tra tutti gli script
export JACK_DEFAULT_SERVER="olms"
export JACK_NO_AUDIO_RESERVATION=1
export JACK_PROMISCUOUS_SERVER=1

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
    error "Startup process aborted due to warning: $1"
    exit 1
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
    log "Pulizia in corso..."
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    if [[ -f "$PID_FILE" ]]; then
        rm -f "$PID_FILE" 2>/dev/null || true
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
            log "Lock file trovato ma processo non attivo, pulizia automatica in corso..."
            # Pulizia automatica forzata
            sudo rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
            # Verifica che la pulizia sia avvenuta
            if [[ -f "$LOCK_FILE" ]]; then
                warn "Impossibile rimuovere lock file, tentativo con kill -9..."
                sudo kill -9 "$lock_pid" 2>/dev/null || true
                sleep 1
                sudo rm -f "$LOCK_FILE" "$PID_FILE" 2>/dev/null || true
            fi
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
    
    if [[ -f "$SCRIPT_DIR/phase2-hardware-config.sh" ]]; then
        # Esegui con timeout di 60 secondi per evitare blocchi
        timeout 60 bash "$SCRIPT_DIR/phase2-hardware-config.sh" || {
            error "Fase 2 fallita o timeout superato"
            exit 1
        }
    else
        error "Script phase2-hardware-config.sh non trovato"
        exit 1
    fi
}

# Fase 3: JACK server initialization (FIXED VERSION)
phase3_jack_init_fixed() {
    log "=== FASE 3: JACK SERVER INITIALIZATION (FIXED) ==="
    
    if [[ -f "$SCRIPT_DIR/phase3-jack-init-fixed.sh" ]]; then
        # Esegui con timeout di 120 secondi per evitare blocchi
        timeout 120 bash "$SCRIPT_DIR/phase3-jack-init-fixed.sh" || {
            error "Fase 3 fallita o timeout superato"
            exit 1
        }
    else
        error "Script phase3-jack-init-fixed.sh non trovato"
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
        log "Avvio script phase5-ardour-startup.sh..."
        log "Questo script eseguirà la transizione utente a francesco_ssh per avviare Ardour"
        bash "$SCRIPT_DIR/phase5-ardour-startup.sh"
        log "Script phase5-ardour-startup.sh completato"
    else
        error "Script phase5-ardour-startup.sh non trovato"
        exit 1
    fi
}

# Fase 6: Final System Report
phase6_final_report() {
    log "=== FASE 6: FINAL SYSTEM REPORT ==="
    
    if [[ -f "$SCRIPT_DIR/phase6-final-report.sh" ]]; then
        bash "$SCRIPT_DIR/phase6-final-report.sh"
    else
        error "Script phase6-final-report.sh non trovato"
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
    log "Modalità di avvio: $MODE"
    
    # Verifica comandi necessari
    check_command "pgrep"
    check_command "pkill"
    check_command "kill"
    check_command "taskset"
    check_command "chrt"
    check_command "sysctl"
    
    # Verifica lock file
    check_lock
    
    # Esegui fasi in base alla modalità
    if [[ "$MODE" == "test" ]]; then
        log "=== MODALITÀ TEST: Avvio completo con interfaccia grafica ==="
        phase0_pre_startup
        phase1_rt_optimization
        phase2_jack_init
        phase3_jack_init_fixed
        phase4_x11_setup
        # Passa la modalità alla fase 5
        export OLMS_MODE="test"
        phase5_ardour_startup
    else
        log "=== MODALITÀ HEADLESS: Avvio senza interfaccia grafica ==="
        phase0_pre_startup
        phase1_rt_optimization
        phase2_jack_init
        phase3_jack_init_fixed
        # Avvia Ardour in modalità headless (senza interfaccia grafica)
        export OLMS_MODE="headless"
        phase5_ardour_startup
    fi
    phase6_final_report
    
    log "=== STARTUP COMPLETATO CON SUCCESSO ==="
    if [[ "$MODE" == "test" ]]; then
        log "OLMS è pronto per l'uso audio real-time con interfaccia grafica"
    else
        log "OLMS è pronto per l'uso audio real-time in modalità headless"
    fi
    
    # Rimuovi trap di cleanup poiché l'esecuzione è completata con successo
    trap - EXIT INT TERM
    
    # Rimuovi lock file
    rm -f "$LOCK_FILE" "$PID_FILE"
}

# Esegui main se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi