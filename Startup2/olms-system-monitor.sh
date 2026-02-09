#!/bin/bash

# OLMS System Monitor
# Monitoraggio continuo e ripristino automatico dei permessi sysfs
# Versione: 1.0

set -euo pipefail

# Configurazione
OLMS_HOME="$HOME/.olms"
mkdir -p "$OLMS_HOME"
LOG_FILE="$OLMS_HOME/olms-system-monitor.log"
MONITOR_INTERVAL=30  # Secondi tra i controlli
MAX_RETRIES=3        # Tentativi massimi per ripristino

# Variabili d'ambiente per l'approccio "tutto come stesso utente"
export TARGET_USER="$(whoami)"
export TARGET_UID=$(id -u "$(whoami)" 2>/dev/null || echo "$(id -u)")
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"

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

# Rilevamento utente e sistema
detect_user_environment() {
    # Gestione intelligente del percorso home per gestire anche l'esecuzione con sudo
    if [[ "$EUID" -eq 0 ]]; then
        # Se siamo root, dobbiamo determinare l'utente effettivo
        if [[ -n "${SUDO_USER:-}" ]]; then
            # Eseguito con sudo, usa l'utente originale
            ACTUAL_USER="$SUDO_USER"
            ACTUAL_HOME=$(eval echo ~$SUDO_USER)
        elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
            # Eseguito come root ma USER è impostato a un utente non root
            ACTUAL_USER="$USER"
            ACTUAL_HOME=$(eval echo ~$USER)
        else
            # Eseguito direttamente come root
            ACTUAL_USER="root"
            ACTUAL_HOME="/root"
        fi
    else
        # Eseguito come utente normale
        ACTUAL_USER="$(whoami)"
        ACTUAL_HOME="$HOME"
    fi
    
    ACTUAL_UID=$(id -u "$ACTUAL_USER")
    ACTUAL_GID=$(id -g "$ACTUAL_USER")
    
    # Ottieni il gruppo primario dell'utente
    USER_GROUP=$(id -gn "$ACTUAL_USER")
    
    log "Ambiente utente rilevato: $ACTUAL_USER (UID: $ACTUAL_UID, GID: $ACTUAL_GID, Gruppo: $USER_GROUP)"
}

# Verifica permessi CPU
check_cpu_permissions() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local failed_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            local perms=$(stat -c "%a" "$governor_file" 2>/dev/null || echo "0")
            local owner=$(stat -c "%U:%G" "$governor_file" 2>/dev/null || echo "unknown:unknown")
            
            if [[ "$perms" != "666" ]] || [[ "$owner" != "$ACTUAL_USER:$USER_GROUP" ]]; then
                failed_count=$((failed_count + 1))
                warn "CPU $i: permessi non corretti (perms=$perms, owner=$owner)"
            fi
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Permessi CPU non corretti: $failed_count/$total_count"
        return 1
    else
        log "Permessi CPU verificati: $total_count corretti"
        return 0
    fi
}

# Verifica permessi C-states
check_cstate_permissions() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local failed_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            for state in state3 state4; do
                local disable_file="$cpu_path/$state/disable"
                
                if [[ -f "$disable_file" ]]; then
                    total_count=$((total_count + 1))
                    local perms=$(stat -c "%a" "$disable_file" 2>/dev/null || echo "0")
                    local owner=$(stat -c "%U:%G" "$disable_file" 2>/dev/null || echo "unknown:unknown")
                    
                    if [[ "$perms" != "666" ]] || [[ "$owner" != "$ACTUAL_USER:$USER_GROUP" ]]; then
                        failed_count=$((failed_count + 1))
                        warn "CPU $i $state: permessi non corretti (perms=$perms, owner=$owner)"
                    fi
                fi
            done
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Permessi C-states non corretti: $failed_count/$total_count"
        return 1
    else
        log "Permessi C-states verificati: $total_count corretti"
        return 0
    fi
}

# Verifica permessi IRQ
check_irq_permissions() {
    local failed_count=0
    local total_count=0
    
    if [[ -d "/proc/irq" ]]; then
        for irq_dir in /proc/irq/*/; do
            if [[ -d "$irq_dir" ]]; then
                local irq_num=$(basename "$irq_dir")
                local affinity_file="/proc/irq/$irq_num/smp_affinity"
                
                if [[ -f "$affinity_file" ]]; then
                    total_count=$((total_count + 1))
                    local perms=$(stat -c "%a" "$affinity_file" 2>/dev/null || echo "0")
                    local owner=$(stat -c "%U:%G" "$affinity_file" 2>/dev/null || echo "unknown:unknown")
                    
                    if [[ "$perms" != "666" ]] || [[ "$owner" != "$ACTUAL_USER:$USER_GROUP" ]]; then
                        failed_count=$((failed_count + 1))
                        warn "IRQ $irq_num: permessi non corretti (perms=$perms, owner=$owner)"
                    fi
                fi
            fi
        done
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Permessi IRQ non corretti: $failed_count/$total_count"
        return 1
    else
        log "Permessi IRQ verificati: $total_count corretti"
        return 0
    fi
}

# Verifica stato governor
check_governor_status() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local failed_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            local gov=$(cat "$governor_file" 2>/dev/null || echo "unknown")
            
            if [[ "$gov" != "performance" ]]; then
                failed_count=$((failed_count + 1))
                warn "CPU $i: governor=$gov (performance atteso)"
            fi
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        warn "Governor non corretti: $failed_count/$total_count"
        return 1
    else
        log "Governor verificati: $total_count in performance"
        return 0
    fi
}

# Verifica stato C-states
check_cstate_status() {
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local disabled_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            for state in state3 state4; do
                local disable_file="$cpu_path/$state/disable"
                
                if [[ -f "$disable_file" ]]; then
                    total_count=$((total_count + 1))
                    local disabled=$(cat "$disable_file" 2>/dev/null || echo "0")
                    
                    if [[ "$disabled" == "1" ]]; then
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i $state: C-state non disabilitato (disabled=$disabled)"
                    fi
                fi
            done
        fi
    done
    
    if [[ $disabled_count -eq $total_count ]] && [[ $total_count -gt 0 ]]; then
        log "C-states verificati: $total_count disabilitati"
        return 0
    else
        warn "C-states non correttamente disabilitati: $disabled_count/$total_count"
        return 1
    fi
}

# Ripristino permessi CPU
restore_cpu_permissions() {
    log "Ripristino permessi CPU..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local restored_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpufreq"
        
        if [[ -d "$cpu_path" ]]; then
            # File sysfs per CPU governor e frequenze
            local cpu_files=(
                "scaling_governor"
                "scaling_min_freq"
                "scaling_max_freq"
                "scaling_setspeed"
                "scaling_cur_freq"
            )
            
            for file in "${cpu_files[@]}"; do
                local target_file="$cpu_path/$file"
                if [[ -f "$target_file" ]]; then
                    total_count=$((total_count + 1))
                    if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                        log "CPU $i: permessi ripristinati per $file"
                        restored_count=$((restored_count + 1))
                    else
                        warn "CPU $i: impossibile ripristinare permessi per $file"
                    fi
                fi
            done
        fi
    done
    
    # Ripristino permessi Turbo Boost
    local turbo_files=(
        "no_turbo"
    )
    
    for file in "${turbo_files[@]}"; do
        local target_file="/sys/devices/system/cpu/intel_pstate/$file"
        if [[ -f "$target_file" ]]; then
            total_count=$((total_count + 1))
            if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                log "Turbo Boost: permessi ripristinati per $file"
                restored_count=$((restored_count + 1))
            else
                warn "Turbo Boost: impossibile ripristinare permessi per $file"
            fi
        fi
    done
    
    log "Ripristino permessi CPU completato: $restored_count/$total_count"
    return $((total_count - restored_count))
}

# Ripristino permessi C-states
restore_cstate_permissions() {
    log "Ripristino permessi C-states..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local restored_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            # Stati C da disabilitare (C3, C6 sono i più problematici per latenza)
            local cstates=("state3" "state4")
            
            for cstate in "${cstates[@]}"; do
                local disable_file="$cpu_path/$cstate/disable"
                local name_file="$cpu_path/$cstate/name"
                
                if [[ -f "$disable_file" ]]; then
                    total_count=$((total_count + 1))
                    if chmod 666 "$disable_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$disable_file" 2>/dev/null; then
                        log "CPU $i: permessi ripristinati per $cstate/disable"
                        restored_count=$((restored_count + 1))
                    else
                        warn "CPU $i: impossibile ripristinare permessi per $cstate/disable"
                    fi
                fi
                
                if [[ -f "$name_file" ]]; then
                    total_count=$((total_count + 1))
                    if chmod 666 "$name_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$name_file" 2>/dev/null; then
                        log "CPU $i: permessi ripristinati per $cstate/name"
                        restored_count=$((restored_count + 1))
                    else
                        warn "CPU $i: impossibile ripristinare permessi per $cstate/name"
                    fi
                fi
            done
        fi
    done
    
    log "Ripristino permessi C-states completato: $restored_count/$total_count"
    return $((total_count - restored_count))
}

# Ripristino permessi IRQ
restore_irq_permissions() {
    log "Ripristino permessi IRQ..."
    
    local restored_count=0
    local total_count=0
    
    if [[ -d "/proc/irq" ]]; then
        for irq_dir in /proc/irq/*/; do
            if [[ -d "$irq_dir" ]]; then
                local irq_num=$(basename "$irq_dir")
                
                # File sysfs per IRQ
                local irq_files=(
                    "smp_affinity"
                    "smp_affinity_list"
                    "affinity_hint"
                )
                
                for file in "${irq_files[@]}"; do
                    local target_file="/proc/irq/$irq_num/$file"
                    if [[ -f "$target_file" ]]; then
                        total_count=$((total_count + 1))
                        if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                            log "IRQ $irq_num: permessi ripristinati per $file"
                            restored_count=$((restored_count + 1))
                        else
                            warn "IRQ $irq_num: impossibile ripristinare permessi per $file"
                        fi
                    fi
                done
            fi
        done
    fi
    
    log "Ripristino permessi IRQ completato: $restored_count/$total_count"
    return $((total_count - restored_count))
}

# Ripristino governor a performance
restore_governor_performance() {
    log "Ripristino governor a performance..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local restored_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            # Verifica se il file è scrivibile
            if [[ -w "$governor_file" ]]; then
                if echo "performance" > "$governor_file" 2>/dev/null; then
                    log "CPU $i: governor ripristinato a performance"
                    restored_count=$((restored_count + 1))
                else
                    warn "CPU $i: impossibile ripristinare governor a performance"
                fi
            else
                warn "CPU $i: governor file non scrivibile"
            fi
        fi
    done
    
    log "Ripristino governor completato: $restored_count core"
    return $((num_cores - restored_count))
}

# Ripristino C-states disabilitati
restore_cstates_disabled() {
    log "Ripristino C-states disabilitati..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local disabled_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            # Disabilita C3 state (se presente)
            if [[ -f "${cpu_path}/state3/disable" ]]; then
                if [[ -w "${cpu_path}/state3/disable" ]]; then
                    if echo 1 > "${cpu_path}/state3/disable" 2>/dev/null; then
                        log "CPU $i: C3 state ripristinato disabilitato"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: impossibile ripristinare C3 state disabilitato"
                    fi
                else
                    warn "CPU $i: C3 state file non scrivibile"
                fi
            fi
            
            # Disabilita C6 state (se presente)
            if [[ -f "${cpu_path}/state4/disable" ]]; then
                if [[ -w "${cpu_path}/state4/disable" ]]; then
                    if echo 1 > "${cpu_path}/state4/disable" 2>/dev/null; then
                        log "CPU $i: C6 state ripristinato disabilitato"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: impossibile ripristinare C6 state disabilitato"
                    fi
                else
                    warn "CPU $i: C6 state file non scrivibile"
                fi
            fi
        fi
    done
    
    log "Ripristino C-states completato: $disabled_count stati"
    return 0
}

# Ripristino completo tramite Runtime Permission Manager
restore_via_runtime_manager() {
    log "Ripristino completo tramite Runtime Permission Manager..."
    
    if [[ -x "/usr/local/bin/olms-runtime-permissions" ]]; then
        sudo /usr/local/bin/olms-runtime-permissions
        log "Runtime Permission Manager eseguito per ripristino completo"
        return 0
    else
        warn "Runtime Permission Manager non trovato o non eseguibile"
        return 1
    fi
}

# Monitoraggio continuo
monitor_system() {
    log "=== OLMS SYSTEM MONITOR ==="
    log "Monitoraggio continuo dei permessi sysfs e stato RT"
    log "Intervallo di controllo: ${MONITOR_INTERVAL} secondi"
    
    local check_count=0
    
    while true; do
        check_count=$((check_count + 1))
        log "Controllo #$check_count"
        
        # Verifica permessi
        local cpu_ok=true
        local cstate_ok=true
        local irq_ok=true
        local governor_ok=true
        local cstate_status_ok=true
        
        # Verifica permessi CPU
        if ! check_cpu_permissions; then
            cpu_ok=false
        fi
        
        # Verifica permessi C-states
        if ! check_cstate_permissions; then
            cstate_ok=false
        fi
        
        # Verifica permessi IRQ
        if ! check_irq_permissions; then
            irq_ok=false
        fi
        
        # Verifica stato governor
        if ! check_governor_status; then
            governor_ok=false
        fi
        
        # Verifica stato C-states
        if ! check_cstate_status; then
            cstate_status_ok=false
        fi
        
        # Ripristino se necessario
        local restore_needed=false
        
        if [[ "$cpu_ok" == "false" ]] || [[ "$cstate_ok" == "false" ]] || [[ "$irq_ok" == "false" ]]; then
            warn "Permessi sysfs non corretti, tentativo di ripristino..."
            restore_via_runtime_manager
            restore_needed=true
        fi
        
        if [[ "$governor_ok" == "false" ]]; then
            warn "Governor non corretti, tentativo di ripristino..."
            restore_governor_performance
            restore_needed=true
        fi
        
        if [[ "$cstate_status_ok" == "false" ]]; then
            warn "C-states non correttamente disabilitati, tentativo di ripristino..."
            restore_cstates_disabled
            restore_needed=true
        fi
        
        if [[ "$restore_needed" == "true" ]]; then
            log "Ripristino completato, nuova verifica in corso..."
            
            # Nuova verifica dopo ripristino
            sleep 2
            
            local retry_count=0
            local all_ok=false
            
            while [[ $retry_count -lt $MAX_RETRIES ]] && [[ "$all_ok" == "false" ]]; do
                retry_count=$((retry_count + 1))
                log "Verifica post-ripristino (tentativo $retry_count/$MAX_RETRIES)"
                
                cpu_ok=true
                cstate_ok=true
                irq_ok=true
                governor_ok=true
                cstate_status_ok=true
                
                if ! check_cpu_permissions; then cpu_ok=false; fi
                if ! check_cstate_permissions; then cstate_ok=false; fi
                if ! check_irq_permissions; then irq_ok=false; fi
                if ! check_governor_status; then governor_ok=false; fi
                if ! check_cstate_status; then cstate_status_ok=false; fi
                
                if [[ "$cpu_ok" == "true" ]] && [[ "$cstate_ok" == "true" ]] && [[ "$irq_ok" == "true" ]] && [[ "$governor_ok" == "true" ]] && [[ "$cstate_status_ok" == "true" ]]; then
                    all_ok=true
                    log "Verifica post-ripristino: OK"
                else
                    warn "Verifica post-ripristino: FALLITA, nuovo tentativo..."
                    restore_via_runtime_manager
                    restore_governor_performance
                    restore_cstates_disabled
                    sleep 2
                fi
            done
            
            if [[ "$all_ok" == "false" ]]; then
                error "Verifica post-ripristino: FALLITA dopo $MAX_RETRIES tentativi"
                error "Controllare manualmente i permessi sysfs"
            fi
        else
            log "Tutto OK, nessun ripristino necessario"
        fi
        
        log "Controllo #$check_count completato"
        log "Prossimo controllo tra ${MONITOR_INTERVAL} secondi..."
        sleep "$MONITOR_INTERVAL"
    done
}

# Funzione principale
main() {
    log "=== OLMS SYSTEM MONITOR ==="
    log "Monitoraggio continuo e ripristino automatico dei permessi sysfs"
    
    # Verifica che lo script sia eseguito come root (necessario per modifiche sysfs)
    if [[ "$EUID" -ne 0 ]]; then
        error "Questo script deve essere eseguito come root per modificare i file sysfs"
        error "Esegui: sudo $0"
        exit 1
    fi
    
    detect_user_environment
    monitor_system
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi