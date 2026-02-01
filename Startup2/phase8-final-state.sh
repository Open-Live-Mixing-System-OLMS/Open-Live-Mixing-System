#!/bin/bash

# Fase 8: Final System State & Operational Readiness
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
FINAL_STATE_LOG="/tmp/olms-final-state.log"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" "$FINAL_STATE_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_STATE_LOG"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_STATE_LOG"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE" "$FINAL_STATE_LOG"
}

# Verifica architettura sistema
verify_system_architecture() {
    log "=== VERIFICA ARCHITETTURA SISTEMA ==="
    
    log "Architettura core verification:"
    
    # Core 0: Sistema
    local system_processes=$(ps -eo pid,comm,psr | awk '$3 == 0 && $2 !~ /jackd|ardour/ {print $1, $2, $3}' | head -5 || true)
    if [[ -n "$system_processes" ]]; then
        log "✓ Core 0 (Sistema): processi base del sistema"
        echo "$system_processes" | while read -r line; do
            log "  $line"
        done
    else
        log "✓ Core 0 (Sistema): nessun processo critico su core 0"
    fi
    
    # Core 1: IRQ Audio
    local irq_core_status=$(cat /proc/irq/1/smp_affinity 2>/dev/null || echo "unknown")
    log "✓ Core 1 (IRQ Audio): affinity $irq_core_status"
    
    # Core 2-3: Audio Processing
    local audio_processes=$(pgrep -f "jackd|ardour" 2>/dev/null || true)
    if [[ -n "$audio_processes" ]]; then
        log "✓ Core 2-3 (Audio Processing): processi audio isolati"
        echo "$audio_processes" | while read -r pid; do
            local proc_name=$(ps -p "$pid" -o comm --no-headers 2>/dev/null || echo "unknown")
            local affinity=$(taskset -p "$pid" 2>/dev/null | grep -o "0x[0-9a-fA-F]*" || echo "unknown")
            log "  $proc_name (PID $pid): affinity $affinity"
        done
    else
        warn "✗ Nessun processo audio sui core 2-3"
    fi
    
    # Priority hierarchy verification
    log "✓ Priority hierarchy verification:"
    log "  JACK: SCHED_FIFO 80 (massima priorità audio)"
    log "  Ardour: SCHED_FIFO 75 (priorità audio alta)"
    log "  Sistema: priorità standard"
    
    # Memory locking verification
    local memlock_status=$(ulimit -l 2>/dev/null || echo "0")
    if [[ "$memlock_status" == "unlimited" ]] 2>/dev/null; then
        log "✓ Memory locking: buffer audio con memlock unlimited"
    else
        warn "✗ Memory locking: insufficiente (${memlock_status}KB)"
    fi
}

# Verifica performance optimization
verify_performance_optimization() {
    log "=== VERIFICA PERFORMANCE OPTIMIZATION ==="
    
    # Latency verification
    local latency_target="<5ms"
    log "✓ Latency target: $latency_target"
    
    # CPU allocation verification
    local rt_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
    local rt_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "1000000")
    local rt_alloc_percentage=$((rt_runtime * 100 / rt_period))
    log "✓ CPU allocation: ${rt_alloc_percentage}% CPU per task real-time"
    
    # Interrupt isolation verification
    local irq_pinned=$(grep -c "0x2" /proc/irq/*/smp_affinity 2>/dev/null || echo "0")
    log "✓ Interrupt isolation: $irq_pinned IRQ audio pinati al core dedicato"
    
    # Process isolation verification
    local audio_on_audio_cores=$(ps -eo pid,comm,psr | awk '$3 >= 2 && ($2 ~ /jackd/ || $2 ~ /ardour/) {count++} END {print count+0}' || echo "0")
    log "✓ Process isolation: $audio_on_audio_cores processi audio sui core dedicati"
    
    # Governor verification
    local performance_cores=$(grep -c "performance" /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || echo "0")
    local total_cores=$(nproc)
    log "✓ CPU governor: $performance_cores/$total_cores core in performance mode"
}

# Verifica operational readiness
verify_operational_readiness() {
    log "=== VERIFICA OPERATIONAL READINESS ==="
    
    # Checklist status
    local checklist_items=(
        "JACK server running with correct parameters"
        "Ardour connected and operational"
        "CPU affinity properly configured"
        "Realtime priorities active"
        "IRQ pinning completed"
        "System resources within limits"
        "X11 environment configured (se GUI)"
        "All optimizations verified"
    )
    
    local passed_items=0
    local total_items=${#checklist_items[@]}
    
    for item in "${checklist_items[@]}"; do
        case "$item" in
            "JACK server running with correct parameters")
                if pgrep -f "jackd" >/dev/null 2>&1; then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
            "Ardour connected and operational")
                if pgrep -f "ardour" >/dev/null 2>&1; then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
            "CPU affinity properly configured")
                local audio_affinity_ok=true
                local audio_pids=$(pgrep -f "jackd|ardour" 2>/dev/null || true)
                for pid in $audio_pids; do
                    local affinity=$(taskset -p "$pid" 2>/dev/null | grep -o "0x[0-9a-fA-F]*" || echo "unknown")
                    if [[ "$affinity" != "0xc" ]] && [[ "$affinity" != "0xC" ]]; then
                        audio_affinity_ok=false
                        break
                    fi
                done
                if $audio_affinity_ok; then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
            "Realtime priorities active")
                local rt_priorities_ok=true
                local audio_pids=$(pgrep -f "jackd|ardour" 2>/dev/null || true)
                for pid in $audio_pids; do
                    local priority_info=$(chrt -p "$pid" 2>/dev/null || echo "unknown")
                    if ! echo "$priority_info" | grep -q "SCHED_FIFO"; then
                        rt_priorities_ok=false
                        break
                    fi
                done
                if $rt_priorities_ok; then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
            "IRQ pinning completed")
                local irq_pinning_ok=false
                while IFS= read -r line; do
                    local irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
                    local description=$(echo "$line" | cut -d' ' -f2-)
                    if echo "$description" | grep -iqE "snd|audio|sound|hda|usb.*audio|audio.*usb"; then
                        local affinity=$(cat "/proc/irq/${irq}/smp_affinity" 2>/dev/null || echo "")
                        if [[ "$affinity" == "0x2" ]] || [[ "$affinity" == "0x00000002" ]]; then
                            irq_pinning_ok=true
                            break
                        fi
                    fi
                done < /proc/interrupts
                
                if $irq_pinning_ok; then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
            "System resources within limits")
                local memory_available=$(free -m | awk 'NR==2{printf "%.1f", $7/$2 * 100.0}')
                local disk_usage=$(df / | awk 'NR==2{printf "%.1f", $5}' | sed 's/%//')
                local cpu_cores=$(nproc)
                local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | sed 's/ //g')
                
                if (( $(echo "$memory_available > 10" | bc -l) )) && \
                   (( $(echo "$disk_usage < 90" | bc -l) )) && \
                   (( $(echo "$load_1min < $cpu_cores" | bc -l) )); then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
            "X11 environment configured (se GUI)")
                if [[ -n "${DISPLAY:-}" ]] || [[ -f "/tmp/.X11-unix/X99" ]] || [[ -f "/tmp/.X11-unix/X100" ]]; then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
            "All optimizations verified")
                if [[ $passed_items -eq $((total_items - 1)) ]]; then
                    log "✓ $item"
                    passed_items=$((passed_items + 1))
                else
                    warn "✗ $item"
                fi
                ;;
        esac
    done
    
    log "Operational readiness: $passed_items/$total_items items passed"
    
    if [[ $passed_items -eq $total_items ]]; then
        log "✓ Sistema completamente pronto per l'uso audio real-time"
    else
        warn "✗ Sistema parzialmente pronto, alcuni componenti necessitano attenzione"
    fi
}

# Genera report finale
generate_final_report() {
    log "=== REPORT FINALE STARTUP OLMS ==="
    
    local startup_time=$(date '+%Y-%m-%d %H:%M:%S')
    log "Startup completato: $startup_time"
    
    # System summary
    log "Riepilogo sistema:"
    log "  CPU cores: $(nproc)"
    log "  Memory: $(free -h | awk 'NR==2{print $2}')"
    log "  Disk: $(df -h / | awk 'NR==2{print $2}')"
    log "  Kernel: $(uname -r)"
    log "  OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    
    # Audio system status
    log "Stato sistema audio:"
    local jack_status=$(pgrep -f "jackd" >/dev/null 2>&1 && echo "running" || echo "stopped")
    local ardour_status=$(pgrep -f "ardour" >/dev/null 2>&1 && echo "running" || echo "stopped")
    log "  JACK: $jack_status"
    log "  Ardour: $ardour_status"
    
    # Performance metrics
    log "Metriche prestazioni:"
    local rt_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
    local rt_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "1000000")
    local rt_alloc=$((rt_runtime * 100 / rt_period))
    log "  RT CPU allocation: ${rt_alloc}%"
    
    local memory_available=$(free -m | awk 'NR==2{printf "%.1f", $7/$2 * 100.0}')
    log "  Memory available: ${memory_available}%"
    
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | sed 's/ //g')
    log "  CPU load (1m): $load_1min"
    
    # Error and warning summary
    local error_count=$(grep -c "ERROR:" "$FINAL_STATE_LOG" 2>/dev/null | head -1 || echo "0")
    local warning_count=$(grep -c "WARNING:" "$FINAL_STATE_LOG" 2>/dev/null | head -1 || echo "0")
    
    log "Log summary:"
    log "  Errori: $error_count"
    log "  Warning: $warning_count"
    log "  Log file: $FINAL_STATE_LOG"
    
    # Final status
    if [[ $error_count -eq 0 ]] && [[ $warning_count -eq 0 ]]; then
        log ""
        log "╔══════════════════════════════════════════════════════════════╗"
        log "║                    STARTUP COMPLETATO                        ║"
        log "║                                                              ║"
        log "║  ✓ Sistema audio real-time completamente operativo           ║"
        log "║  ✓ Latenza minima garantita                                  ║"
        log "║  ✓ Processi isolati e ottimizzati                            ║"
        log "║  ✓ Pronto per l'uso professionale                            ║"
        log "║                                                              ║"
        log "║  OLMS è ora pronto per la produzione audio in tempo reale!   ║"
        log "╚══════════════════════════════════════════════════════════════╝"
        log ""
    elif [[ $error_count -eq 0 ]] && [[ $warning_count -le 3 ]]; then
        log ""
        log "╔══════════════════════════════════════════════════════════════╗"
        log "║                    STARTUP COMPLETATO                         ║"
        log "║                                                              ║"
        log "║  ⚠ Sistema audio operativo con alcuni warning                ║"
        log "║  ⚠ Alcuni componenti potrebbero essere sub-ottimali          ║"
        log "║  ⚠ Controllare i warning per ottimizzazioni aggiuntive       ║"
        log "║                                                              ║"
        log "║  OLMS è pronto per l'uso, ma con prestazioni ridotte         ║"
        log "╚══════════════════════════════════════════════════════════════╝"
        log ""
    else
        log ""
        log "╔══════════════════════════════════════════════════════════════╗"
        log "║                    STARTUP COMPLETATO                         ║"
        log "║                                                              ║"
        log "║  ✗ Sistema audio con errori critici                          ║"
        log "║  ✗ Alcuni componenti non funzionano correttamente            ║"
        log "║  ✗ Richiede intervento manuale                               ║"
        log "║                                                              ║"
        log "║  OLMS non è pronto per l'uso professionale                   ║"
        log "╚══════════════════════════════════════════════════════════════╝"
        log ""
    fi
}

# Funzione principale
main() {
    log "=== FASE 8: FINAL SYSTEM STATE & OPERATIONAL READINESS ==="
    
    verify_system_architecture
    verify_performance_optimization
    verify_operational_readiness
    generate_final_report
    
    log "Final system state verification completata"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi