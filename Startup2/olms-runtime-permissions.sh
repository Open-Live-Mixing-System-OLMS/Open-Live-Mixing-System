#!/bin/bash

# OLMS Runtime Permission Manager
# Gestisce i permessi sysfs in tempo reale per qualsiasi utente Linux
# Versione: 1.0

set -euo pipefail

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
    
    log "Ambiente utente rilevato:"
    log "  Utente: $ACTUAL_USER"
    log "  UID: $ACTUAL_UID"
    log "  GID: $ACTUAL_GID"
    log "  Gruppo: $USER_GROUP"
    log "  Home: $ACTUAL_HOME"
    
    # Verifica che l'utente esista e abbia i permessi necessari
    if ! id "$ACTUAL_USER" >/dev/null 2>&1; then
        error "Utente $ACTUAL_USER non esiste"
        exit 1
    fi
    
    # Verifica che l'utente abbia una home directory
    if [[ ! -d "$ACTUAL_HOME" ]]; then
        warn "Home directory $ACTUAL_HOME non esiste"
        return 1
    fi
}

# Applicazione permessi sysfs per CPU/Governor
apply_cpu_permissions() {
    log "Applicazione permessi sysfs per CPU/Governor..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    log "Numero core rilevati: $num_cores"
    
    local applied_count=0
    local total_count=0
    
    # File sysfs per CPU governor e frequenze
    local cpu_files=(
        "scaling_governor"
        "scaling_min_freq"
        "scaling_max_freq"
        "scaling_setspeed"
        "scaling_cur_freq"
    )
    
    # File sysfs per Turbo Boost
    local turbo_files=(
        "no_turbo"
    )
    
    # Applica permessi per ogni core
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpufreq"
        
        # Verifica che la directory esista
        if [[ ! -d "$cpu_path" ]]; then
            warn "CPU $i: directory $cpu_path non esiste (potrebbe essere offline)"
            continue
        fi
        
        # Applica permessi ai file CPU
        for file in "${cpu_files[@]}"; do
            local target_file="$cpu_path/$file"
            if [[ -f "$target_file" ]]; then
                total_count=$((total_count + 1))
                if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                    log "CPU $i: permessi applicati a $file"
                    applied_count=$((applied_count + 1))
                else
                    warn "CPU $i: impossibile applicare permessi a $file"
                fi
            fi
        done
    done
    
    # Applica permessi per Turbo Boost (se presente)
    for file in "${turbo_files[@]}"; do
        local target_file="/sys/devices/system/cpu/intel_pstate/$file"
        if [[ -f "$target_file" ]]; then
            total_count=$((total_count + 1))
            if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                log "Turbo Boost: permessi applicati a $file"
                applied_count=$((applied_count + 1))
            else
                warn "Turbo Boost: impossibile applicare permessi a $file"
            fi
        fi
    done
    
    log "Permessi CPU applicati: $applied_count/$total_count"
    
    # Verifica applicazione
    verify_cpu_permissions
}

# Applicazione permessi sysfs per C-states
apply_cstate_permissions() {
    log "Applicazione permessi sysfs per C-states..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local applied_count=0
    local total_count=0
    
    # Stati C da disabilitare (C3, C6 sono i più problematici per latenza)
    local cstates=("state3" "state4")
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        # Verifica che la directory esista
        if [[ ! -d "$cpu_path" ]]; then
            warn "CPU $i: directory cpuidle non esiste"
            continue
        fi
        
        # Applica permessi ai file C-states
        for cstate in "${cstates[@]}"; do
            local disable_file="$cpu_path/$cstate/disable"
            local name_file="$cpu_path/$cstate/name"
            
            if [[ -f "$disable_file" ]]; then
                total_count=$((total_count + 1))
                if chmod 666 "$disable_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$disable_file" 2>/dev/null; then
                    log "CPU $i: permessi applicati a $cstate/disable"
                    applied_count=$((applied_count + 1))
                else
                    warn "CPU $i: impossibile applicare permessi a $cstate/disable"
                fi
            fi
            
            if [[ -f "$name_file" ]]; then
                total_count=$((total_count + 1))
                if chmod 666 "$name_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$name_file" 2>/dev/null; then
                    log "CPU $i: permessi applicati a $cstate/name"
                    applied_count=$((applied_count + 1))
                else
                    warn "CPU $i: impossibile applicare permessi a $cstate/name"
                fi
            fi
        done
    done
    
    log "Permessi C-states applicati: $applied_count/$total_count"
    
    # Verifica applicazione
    verify_cstate_permissions
}

# Applicazione permessi sysfs per IRQ
apply_irq_permissions() {
    log "Applicazione permessi sysfs per IRQ..."
    
    local applied_count=0
    local total_count=0
    
    # File sysfs per IRQ
    local irq_files=(
        "smp_affinity"
        "smp_affinity_list"
        "affinity_hint"
    )
    
    # Trova tutte le IRQ disponibili
    if [[ -d "/proc/irq" ]]; then
        for irq_dir in /proc/irq/*/; do
            if [[ -d "$irq_dir" ]]; then
                local irq_num=$(basename "$irq_dir")
                
                # Applica permessi ai file IRQ
                for file in "${irq_files[@]}"; do
                    local target_file="/proc/irq/$irq_num/$file"
                    if [[ -f "$target_file" ]]; then
                        total_count=$((total_count + 1))
                        if chmod 666 "$target_file" 2>/dev/null && chown "$ACTUAL_USER:$USER_GROUP" "$target_file" 2>/dev/null; then
                            log "IRQ $irq_num: permessi applicati a $file"
                            applied_count=$((applied_count + 1))
                        else
                            warn "IRQ $irq_num: impossibile applicare permessi a $file"
                        fi
                    fi
                done
            fi
        done
    fi
    
    log "Permessi IRQ applicati: $applied_count/$total_count"
    
    # Verifica applicazione
    verify_irq_permissions
}

# Verifica permessi CPU
verify_cpu_permissions() {
    log "Verifica permessi CPU..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local verified_count=0
    local total_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            total_count=$((total_count + 1))
            local perms=$(stat -c "%a" "$governor_file" 2>/dev/null || echo "0")
            local owner=$(stat -c "%U:%G" "$governor_file" 2>/dev/null || echo "unknown:unknown")
            
            if [[ "$perms" == "666" ]] && [[ "$owner" == "$ACTUAL_USER:$USER_GROUP" ]]; then
                log "CPU $i: permessi verificati (666, $owner)"
                verified_count=$((verified_count + 1))
            else
                warn "CPU $i: permessi non corretti (perms=$perms, owner=$owner)"
            fi
        fi
    done
    
    log "Verifica CPU completata: $verified_count/$total_count corretti"
}

# Verifica permessi C-states
verify_cstate_permissions() {
    log "Verifica permessi C-states..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local verified_count=0
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
                    
                    if [[ "$perms" == "666" ]] && [[ "$owner" == "$ACTUAL_USER:$USER_GROUP" ]]; then
                        log "CPU $i $state: permessi verificati (666, $owner)"
                        verified_count=$((verified_count + 1))
                    else
                        warn "CPU $i $state: permessi non corretti (perms=$perms, owner=$owner)"
                    fi
                fi
            done
        fi
    done
    
    log "Verifica C-states completata: $verified_count/$total_count corretti"
}

# Verifica permessi IRQ
verify_irq_permissions() {
    log "Verifica permessi IRQ..."
    
    local verified_count=0
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
                    
                    if [[ "$perms" == "666" ]] && [[ "$owner" == "$ACTUAL_USER:$USER_GROUP" ]]; then
                        log "IRQ $irq_num: permessi verificati (666, $owner)"
                        verified_count=$((verified_count + 1))
                    else
                        warn "IRQ $irq_num: permessi non corretti (perms=$perms, owner=$owner)"
                    fi
                fi
            fi
        done
    fi
    
    log "Verifica IRQ completata: $verified_count/$total_count corretti"
}

# Forza impostazione governor a performance
force_performance_governor() {
    log "Forzatura governor a performance..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local success_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        
        if [[ -f "$governor_file" ]]; then
            # Verifica se il file è scrivibile
            if [[ -w "$governor_file" ]]; then
                if echo "performance" > "$governor_file" 2>/dev/null; then
                    log "CPU $i: governor impostato a performance"
                    success_count=$((success_count + 1))
                else
                    warn "CPU $i: impossibile impostare governor a performance"
                fi
            else
                warn "CPU $i: governor file non scrivibile"
            fi
        fi
    done
    
    log "Governor performance impostati: $success_count core"
}

# Forza disabilitazione C-states problematici
force_disable_cstates() {
    log "Forzatura disabilitazione C-states problematici..."
    
    local num_cores=$(nproc 2>/dev/null || echo "4")
    local disabled_count=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local cpu_path="/sys/devices/system/cpu/cpu${i}/cpuidle"
        
        if [[ -d "$cpu_path" ]]; then
            # Disabilita C3 state (se presente)
            if [[ -f "${cpu_path}/state3/disable" ]]; then
                if [[ -w "${cpu_path}/state3/disable" ]]; then
                    if echo 1 > "${cpu_path}/state3/disable" 2>/dev/null; then
                        log "CPU $i: C3 state disabilitato"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: impossibile disabilitare C3 state"
                    fi
                else
                    warn "CPU $i: C3 state file non scrivibile"
                fi
            fi
            
            # Disabilita C6 state (se presente)
            if [[ -f "${cpu_path}/state4/disable" ]]; then
                if [[ -w "${cpu_path}/state4/disable" ]]; then
                    if echo 1 > "${cpu_path}/state4/disable" 2>/dev/null; then
                        log "CPU $i: C6 state disabilitato"
                        disabled_count=$((disabled_count + 1))
                    else
                        warn "CPU $i: impossibile disabilitare C6 state"
                    fi
                else
                    warn "CPU $i: C6 state file non scrivibile"
                fi
            fi
        fi
    done
    
    log "C-states disabilitati: $disabled_count stati"
}

# Funzione principale
main() {
    log "=== OLMS RUNTIME PERMISSION MANAGER ==="
    log "Gestione permessi sysfs in tempo reale per qualsiasi utente Linux"
    
    # Verifica che lo script sia eseguito come root (necessario per modifiche sysfs)
    if [[ "$EUID" -ne 0 ]]; then
        error "Questo script deve essere eseguito come root per modificare i file sysfs"
        error "Esegui: sudo $0"
        exit 1
    fi
    
    detect_user_environment
    
    # Applica permessi sysfs
    apply_cpu_permissions
    apply_cstate_permissions
    apply_irq_permissions
    
    # Forza impostazioni RT
    force_performance_governor
    force_disable_cstates
    
    log "=== RUNTIME PERMISSION MANAGER COMPLETATO ==="
    log "Permessi sysfs applicati per l'utente $ACTUAL_USER"
    log "Sistema pronto per l'uso audio real-time"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi