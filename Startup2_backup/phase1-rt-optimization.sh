#!/bin/bash

# Fase 1: System Real-Time Optimization
# Versione: 2.0

set -euo pipefail

# Configurazione
OLMS_HOME="$HOME/.olms"
mkdir -p "$OLMS_HOME"
LOG_FILE="$OLMS_HOME/olms-orchestrator.log"
RT_CONFIG_FILE="/etc/sysctl.d/99-olms-rt.conf"
LIMITS_FILE="/etc/security/limits.d/99-realtime.conf"
MODE="${OLMS_RT_MODE:-prod}"  # prod, test, light

# Variabili d'ambiente per l'approccio "tutto come stesso utente"
export TARGET_USER="francesco_ssh"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"

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
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} Startup process aborted due to warning: $1" | tee -a "$LOG_FILE"
    exit 1
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Funzione per scrivere file di sistema con privilegi
safe_write_file() {
    local content="$1"
    local target="$2"
    echo "$content" > "$target"
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
        local config_content="# OLMS Real-Time Kernel Parameters
kernel.sched_rt_runtime_us = $rt_runtime
kernel.sched_rt_period_us = $rt_period
kernel.sched_migration_cost_ns = 500000
kernel.sched_wakeup_granularity_ns = 1000000"
        
        safe_write_file "$config_content" "$RT_CONFIG_FILE"
    fi
    
    # Applica la configurazione se il file esiste
    if [[ -f "$RT_CONFIG_FILE" ]]; then
        if sysctl -p "$RT_CONFIG_FILE" &>/dev/null; then
            log "Kernel parameters RT applicati con successo"
        else
            warn "Impossibile applicare kernel parameters RT"
            warn "Verifica che i parametri siano già applicati o esegui: sysctl -p $RT_CONFIG_FILE"
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
    log "Configurazione CPU governor per prestazioni (modalità forzata)..."
    
    local num_cores=$(nproc)
    log "Numero core rilevati: $num_cores"
    
    # 1. Tenta di disabilitare il risparmio energetico hardware Intel se presente
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        if echo "0" > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null; then
            log "Turbo Boost disabilitato con successo"
        else
            warn "Impossibile disabilitare Turbo Boost (permessi insufficienti)"
        fi
    fi

    # 2. Applica 'performance' a ogni core disponibile
    # Usiamo un approccio che bypassa potenziali errori di scrittura individuali
    local success_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            
            # Prova a scrivere performance
            if echo "performance" > "$governor_file"; then
                log "CPU $i: governor impostato a 'performance'"
                success_count=$((success_count + 1))
            else
                warn "Impossibile scrivere su $governor_file"
            fi
        else
            warn "Governor file non trovato per CPU $i"
        fi
    done
    
    # 3. Forza la frequenza minima al massimo possibile (per driver intel_pstate)
    for i in $(seq 0 $((num_cores - 1))); do
        local min_freq="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_min_freq"
        local max_freq="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_max_freq"
        
        if [ -f "$max_freq" ] && [ -f "$min_freq" ]; then
            cat "$max_freq" > "$min_freq" 2>&1 || true
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
    
    # Verifica stato irqbalance (senza tentare di modificarlo)
    log "Verifica stato irqbalance..."
    if systemctl is-active --quiet irqbalance 2>/dev/null; then
        warn "irqbalance è attivo (potrebbe causare jitter audio)"
        warn "Per disattivarlo: sudo systemctl stop irqbalance && sudo systemctl disable irqbalance"
    else
        log "irqbalance è disattivato (corretto per audio RT)"
    fi
    
    # Configurazione C-states (disabilitazione via sysfs per sistemi senza GRUB)
    log "Configurazione C-states via sysfs..."
    disable_cstates
}

# Funzione per disabilitare C-states problematici via sysfs
disable_cstates() {
    log "Disabilitazione C-states problematici per audio real-time..."
    
    local num_cores=$(nproc)
    local disabled_states=0
    
    # Disabilita C3 e C6 per tutti i core (i più problematici per latenza)
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        # Disabilita C3 state (se presente)
        if [[ -f "${cpu_path}/state3/disable" ]]; then
            if echo 1 > "${cpu_path}/state3/disable" 2>/dev/null; then
                log "C3 state disabilitato per CPU $i"
                disabled_states=$((disabled_states + 1))
            else
                warn "Impossibile disabilitare C3 state per CPU $i (permessi)"
            fi
        fi
        
        # Disabilita C6 state (se presente)
        if [[ -f "${cpu_path}/state4/disable" ]]; then
            if echo 1 > "${cpu_path}/state4/disable" 2>/dev/null; then
                log "C6 state disabilitato per CPU $i"
                disabled_states=$((disabled_states + 1))
            else
                warn "Impossibile disabilitare C6 state per CPU $i (permessi)"
            fi
        fi
    done
    
    if [[ $disabled_states -gt 0 ]]; then
        log "C-states disabilitati con successo: $disabled_states stati"
    else
        warn "Nessun C-state disabilitato (potrebbe essere già configurato o mancanza permessi)"
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
        local limits_content="# OLMS Real-Time User Limits
@realtime soft rtprio 99
@realtime hard rtprio 99
@realtime soft memlock unlimited
@realtime hard memlock unlimited
@audio soft rtprio 99
@audio hard rtprio 99
@audio soft memlock unlimited
@audio hard memlock unlimited"
        
        safe_write_file "$limits_content" "$LIMITS_FILE"
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
    log "Verifica finale..."
    
    # Verifica CPU governor
    local gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
    [[ "$gov" == "performance" ]] && log "Governor: OK ($gov)" || error "Governor: FAIL ($gov)"
    
    # Verifica limiti utente
    local rtprio=$(ulimit -r)
    [[ "$rtprio" -eq 99 ]] && log "RT Prio: OK ($rtprio)" || warn "RT Prio: $rtprio (richiede riavvio sessione)"
    
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
