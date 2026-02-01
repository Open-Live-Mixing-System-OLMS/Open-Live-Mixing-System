#!/bin/bash

# Fase 6: CPU Affinity & Resource Allocation
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
MAX_POLL_ATTEMPTS=15
POLL_INTERVAL=2

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

# Discovery processi audio con polling intelligente
discover_audio_processes() {
    log "Discovery processi audio con polling intelligente..."
    
    local attempt=1
    local jack_pids=()
    local ardour_pids=()
    
    while [[ $attempt -le $MAX_POLL_ATTEMPTS ]]; do
        log "Polling processi audio (tentativo $attempt/$MAX_POLL_ATTEMPTS)..."
        
        # Ricerca processi JACK
        local current_jack_pids=$(pgrep -f "jackd" 2>/dev/null || true)
        if [[ -n "$current_jack_pids" ]]; then
            for pid in $current_jack_pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    jack_pids+=("$pid")
                    log "JACK processo attivo: PID $pid"
                fi
            done
        fi
        
        # Ricerca processi Ardour
        local current_ardour_pids=$(pgrep -f "ardour" 2>/dev/null || true)
        if [[ -n "$current_ardour_pids" ]]; then
            for pid in $current_ardour_pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    ardour_pids+=("$pid")
                    log "Ardour processo attivo: PID $pid"
                fi
            done
        fi
        
        # Verifica se abbiamo trovato processi
        if [[ ${#jack_pids[@]} -gt 0 ]] || [[ ${#ardour_pids[@]} -gt 0 ]]; then
            log "Processi audio trovati: JACK=${#jack_pids[@]}, Ardour=${#ardour_pids[@]}"
            break
        fi
        
        # Attendi prima del prossimo tentativo
        if [[ $attempt -lt $MAX_POLL_ATTEMPTS ]]; then
            log "Attesa ${POLL_INTERVAL}s prima del prossimo polling..."
            sleep $POLL_INTERVAL
        fi
        
        attempt=$((attempt + 1))
    done
    
    # Rimuovi duplicati
    local unique_jack_pids=($(printf '%s\n' "${jack_pids[@]}" | sort -u))
    local unique_ardour_pids=($(printf '%s\n' "${ardour_pids[@]}" | sort -u))
    
    log "Discovery completato: JACK=${#unique_jack_pids[@]}, Ardour=${#unique_ardour_pids[@]}"
    
    # Salva PIDs in file
    if [[ ${#unique_jack_pids[@]} -gt 0 ]]; then
        printf '%s\n' "${unique_jack_pids[@]}" > "/tmp/jack_pids.list"
        log "JACK PIDs salvati: /tmp/jack_pids.list"
    fi
    
    if [[ ${#unique_ardour_pids[@]} -gt 0 ]]; then
        printf '%s\n' "${unique_ardour_pids[@]}" > "/tmp/ardour_pids.list"
        log "Ardour PIDs salvati: /tmp/ardour_pids.list"
    fi
    
    return 0
}

# Applicazione CPU affinity
apply_cpu_affinity() {
    log "Applicazione CPU affinity..."
    
    # Definizione core isolation
    local system_core="0"        # Sistema (kernel, processi base)
    local irq_core="1"           # IRQ Audio (interrupt handling dedicato)
    local audio_cores="2-3"      # Audio Processing (JACK, Ardour, plugins)
    
    log "Architettura core isolation:"
    log "  Core 0: Sistema"
    log "  Core 1: IRQ Audio"
    log "  Core 2-3: Audio Processing"
    
    # Applica affinity per processi JACK
    if [[ -f "/tmp/jack_pids.list" ]]; then
        log "Applicazione affinity per processi JACK..."
        while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                # JACK: core 2-3 (audio processing)
                if taskset -pc $audio_cores "$pid" >/dev/null 2>&1; then
                    log "JACK PID $pid: affinity impostata a $audio_cores"
                else
                    warn "Impossibile impostare affinity per JACK PID $pid"
                fi
                
                # Verifica affinity
                local current_affinity=$(taskset -p "$pid" 2>/dev/null | grep -o "0x[0-9a-fA-F]*" || echo "unknown")
                log "JACK PID $pid: affinity corrente $current_affinity"
            else
                warn "JACK PID $pid non più attivo"
            fi
        done < "/tmp/jack_pids.list"
    fi
    
    # Applica affinity per processi Ardour
    if [[ -f "/tmp/ardour_pids.list" ]]; then
        log "Applicazione affinity per processi Ardour..."
        while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                # Ardour: core 2-3 (audio processing)
                if taskset -pc $audio_cores "$pid" >/dev/null 2>&1; then
                    log "Ardour PID $pid: affinity impostata a $audio_cores"
                else
                    warn "Impossibile impostare affinity per Ardour PID $pid"
                fi
                
                # Verifica affinity
                local current_affinity=$(taskset -p "$pid" 2>/dev/null | grep -o "0x[0-9a-fA-F]*" || echo "unknown")
                log "Ardour PID $pid: affinity corrente $current_affinity"
            else
                warn "Ardour PID $pid non più attivo"
            fi
        done < "/tmp/ardour_pids.list"
    fi
    
    # Applica affinity per IRQ audio (se configurati)
    log "Verifica affinity IRQ audio..."
    if [[ -f "/proc/irq/1/smp_affinity" ]]; then
        local irq_affinity=$(cat "/proc/irq/1/smp_affinity" 2>/dev/null || echo "unknown")
        log "IRQ 1 affinity: $irq_affinity (dovrebbe essere 0x2 per core 1)"
    fi
}

# Verifica realtime priorities
verify_realtime_priorities() {
    log "Verifica realtime priorities..."
    
    # Verifica priorità processi JACK
    if [[ -f "/tmp/jack_pids.list" ]]; then
        log "Verifica priorità processi JACK..."
        while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                local priority_info=$(chrt -p "$pid" 2>/dev/null || echo "unknown")
                log "JACK PID $pid: $priority_info"
                
                # Parsing output chrt
                if echo "$priority_info" | grep -q "SCHED_FIFO"; then
                    local current_priority=$(echo "$priority_info" | grep -o "priority [0-9]*" | grep -o "[0-9]*" || echo "0")
                    if [[ "$current_priority" -eq 80 ]]; then
                        log "JACK PID $pid: priorità corretta (SCHED_FIFO 80)"
                    else
                        warn "JACK PID $pid: priorità non corretta ($current_priority, atteso 80)"
                    fi
                else
                    warn "JACK PID $pid: policy non SCHED_FIFO"
                fi
            fi
        done < "/tmp/jack_pids.list"
    fi
    
    # Verifica priorità processi Ardour
    if [[ -f "/tmp/ardour_pids.list" ]]; then
        log "Verifica priorità processi Ardour..."
        while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                local priority_info=$(chrt -p "$pid" 2>/dev/null || echo "unknown")
                log "Ardour PID $pid: $priority_info"
                
                # Parsing output chrt
                if echo "$priority_info" | grep -q "SCHED_FIFO"; then
                    local current_priority=$(echo "$priority_info" | grep -o "priority [0-9]*" | grep -o "[0-9]*" || echo "0")
                    if [[ "$current_priority" -eq 75 ]]; then
                        log "Ardour PID $pid: priorità corretta (SCHED_FIFO 75)"
                    else
                        warn "Ardour PID $pid: priorità non corretta ($current_priority, atteso 75)"
                    fi
                else
                    warn "Ardour PID $pid: policy non SCHED_FIFO"
                fi
            fi
        done < "/tmp/ardour_pids.list"
    fi
}

# Verifica isolamento processi
verify_process_isolation() {
    log "Verifica isolamento processi audio..."
    
    # Controlla affinità processi audio
    local audio_processes=$(pgrep -f "jackd|ardour" 2>/dev/null || true)
    
    if [[ -n "$audio_processes" ]]; then
        log "Verifica affinità processi audio:"
        echo "$audio_processes" | while read -r pid; do
            local proc_name=$(ps -p "$pid" -o comm --no-headers 2>/dev/null || echo "unknown")
            local affinity=$(taskset -p "$pid" 2>/dev/null | grep -o "0x[0-9a-fA-F]*" || echo "unknown")
            
            log "Processo $proc_name (PID $pid): affinity $affinity"
            
            # Verifica che l'affinità sia corretta (core 2-3 = maschera 0xc)
            if [[ "$affinity" == "0xc" ]] || [[ "$affinity" == "0xC" ]]; then
                log "Processo $proc_name: isolamento corretto (core 2-3)"
            else
                warn "Processo $proc_name: isolamento non corretto"
            fi
        done
    else
        warn "Nessun processo audio attivo da verificare"
    fi
    
    # Verifica che i processi non siano su core di sistema
    log "Verifica che i processi non siano su core di sistema (0-1)..."
    local system_core_processes=$(ps -eo pid,comm,psr | awk '$3 <= 1 && ($2 ~ /jackd/ || $2 ~ /ardour/) {print $1, $2, $3}' || true)
    
    if [[ -n "$system_core_processes" ]]; then
        warn "Processi audio su core di sistema:"
        echo "$system_core_processes" | while read -r line; do
            warn "  $line"
        done
    else
        log "Nessun processo audio su core di sistema (corretto)"
    fi
}

# Monitoraggio risorse
monitor_resources() {
    log "Monitoraggio risorse di sistema..."
    
    # Memoria
    local memory_info=$(free -m)
    log "Stato memoria:"
    echo "$memory_info" | while read -r line; do
        log "  $line"
    done
    
    # Disco
    local disk_info=$(df /)
    log "Stato disco root:"
    echo "$disk_info" | while read -r line; do
        log "  $line"
    done
    
    # CPU load
    local load_info=$(uptime)
    log "CPU load: $load_info"
    
    # Verifica utilizzo risorse
    local memory_available=$(free -m | awk 'NR==2{printf "%.1f", $7/$2 * 100.0}')
    local disk_usage=$(df / | awk 'NR==2{printf "%.1f", $5}' | sed 's/%//')
    local cpu_cores=$(nproc)
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | sed 's/ //g')
    
    if (( $(echo "$memory_available > 10" | bc -l) )); then
        log "Memoria disponibile: ${memory_available}% (OK)"
    else
        warn "Memoria disponibile: ${memory_available}% (bassa)"
    fi
    
    if (( $(echo "$disk_usage < 90" | bc -l) )); then
        log "Utilizzo disco: ${disk_usage}% (OK)"
    else
        warn "Utilizzo disco: ${disk_usage}% (alto)"
    fi
    
    if (( $(echo "$load_1min < $cpu_cores" | bc -l) )); then
        log "CPU load: $load_1min (OK, < $cpu_cores core)"
    else
        warn "CPU load: $load_1min (alto, >= $cpu_cores core)"
    fi
}

# Funzione principale
main() {
    log "=== FASE 6: CPU AFFINITY & RESOURCE ALLOCATION ==="
    
    # Discovery processi
    discover_audio_processes
    
    # Applica CPU affinity
    apply_cpu_affinity
    
    # Verifica realtime priorities
    verify_realtime_priorities
    
    # Verifica isolamento
    verify_process_isolation
    
    # Monitoraggio risorse
    monitor_resources
    
    log "CPU affinity & resource allocation completati"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi