#!/bin/bash

# Fase 1: System Real-Time Optimization
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
RT_CONFIG_FILE="/etc/sysctl.d/99-olms-rt.conf"
LIMITS_FILE="/etc/security/limits.d/99-realtime.conf"
MODE="${OLMS_RT_MODE:-prod}"  # prod, test, light

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

# Configurazione kernel parameters
configure_kernel_parameters() {
    log "Configurazione kernel parameters RT..."
    
    # Determina i valori in base alla modalità
    local rt_runtime rt_period
    
    case "$MODE" in
        "prod")
            rt_runtime=950000  # 95% CPU per RT
            rt_period=1000000  # 1 secondo periodo
            ;;
        "test")
            rt_runtime=800000  # 80% CPU per RT (lascia 20% per GUI/debug)
            rt_period=1000000
            ;;
        "light")
            rt_runtime=600000  # 60% CPU per RT (per ambienti debug pesanti)
            rt_period=1000000
            ;;
        *)
            rt_runtime=950000
            rt_period=1000000
            warn "Modalità sconosciuta: $MODE, uso default (prod)"
            ;;
    esac
    
    log "Modalità: $MODE - RT Runtime: ${rt_runtime}μs, RT Period: ${rt_period}μs"
    
    # Verifica se il file di configurazione esiste già
    if [[ -f "$RT_CONFIG_FILE" ]]; then
        log "File di configurazione RT già esistente: $RT_CONFIG_FILE"
        log "Saltando creazione file (richiede privilegi root)"
    else
        # Crea file di configurazione solo se non esiste
        if ! cat > "$RT_CONFIG_FILE" << EOF
# OLMS Real-Time Kernel Parameters
# Mode: $MODE

# Real-time scheduling parameters
kernel.sched_rt_runtime_us = $rt_runtime
kernel.sched_rt_period_us = $rt_period

# Additional RT optimizations
kernel.sched_migration_cost_ns = 500000
kernel.sched_wakeup_granularity_ns = 1000000
EOF
        then
            error "Impossibile scrivere in $RT_CONFIG_FILE (permessi insufficienti)"
            error "Esegui lo script con sudo oppure esegui manualmente:"
            error "sudo tee $RT_CONFIG_FILE << 'EOF'"
            error "# OLMS Real-Time Kernel Parameters"
            error "# Mode: $MODE"
            error ""
            error "# Real-time scheduling parameters"
            error "kernel.sched_rt_runtime_us = $rt_runtime"
            error "kernel.sched_rt_period_us = $rt_period"
            error ""
            error "# Additional RT optimizations"
            error "kernel.sched_migration_cost_ns = 500000"
            error "kernel.sched_wakeup_granularity_ns = 1000000"
            error "EOF"
            return 1
        fi
    fi
    
    # Applica la configurazione se il file esiste
    if [[ -f "$RT_CONFIG_FILE" ]]; then
        if sysctl -p "$RT_CONFIG_FILE" &>/dev/null; then
            log "Kernel parameters RT applicati con successo"
        else
            # Prova con sudo se non siamo root
            if [[ $EUID -ne 0 ]]; then
                if sudo sysctl -p "$RT_CONFIG_FILE" &>/dev/null; then
                    log "Kernel parameters RT applicati con successo (con sudo)"
                else
                    warn "Impossibile applicare kernel parameters RT (richiede sudo)"
                    warn "Verifica che i parametri siano già applicati o esegui: sudo sysctl -p $RT_CONFIG_FILE"
                fi
            else
                warn "Impossibile applicare kernel parameters RT"
            fi
        fi
    else
        warn "File di configurazione RT non trovato, impossibile applicare parametri"
    fi
    
    # Verifica applicazione
    local current_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
    local current_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "0")
    
    if [[ "$current_runtime" == "$rt_runtime" ]] && [[ "$current_period" == "$rt_period" ]]; then
        log "Kernel parameters verificati: runtime=$current_runtime, period=$current_period"
    else
        warn "Kernel parameters non corrispondenti: runtime=$current_runtime, period=$current_period"
    fi
}

# Configurazione CPU governor
configure_cpu_governor() {
    log "Configurazione CPU governor per prestazioni..."
    
    local num_cores=$(nproc)
    log "Numero core rilevati: $num_cores"
    
    # Verifica se siamo root per evitare tentativi inutili
    if [[ $EUID -ne 0 ]]; then
        warn "Esecuzione non come root - alcune operazioni potrebbero fallire"
        warn "Per un setup completo, esegui: sudo $0"
    fi
    
    # Applica performance mode a tutti i core
    local success_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            
            # Verifica preventiva dei permessi
            if [[ ! -w "$governor_file" ]]; then
                warn "Permessi insufficienti per modificare $governor_file"
                warn "Esegui: sudo chown $USER $governor_file oppure usa sudo"
                continue
            fi
            
            # Tentativo 1: Scrittura diretta
            if echo "performance" > "$governor_file" 2>/dev/null; then
                log "CPU $i: governor impostato a 'performance'"
                success_count=$((success_count + 1))
            else
                # Tentativo 2: Con sudo (più robusto)
                if sudo bash -c "echo performance > $governor_file" 2>/dev/null; then
                    log "CPU $i: governor impostato a 'performance' (con sudo)"
                    success_count=$((success_count + 1))
                else
                    warn "Impossibile impostare governor per CPU $i (permessi insufficienti)"
                    warn "Esegui manualmente: sudo echo performance > $governor_file"
                fi
            fi
        else
            warn "Governor file non trovato per CPU $i"
        fi
    done
    
    # Verifica impostazione di tutti i governor
    log "Verifica stato governor per tutte le CPU..."
    local all_performance=true
    local failed_cpus=()
    
    for i in $(seq 0 $((num_cores - 1))); do
        local gov=$(cat "/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor" 2>/dev/null || echo "unknown")
        if [[ "$gov" != "performance" ]]; then
            all_performance=false
            failed_cpus+=("$i:$gov")
            warn "CPU $i: governor=$gov (performance atteso)"
        fi
    done
    
    if [[ "$all_performance" == "true" ]]; then
        log "Tutti i governor impostati correttamente su performance"
    else
        warn "Alcuni governor non sono in performance mode"
        warn "CPU con problemi: ${failed_cpus[*]}"
    fi
    
    log "CPU governor configuration: $success_count/$total_count core configurati"
}

# Configurazione power management
configure_power_management() {
    log "Configurazione power management..."
    
    # Ferma irqbalance
    if systemctl is-active --quiet irqbalance 2>/dev/null; then
        log "Fermando irqbalance service..."
        systemctl stop irqbalance 2>/dev/null || warn "Impossibile fermare irqbalance"
    fi
    
    # Disabilita irqbalance al boot (se possibile)
    if systemctl is-enabled --quiet irqbalance 2>/dev/null; then
        log "Disabilitando irqbalance al boot..."
        systemctl disable irqbalance 2>/dev/null || warn "Impossibile disabilitare irqbalance"
    fi
    
    # Configurazione C-states (richiede modifica GRUB, qui solo verifica)
    log "Verifica C-states configuration..."
    if [[ -f "/proc/cmdline" ]]; then
        local cmdline=$(cat /proc/cmdline)
        if echo "$cmdline" | grep -q "idle=nomwait\|processor.max_cstate=1"; then
            log "C-states già disabilitati nel kernel"
        else
            warn "C-states non disabilitati nel kernel (richiede modifica GRUB)"
        fi
    fi
}

# Configurazione memory locking e realtime privileges
configure_realtime_privileges() {
    log "Configurazione memory locking e realtime privileges..."
    
    # Verifica se il file limits esiste già
    if [[ -f "$LIMITS_FILE" ]]; then
        log "File limits già esistente: $LIMITS_FILE"
        log "Saltando creazione file (richiede privilegi root)"
    else
        # Crea file limits per realtime solo se non esiste
        if ! cat > "$LIMITS_FILE" << EOF
# OLMS Real-Time User Limits

# Real-time group
@realtime soft rtprio 99
@realtime hard rtprio 99
@realtime soft memlock unlimited
@realtime hard memlock unlimited

# Audio group
@audio soft rtprio 99
@audio hard rtprio 99
@audio soft memlock unlimited
@audio hard memlock unlimited

# All users (fallback)
* soft rtprio 99
* hard rtprio 99
* soft memlock unlimited
* hard memlock unlimited
EOF
        then
            error "Impossibile scrivere in $LIMITS_FILE (permessi insufficienti)"
            error "Esegui lo script con sudo oppure esegui manualmente:"
            error "sudo tee $LIMITS_FILE << 'EOF'"
            error "# OLMS Real-Time User Limits"
            error ""
            error "# Real-time group"
            error "@realtime soft rtprio 99"
            error "@realtime hard rtprio 99"
            error "@realtime soft memlock unlimited"
            error "@realtime hard memlock unlimited"
            error ""
            error "# Audio group"
            error "@audio soft rtprio 99"
            error "@audio hard rtprio 99"
            error "@audio soft memlock unlimited"
            error "@audio hard memlock unlimited"
            error ""
            error "# All users (fallback)"
            error "* soft rtprio 99"
            error "* hard rtprio 99"
            error "* soft memlock unlimited"
            error "* hard memlock unlimited"
            error "EOF"
            return 1
        fi
    fi
    
    log "File limits verificato: $LIMITS_FILE"
    
    # Verifica limiti correnti
    local current_rtprio=$(ulimit -r 2>/dev/null || echo "0")
    local current_memlock=$(ulimit -l 2>/dev/null || echo "0")
    
    log "Limiti correnti: rtprio=$current_rtprio, memlock=${current_memlock}KB"
    
    # Verifica appartenenza gruppi
    local current_user=$(whoami)
    if groups "$current_user" | grep -q "realtime"; then
        log "Utente $current_user appartiene al gruppo 'realtime'"
    else
        warn "Utente $current_user NON appartiene al gruppo 'realtime'"
    fi
    
    if groups "$current_user" | grep -q "audio"; then
        log "Utente $current_user appartiene al gruppo 'audio'"
    else
        warn "Utente $current_user NON appartiene al gruppo 'audio'"
    fi
}

# Verifica configurazione RT
verify_rt_configuration() {
    log "Verifica configurazione real-time..."
    
    # Verifica kernel parameters
    local rt_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
    local rt_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "0")
    
    if [[ "$rt_runtime" -gt 0 ]] && [[ "$rt_period" -gt 0 ]]; then
        local rt_percentage=$((rt_runtime * 100 / rt_period))
        log "RT scheduling: ${rt_percentage}% della CPU disponibile per task real-time"
    else
        error "RT scheduling non configurato correttamente"
        return 1
    fi
    
    # Verifica CPU governor
    local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    if [[ "$governor" == "performance" ]]; then
        log "CPU governor: performance mode attivo"
    else
        warn "CPU governor: $governor (performance raccomandato)"
    fi
    
    # Verifica limiti utente
    local rtprio=$(ulimit -r 2>/dev/null || echo "0")
    local memlock=$(ulimit -l 2>/dev/null || echo "0")
    
    if [[ "$rtprio" -eq 99 ]] && [[ "$memlock" == "unlimited" ]] 2>/dev/null; then
        log "Realtime privileges: rtprio=99, memlock=unlimited"
    else
        warn "Realtime privileges insufficienti: rtprio=$rtprio, memlock=${memlock}KB"
    fi
    
    # Verifica irqbalance
    if ! systemctl is-active --quiet irqbalance 2>/dev/null; then
        log "irqbalance: disattivato (corretto per audio RT)"
    else
        warn "irqbalance: attivo (potrebbe causare jitter)"
    fi
}

# Funzione principale
main() {
    log "=== FASE 1: OTTIMIZZAZIONE SISTEMA REAL-TIME ==="
    info "Modalità: $MODE (prod=95%, test=80%, light=60%)"
    
    configure_kernel_parameters
    configure_cpu_governor
    configure_power_management
    configure_realtime_privileges
    verify_rt_configuration
    
    log "Ottimizzazione sistema real-time completata"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi