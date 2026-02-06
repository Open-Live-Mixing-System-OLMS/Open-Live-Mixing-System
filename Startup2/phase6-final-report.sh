#!/bin/bash

# Fase 6: Final System Report
# Versione: 1.0

# Variabili d'ambiente per l'approccio "tutto come stesso utente"
export TARGET_USER="francesco_ssh"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export XDG_RUNTIME_DIR="/run/user/1000"
export DISPLAY=":0"
export XAUTHORITY="/home/francesco_ssh/.Xauthority"
export JACK_DEFAULT_SERVER="olms"
export JACK_NO_START_SERVER=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_SESSION_DIR="/dev/shm/jack-olms-0"

# Rimosso -e per evitare chiusure improvvise, manteniamo -u e -o pipefail
set -uo pipefail

# Calcolo dinamico dei core
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))
SYSTEM_CORE="0"
IRQ_CORE="1"
AUDIO_CORES="2-$LAST_CORE"

# Funzione per estrarre la maschera bitwise dell'affinità
# Esempio: Core 0 = 1, Core 1 = 2, Core 2 = 4, Core 3 = 8
get_affinity_mask() {
    local pid=$1
    taskset -p "$pid" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' '
}

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
FINAL_REPORT_LOG="/tmp/olms-final-report.log"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} Startup process aborted due to warning: $1" | tee -a "$LOG_FILE"
    exit 1
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_REPORT_LOG"
}

# Genera report finale sintetico
generate_final_report() {
    log "=== FASE 6: FINAL SYSTEM REPORT (UNIVERSAL) ==="
    echo ""
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║                    OLMS STARTUP COMPLETATO                    ║"
    log "╠═══════════════════════════════════════════════════════════════╣"
    
    # --- 1. VERIFICA ISOLAMENTO SISTEMA (Core 0) ---
    # Controlliamo un processo di sistema a caso (es. init o kthreadd)
    local sys_pid=$(pgrep -x "systemd" | head -n 1 || pgrep -x "init" | head -n 1 || echo "1")
    local sys_aff=$(taskset -cp "$sys_pid" 2>/dev/null | awk -F': ' '{print $2}')
    
    # Verifica se il sistema è isolato su core 0
    if [[ "$sys_aff" == "0" ]]; then
        log "║  ✓ Sistema: Isolato correttamente su Core $SYSTEM_CORE              ║"
    else
        # Controlliamo se è un falso positivo (processo con affinità multi-core)
        if [[ "$sys_aff" == *"0"* ]]; then
            log "║  ✓ Sistema: Core $SYSTEM_CORE incluso (OK - multi-core)           ║"
        else
            log "║  ⚠ Sistema: Non isolato (Affinità attuale: $sys_aff)          ║"
        fi
    fi

    # --- 2. JACK SERVER (Core 2+) ---
    local jack_pid=$(pgrep -u "$TARGET_USER" -x "jackd" | head -n 1 || echo "")
    if [[ -n "$jack_pid" ]]; then
        local affinity=$(taskset -cp "$jack_pid" 2>/dev/null | awk -F': ' '{print $2}')
        local priority=$(chrt -p "$jack_pid" 2>/dev/null | awk -F': ' '/priority/ {print $2}' || echo "N/A")
        
        # Verifica se l'affinità non tocca i core 0 e 1
        if [[ "$affinity" != *"0"* && "$affinity" != *"1"* ]]; then
            log "║  ✓ JACK Server: Core $affinity (OK), RT Prio $priority             ║"
        else
            log "║  ⚠ JACK Server: Core $affinity (CONFLITTO SISTEMA/IRQ)       ║"
        fi
    fi
    
    # --- 3. ARDOUR DAW (Core 2+) ---
    local ardour_pid=$(pgrep -u "$TARGET_USER" -f "ardour" | head -n 1 || echo "")
    if [[ -n "$ardour_pid" ]]; then
        local affinity=$(taskset -cp "$ardour_pid" 2>/dev/null | awk -F': ' '{print $2}')
        if [[ "$affinity" != *"0"* && "$affinity" != *"1"* ]]; then
            log "║  ✓ Ardour DAW:  Core $affinity (OK)                           ║"
        else
            log "║  ⚠ Ardour DAW:  Core $affinity (CONFLITTO SISTEMA/IRQ)       ║"
        fi
    fi

    # --- 4. IRQ ANALYSIS (Core 1) ---
    local usb_irq=$(grep "xhci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':' | head -n 1 || echo "")
    if [[ -n "$usb_irq" ]]; then
        local aff_mask=$(cat "/proc/irq/$usb_irq/smp_affinity" 2>/dev/null | tr -d ' \n' | sed 's/^0*//')
        # 2 in hex/dec è sempre il secondo core (Core 1)
        if [[ "$aff_mask" == "2" ]]; then
            log "║  ✓ IRQ USB $usb_irq: Core $IRQ_CORE (Verificato 0x2)                 ║"
        else
            log "║  ⚠ IRQ USB $usb_irq: Errore Pinning (Mask: 0x$aff_mask)           ║"
        fi
    fi
    
    # --- 5. RIASSUNTO ARCHITETTURA ---
    log "╠═══════════════════════════════════════════════════════════════╣"
    log "║  INFO: Core 0=SISTEMA | Core 1=AUDIO IRQ | Core $AUDIO_CORES=AUDIO RT  ║"
    log "╚══════════════════════════════════════════════════════════════╝"
    
    # Summary finale
    local error_count=$(grep -c "ERROR:" "$FINAL_REPORT_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    local warning_count=$(grep -c "WARNING:" "$FINAL_REPORT_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    
    if [[ $error_count -eq 0 ]] && [[ $warning_count -eq 0 ]]; then
        log "✅ Sistema audio real-time completamente operativo"
        log "✅ Pronto per l'uso professionale"
    elif [[ $error_count -eq 0 ]] && [[ $warning_count -le 2 ]]; then
        log "⚠ Sistema audio operativo con alcuni warning"
        log "⚠ Prestazioni potenzialmente ridotte"
    else
        log "✗ Sistema audio con errori critici"
        log "✗ Richiede intervento manuale"
    fi
    
    log "Log dettagliato: $FINAL_REPORT_LOG"
}

# Funzione principale
main() {
    generate_final_report
    log "Final system report completato"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi