#!/bin/bash

# Fase 7: System Verification & Monitoring
# Versione: 2.0

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

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
VERIFICATION_LOG="/tmp/olms-verification.log"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" "$VERIFICATION_LOG"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE" "$VERIFICATION_LOG"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE" "$VERIFICATION_LOG"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE" "$VERIFICATION_LOG"
}

# Verifica kernel parameters
verify_kernel_parameters() {
    log "Verifica kernel parameters RT..."
    
    local rt_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
    local rt_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "0")
    
    if [[ "$rt_runtime" -gt 0 ]] && [[ "$rt_period" -gt 0 ]]; then
        local rt_percentage=$((rt_runtime * 100 / rt_period))
        log "✓ RT scheduling: ${rt_percentage}% della CPU disponibile per task real-time"
        log "  Runtime: ${rt_runtime}μs, Period: ${rt_period}μs"
    else
        error "✗ RT scheduling non configurato correttamente"
        return 1
    fi
    
    # Verifica parametri aggiuntivi
    local migration_cost=$(sysctl -n kernel.sched_migration_cost_ns 2>/dev/null || echo "0")
    local wakeup_granularity=$(sysctl -n kernel.sched_wakeup_granularity_ns 2>/dev/null || echo "0")
    
    log "✓ Scheduling optimizations:"
    log "  Migration cost: ${migration_cost}ns"
    log "  Wakeup granularity: ${wakeup_granularity}ns"
}

# Verifica CPU governor
verify_cpu_governor() {
    log "Verifica CPU governor..."
    
    local num_cores=$(nproc)
    local performance_cores=0
    
    for i in $(seq 0 $((num_cores - 1))); do
        local governor_file="/sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor"
        local current_governor=$(cat "$governor_file" 2>/dev/null || echo "unknown")
        
        if [[ "$current_governor" == "performance" ]]; then
            performance_cores=$((performance_cores + 1))
            log "  CPU $i: $current_governor ✓"
        else
            warn "  CPU $i: $current_governor ✗"
        fi
    done
    
    if [[ $performance_cores -eq $num_cores ]]; then
        log "✓ Tutti i core in performance mode"
    else
        warn "✗ Solo $performance_cores core su $num_cores in performance mode"
    fi
}

# Verifica realtime privileges
verify_realtime_privileges() {
    log "Verifica realtime privileges..."
    
    local current_user=$(whoami)
    
    # Verifica limiti utente
    local rtprio=$(ulimit -r 2>/dev/null || echo "0")
    local memlock=$(ulimit -l 2>/dev/null || echo "0")
    
    if [[ "$rtprio" -eq 99 ]] && [[ "$memlock" == "unlimited" ]] 2>/dev/null; then
        log "✓ Realtime privileges: rtprio=99, memlock=unlimited"
    else
        warn "✗ Realtime privileges insufficienti: rtprio=$rtprio, memlock=${memlock}KB"
    fi
    
    # Verifica appartenenza gruppi
    if groups "$current_user" | grep -q "realtime"; then
        log "✓ Utente $current_user appartiene al gruppo 'realtime'"
    else
        warn "✗ Utente $current_user NON appartiene al gruppo 'realtime'"
    fi
    
    if groups "$current_user" | grep -q "audio"; then
        log "✓ Utente $current_user appartiene al gruppo 'audio'"
    else
        warn "✗ Utente $current_user NON appartiene al gruppo 'audio'"
    fi
}

# Verifica IRQ pinning
verify_irq_pinning() {
    log "Verifica IRQ pinning..."
    
    local audio_irqs_found=0
    local correctly_pinned=0
    
    while IFS= read -r line; do
        local irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        local description=$(echo "$line" | cut -d' ' -f2-)
        
        if [[ "$irq" =~ ^[0-9]+$ ]] && [[ $irq -ge 0 ]] && [[ $irq -le 4095 ]]; then
            # Verifica se è un IRQ audio
            if echo "$description" | grep -iqE "snd|audio|sound|hda|usb.*audio|audio.*usb"; then
                audio_irqs_found=$((audio_irqs_found + 1))
                
                local affinity_file="/proc/irq/${irq}/smp_affinity"
                local current_affinity=$(cat "$affinity_file" 2>/dev/null || echo "")
                
                if [[ -n "$current_affinity" ]]; then
                    log "  IRQ $irq ($description): affinity $current_affinity"
                    
                    # Verifica pinning corretto (core 1 = maschera 0x2)
                    if [[ "$current_affinity" == "0x2" ]] || [[ "$current_affinity" == "0x00000002" ]]; then
                        correctly_pinned=$((correctly_pinned + 1))
                        log "    ✓ Pinato correttamente al core 1"
                    else
                        warn "    ✗ Pinato non correttamente (atteso 0x2)"
                    fi
                else
                    warn "  IRQ $irq: impossibile leggere affinity"
                fi
            fi
        fi
    done < /proc/interrupts
    
    if [[ $audio_irqs_found -gt 0 ]]; then
        log "✓ IRQ audio trovati: $audio_irqs_found, correttamente pinati: $correctly_pinned"
    else
        warn "✗ Nessun IRQ audio rilevato"
    fi
}

# Verifica CPU affinity processi
verify_cpu_affinity() {
    log "Verifica CPU affinity processi audio..."
    
    # Cerca solo i binari reali, escludendo i wrapper
    local audio_processes=$(pgrep -x "jackd" && pgrep -x "ardour" 2>/dev/null || true)
    
    if [[ -n "$audio_processes" ]]; then
        local correctly_isolated=0
        local total_audio=0
        
        echo "$audio_processes" | while read -r pid; do
            local proc_name=$(ps -p "$pid" -o comm --no-headers 2>/dev/null || echo "unknown")
            local affinity=$(taskset -p "$pid" 2>/dev/null | grep -o "0x[0-9a-fA-F]*" || echo "unknown")
            
            log "  Processo $proc_name (PID $pid): affinity $affinity"
            
            # Verifica isolamento corretto (core 2-3 = maschera 0xc)
            if [[ "$affinity" == "0xc" ]] || [[ "$affinity" == "0xC" ]] || [[ "$affinity" == "0x0000000c" ]] || [[ "$affinity" == "0x0000000C" ]]; then
                log "    ✓ Isolato correttamente sui core audio (2-3)"
                correctly_isolated=$((correctly_isolated + 1))
            else
                warn "    ✗ Isolamento non corretto"
            fi
            
            total_audio=$((total_audio + 1))
        done
        
        log "✓ Processi audio isolati correttamente: $correctly_isolated su $total_audio"
    else
        warn "✗ Nessun processo audio attivo"
    fi
}

# Verifica realtime priorities
verify_rt_priorities() {
    log "Verifica realtime priorities..."
    
    local audio_processes=$(pgrep -f "jackd|ardour" 2>/dev/null || true)
    
    if [[ -n "$audio_processes" ]]; then
        local correct_priorities=0
        local total_processes=0
        
        echo "$audio_processes" | while read -r pid; do
            local proc_name=$(ps -p "$pid" -o comm --no-headers 2>/dev/null || echo "unknown")
            local priority_info=$(chrt -p "$pid" 2>/dev/null || echo "unknown")
            
            log "  Processo $proc_name (PID $pid): $priority_info"
            
            if echo "$priority_info" | grep -q "SCHED_FIFO"; then
                local current_priority=$(echo "$priority_info" | grep -o "priority [0-9]*" | grep -o "[0-9]*" || echo "0")
                
                # Verifica priorità corretta (JACK=80, Ardour=75)
                if [[ "$proc_name" == "jackd" ]] && [[ "$current_priority" -eq 80 ]]; then
                    log "    ✓ Priorità corretta per JACK (80)"
                    correct_priorities=$((correct_priorities + 1))
                elif [[ "$proc_name" == "ardour" ]] && [[ "$current_priority" -eq 75 ]]; then
                    log "    ✓ Priorità corretta per Ardour (75)"
                    correct_priorities=$((correct_priorities + 1))
                else
                    warn "    ✗ Priorità non corretta ($current_priority)"
                fi
            else
                warn "    ✗ Policy non SCHED_FIFO"
            fi
            
            total_processes=$((total_processes + 1))
        done
        
        log "✓ Processi con priorità corretta: $correct_priorities su $total_processes"
    else
        warn "✗ Nessun processo audio attivo"
    fi
}

# Verifica stato audio multi-metodo
verify_audio_status() {
    log "Verifica stato audio multi-metodo..."
    
    # Metodo 1: JACK process
    local jack_pids=$(pgrep -f "jackd" 2>/dev/null || true)
    if [[ -n "$jack_pids" ]]; then
        log "✅ JACK processi attivi: $jack_pids"
        for pid in $jack_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                log "  PID $pid: attivo ✓"
            else
                warn "  PID $pid: non attivo ✗"
            fi
        done
    else
        warn "✗ Nessun processo JACK attivo"
    fi
    
    # Metodo 2: Socket files - Enhanced with multiple paths
    local user_id=$(id -u)
    local socket_found=false
    
    local socket_patterns=(
        "/dev/shm/jack_default_${user_id}_0"
        "/tmp/.jack_default_${user_id}_0"
        "/tmp/jack_default_${user_id}_0"
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-${user_id}"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-${user_id}"
    )
    
    for pattern in "${socket_patterns[@]}"; do
        if [[ -d "$pattern" ]]; then
            log "✓ Socket JACK trovato: $pattern"
            socket_found=true
        fi
    done
    
    if [[ "$socket_found" == "false" ]]; then
        warn "✗ Nessun socket JACK trovato"
    fi
    
    # Metodo 3: Port availability - Enhanced with retry and JACK status check
    if command -v jack_lsp >/dev/null 2>&1; then
        # Prima verifica se JACK è attivo
        local jack_status=$(jack_control status 2>/dev/null || echo "unknown")
        if echo "$jack_status" | grep -q "running"; then
            log "✓ JACK server attivo, test porte in corso..."
            
            # Verifica aggiuntiva: prova a connettersi effettivamente a JACK
            local jack_connect_test=$(jack_lsp 2>&1 | head -1 || echo "connection_failed")
            if echo "$jack_connect_test" | grep -q "Cannot connect"; then
                warn "✗ JACK server attivo ma connessione fallita, salto test porte"
            else
                local max_attempts=3
                local attempt=1
                local ports_found=false
                
                while [[ $attempt -le $max_attempts ]]; do
                    local ports=$(jack_lsp 2>/dev/null || true)
                    if [[ -n "$ports" ]]; then
                        log "✓ Porte JACK operative (tentativo $attempt):"
                        echo "$ports" | while read -r port; do
                            log "  $port"
                        done
                        ports_found=true
                        break
                    else
                        warn "✗ Nessuna porta JACK operativa (tentativo $attempt/$max_attempts)"
                        if [[ $attempt -lt $max_attempts ]]; then
                            log "Attesa 2 secondi prima del prossimo tentativo..."
                            sleep 2
                        fi
                    fi
                    attempt=$((attempt + 1))
                done
                
                if [[ "$ports_found" == "false" ]]; then
                    warn "✗ Nessuna porta JACK operativa dopo $max_attempts tentativi"
                fi
            fi
        else
            warn "✗ JACK server non attivo (status: $jack_status), salto test porte"
        fi
    fi
    
    # Metodo 4: Control status
    if command -v jack_control >/dev/null 2>&1; then
        local jack_status=$(jack_control status 2>/dev/null || echo "unknown")
        if echo "$jack_status" | grep -q "running"; then
            log "✓ JACK server running (jack_control)"
        else
            warn "✗ JACK server non running (jack_control: $jack_status)"
        fi
    fi
    
    # Metodo 5: Connection status - Enhanced with multiple user contexts
    if command -v jack_lsp >/dev/null 2>&1; then
        local ardour_ports=""
        local connection_tested=false
        
        # Test connection as different users
        local test_users=("root" "$USER" "francesco_ssh")
        
        for test_user in "${test_users[@]}"; do
            if id "$test_user" >/dev/null 2>&1; then
                if sudo -u "$test_user" -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | grep -q "ardour"; then
                    ardour_ports=$(sudo -u "$test_user" -E JACK_DEFAULT_SERVER=olms jack_lsp 2>/dev/null | grep -i ardour || true)
                    if [[ -n "$ardour_ports" ]]; then
                        log "✓ Ardour connesso a JACK (utente: $test_user):"
                        echo "$ardour_ports" | while read -r port; do
                            log "  $port"
                        done
                        connection_tested=true
                        break
                    fi
                fi
            fi
        done
        
        if [[ "$connection_tested" == "false" ]]; then
            warn "✗ Ardour non connesso a JACK (testato con più utenti)"
        fi
    fi
}

# Monitoraggio risorse sistema
monitor_system_resources() {
    log "Monitoraggio risorse sistema..."
    
    # Memoria
    local memory_info=$(free -m)
    log "Stato memoria:"
    echo "$memory_info" | while read -r line; do
        log "  $line"
    done
    
    local memory_available=$(free -m | awk 'NR==2{printf "%.1f", $7/$2 * 100.0}')
    if (( $(echo "$memory_available > 10" | bc -l) )); then
        log "✓ Memoria disponibile: ${memory_available}%"
    else
        warn "✗ Memoria disponibile: ${memory_available}% (bassa)"
    fi
    
    # Disco
    local disk_info=$(df /)
    log "Stato disco root:"
    echo "$disk_info" | while read -r line; do
        log "  $line"
    done
    
    local disk_usage=$(df / | awk 'NR==2{printf "%.1f", $5}' | sed 's/%//')
    if (( $(echo "$disk_usage < 90" | bc -l) )); then
        log "✓ Utilizzo disco: ${disk_usage}%"
    else
        warn "✗ Utilizzo disco: ${disk_usage}% (alto)"
    fi
    
    # CPU load
    local load_info=$(uptime)
    log "CPU load: $load_info"
    
    local cpu_cores=$(nproc)
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | sed 's/ //g')
    if (( $(echo "$load_1min < $cpu_cores" | bc -l) )); then
        log "✓ CPU load: $load_1min (OK, < $cpu_cores core)"
    else
        warn "✗ CPU load: $load_1min (alto, >= $cpu_cores core)"
    fi
    
    # Process count
    local process_count=$(ps aux | wc -l)
    log "Processi totali: $process_count"
    
    # Audio processes count
    local audio_process_count=$(pgrep -f "jackd|ardour" 2>/dev/null | wc -l || echo "0")
    log "Processi audio: $audio_process_count"
}

# Report finale verifica
generate_verification_report() {
    log "=== REPORT VERIFICA SISTEMA ==="
    
    local verification_passed=true
    
    # Controlla errori nel log
    local error_count=$(grep -c "ERROR:" "$VERIFICATION_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    error_count=$((error_count + 0)) # Forza il cast a intero
    
    local warning_count=$(grep -c "WARNING:" "$VERIFICATION_LOG" 2>/dev/null | tr -d '\n' || echo "0")
    warning_count=$((warning_count + 0)) # Forza il cast a intero
    
    log "Riepilogo:"
    log "  Errori: $error_count"
    log "  Warning: $warning_count"
    
    if [[ $error_count -eq 0 ]]; then
        log "✓ Verifica sistema completata con successo"
        log "✓ Sistema pronto per audio real-time"
    else
        warn "✗ Verifica sistema completata con errori"
        warn "✗ Alcuni componenti potrebbero non funzionare correttamente"
    fi
    
    if [[ $warning_count -gt 5 ]]; then
        warn "✗ Numerosi warning rilevati, controllare il log per dettagli"
    fi
    
    log "Log dettagliato: $VERIFICATION_LOG"
}

# Funzione principale
main() {
    log "=== FASE 7: SYSTEM VERIFICATION & MONITORING ==="
    
    verify_kernel_parameters
    verify_cpu_governor
    verify_realtime_privileges
    verify_irq_pinning
    verify_cpu_affinity
    verify_rt_priorities
    verify_audio_status
    monitor_system_resources
    generate_verification_report
    
    log "System verification completata"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi