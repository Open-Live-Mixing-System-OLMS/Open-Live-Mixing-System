#!/bin/bash

# OLMS Bootstrap Script
# Configurazione universale per qualsiasi utente Linux
# Versione: 1.0

set -euo pipefail

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Definisci SCRIPT_DIR globalmente per le funzioni che ne hanno bisogno
SCRIPT_DIR="$(dirname "$0")"

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
    
    log "Ambiente utente rilevato:"
    log "  Utente: $ACTUAL_USER"
    log "  UID: $ACTUAL_UID"
    log "  Home: $ACTUAL_HOME"
    
    # Verifica che l'utente esista e abbia i permessi necessari
    if ! id "$ACTUAL_USER" >/dev/null 2>&1; then
        error "Utente $ACTUAL_USER non esiste"
        exit 1
    fi
    
    # Verifica che l'utente abbia una home directory
    if [[ ! -d "$ACTUAL_HOME" ]]; then
        warn "Home directory $ACTUAL_HOME non esiste, creazione in corso..."
        mkdir -p "$ACTUAL_HOME"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME"
    fi
}

# Creazione directory necessarie
create_directories() {
    log "Creazione directory necessarie..."
    
    # Directory per OLMS
    mkdir -p "$ACTUAL_HOME/.olms"
    mkdir -p "$ACTUAL_HOME/Progetti/OLMS-Core"
    
    # NOTA: Non creiamo directory personalizzate per JACK
    # JACK2 mette i file direttamente in /dev/shm/ con prefisso jack_olms
    # La directory /dev/shm è già gestita dal sistema
    
    # Imposta permessi corretti
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.olms" 2>/dev/null || true
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/Progetti/OLMS-Core" 2>/dev/null || true
    
    log "Directory create con successo"
}

# Generazione regole Udev USB
generate_usb_rules() {
    log "Generazione regole Udev USB per $ACTUAL_USER..."
    
    local usb_rules_file="/etc/udev/rules.d/99-olms-usb-permissions.rules"
    
    # Contenuto delle regole USB
    cat > "$usb_rules_file" << EOF
# OLMS USB Audio Device Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di controllare i dispositivi USB senza sudo

# Regole per dispositivi audio USB (vendor/product specifici)
# Texas Instruments PCM2902
SUBSYSTEM=="usb", ATTR{idVendor}=="08bb", ATTR{idProduct}=="2902", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Regole generiche per dispositivi audio USB
SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="01", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="03", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Regole per dispositivi audio ALSA
KERNEL=="snd/*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="controlC[0-9]*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="pcmC[D0-9]*c", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="pcmC[D0-9]*p", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="midiC[D0-9]*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="timer", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="seq", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "Regole Udev USB generate in $usb_rules_file"
}

# Generazione regole Udev JACK
generate_jack_rules() {
    log "Generazione regole Udev JACK per $ACTUAL_USER..."
    
    local jack_rules_file="/etc/udev/rules.d/99-olms-jack-sockets.rules"
    
    # Contenuto delle regole JACK
    cat > "$jack_rules_file" << EOF
# OLMS JACK Socket Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di gestire i socket JACK senza sudo

# Permessi per socket JACK in /dev/shm (pattern moderno)
KERNEL=="jack_*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="jack-shm-*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per socket JACK legacy (pattern legacy che alcuni script JACK usano)
KERNEL=="jack-*", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per socket JACK in /tmp
KERNEL=="jack_*", SUBSYSTEM=="misc", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per directory JACK per compatibilità
KERNEL=="jack-*", SUBSYSTEM=="misc", MODE="0777", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "Regole Udev JACK generate in $jack_rules_file"
}

# Generazione regole Udev CPU/Governor
generate_cpu_rules() {
    log "Generazione regole Udev CPU/Governor per $ACTUAL_USER..."
    
    local cpu_rules_file="/etc/udev/rules.d/99-olms-cpu.rules"
    
    # Contenuto delle regole CPU per permettere la gestione dei governor
    cat > "$cpu_rules_file" << EOF
# OLMS CPU Governor Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di gestire i governor CPU senza sudo

# Permessi per governor CPU
KERNEL=="cpu*", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="scaling_governor", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="scaling_min_freq", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="scaling_max_freq", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="scaling_setspeed", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="scaling_cur_freq", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per Turbo Boost
KERNEL=="no_turbo", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per CPU affinity
KERNEL=="smp_affinity", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="smp_affinity_list", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per C-states
KERNEL=="state*", SUBSYSTEM=="cpuidle", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="disable", SUBSYSTEM=="cpuidle", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "Regole Udev CPU generate in $cpu_rules_file"
}

# Generazione regole Udev IRQ
generate_irq_rules() {
    log "Generazione regole Udev IRQ per $ACTUAL_USER..."
    
    local irq_rules_file="/etc/udev/rules.d/99-olms-irq.rules"
    
    # Contenuto delle regole IRQ per permettere la gestione delle IRQ
    cat > "$irq_rules_file" << EOF
# OLMS IRQ Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di gestire le IRQ senza sudo

# Permessi per IRQ
KERNEL=="smp_affinity", SUBSYSTEM=="irq", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="smp_affinity_list", SUBSYSTEM=="irq", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
KERNEL=="affinity_hint", SUBSYSTEM=="irq", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "Regole Udev IRQ generate in $irq_rules_file"
}

# Generazione regole sysfs per CPU/Governor
generate_sysfs_rules() {
    log "Generazione regole sysfs per CPU/Governor per $ACTUAL_USER..."
    
    # Ottieni il gruppo primario dell'utente
    local user_group=$(id -gn "$ACTUAL_USER")
    
    # Creazione di un file di configurazione per systemd-sysfs per gestire i permessi sysfs
    local sysfs_config_file="/etc/tmpfiles.d/olms-cpu.conf"
    
    # Contenuto delle regole sysfs per permettere la gestione dei governor e C-states
    cat > "$sysfs_config_file" << EOF
# OLMS CPU Governor and C-states Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di gestire i governor CPU e C-states senza sudo

# Permessi per governor CPU
f /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 0666 $ACTUAL_USER $user_group -
f /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq 0666 $ACTUAL_USER $user_group -
f /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq 0666 $ACTUAL_USER $user_group -
f /sys/devices/system/cpu/cpu*/cpufreq/scaling_setspeed 0666 $ACTUAL_USER $user_group -
f /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 0666 $ACTUAL_USER $user_group -

# Permessi per Turbo Boost
f /sys/devices/system/cpu/intel_pstate/no_turbo 0666 $ACTUAL_USER $user_group -

# Permessi per C-states
f /sys/devices/system/cpu/cpu*/cpuidle/state*/disable 0666 $ACTUAL_USER $user_group -
f /sys/devices/system/cpu/cpu*/cpuidle/state*/name 0666 $ACTUAL_USER $user_group -
f /sys/devices/system/cpu/cpu*/cpuidle/state*/latency 0666 $ACTUAL_USER $user_group -
f /sys/devices/system/cpu/cpu*/cpuidle/state*/power 0666 $ACTUAL_USER $user_group -
EOF

    log "Regole sysfs generate in $sysfs_config_file"
}

# Applicazione permessi sysfs diretti
apply_sysfs_permissions() {
    log "Applicazione permessi sysfs diretti per $ACTUAL_USER..."
    
    # Ottieni il gruppo primario dell'utente
    local user_group=$(id -gn "$ACTUAL_USER")
    
    # Applica permessi diretti sui file sysfs esistenti
    local sysfs_files=(
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_governor"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_min_freq"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_max_freq"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_setspeed"
        "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/cpu3/cpufreq/scaling_cur_freq"
        "/sys/devices/system/cpu/intel_pstate/no_turbo"
    )
    
    local cstate_files=(
        "/sys/devices/system/cpu/cpu0/cpuidle/state0/disable"
        "/sys/devices/system/cpu/cpu0/cpuidle/state1/disable"
        "/sys/devices/system/cpu/cpu0/cpuidle/state2/disable"
        "/sys/devices/system/cpu/cpu1/cpuidle/state0/disable"
        "/sys/devices/system/cpu/cpu1/cpuidle/state1/disable"
        "/sys/devices/system/cpu/cpu1/cpuidle/state2/disable"
        "/sys/devices/system/cpu/cpu2/cpuidle/state0/disable"
        "/sys/devices/system/cpu/cpu2/cpuidle/state1/disable"
        "/sys/devices/system/cpu/cpu2/cpuidle/state2/disable"
        "/sys/devices/system/cpu/cpu3/cpuidle/state0/disable"
        "/sys/devices/system/cpu/cpu3/cpuidle/state1/disable"
        "/sys/devices/system/cpu/cpu3/cpuidle/state2/disable"
    )
    
    # Applica permessi sui file governor e freq
    for file in "${sysfs_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "Impostazione permessi su $file"
            chmod 666 "$file" 2>/dev/null || warn "Impossibile impostare permessi su $file"
            chown "$ACTUAL_USER:$user_group" "$file" 2>/dev/null || warn "Impossibile impostare proprietario su $file"
        fi
    done
    
    # Applica permessi sui file C-states (solo se esistono e sono scrivibili)
    for file in "${cstate_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "Verifica permessi su $file"
            # Controlla se il file è già scrivibile
            if [[ -w "$file" ]]; then
                log "Permessi già corretti su $file"
            else
                log "Impostazione permessi su $file"
                chmod 666 "$file" 2>/dev/null || warn "Impossibile impostare permessi su $file (potrebbe essere di sola lettura)"
                chown "$ACTUAL_USER:$user_group" "$file" 2>/dev/null || warn "Impossibile impostare proprietario su $file (potrebbe essere di sola lettura)"
            fi
        fi
    done
    
    log "Permessi sysfs applicati"
}

# Generazione configurazione realtime limits
generate_realtime_limits() {
    log "Generazione limiti realtime per $ACTUAL_USER..."
    
    local limits_file="/etc/security/limits.d/99-olms-realtime.conf"
    
    # Contenuto dei limiti realtime
    cat > "$limits_file" << EOF
# OLMS Real-Time User Limits
# Generato automaticamente per l'utente $ACTUAL_USER

# Limiti per utenti realtime
@$ACTUAL_USER soft rtprio 99
@$ACTUAL_USER hard rtprio 99
@$ACTUAL_USER soft memlock unlimited
@$ACTUAL_USER hard memlock unlimited

# Limiti per gruppo audio
@audio soft rtprio 99
@audio hard rtprio 99
@audio soft memlock unlimited
@audio hard memlock unlimited

# Limiti specifici per l'utente
$ACTUAL_USER soft rtprio 99
$ACTUAL_USER hard rtprio 99
$ACTUAL_USER soft memlock unlimited
$ACTUAL_USER hard memlock unlimited
EOF

    log "Limiti realtime generati in $limits_file"
}

# Generazione configurazione kernel RT
generate_kernel_config() {
    log "Generazione configurazione kernel RT..."
    
    local kernel_config_file="/etc/sysctl.d/99-olms-rt.conf"
    
    # Contenuto della configurazione kernel
    cat > "$kernel_config_file" << EOF
# OLMS Real-Time Kernel Parameters
# Generato automaticamente per l'utente $ACTUAL_USER

# Parametri RT base
kernel.sched_rt_runtime_us = 950000
kernel.sched_rt_period_us = 1000000

# Migrazione CPU (se supportato)
kernel.sched_migration_cost_ns = 500000

# Granularità wakeup (se supportato)
kernel.sched_wakeup_granularity_ns = 1000000

# Disabilita C-states deep (se supportato)
kernel.sched_mc_power_savings = 0
EOF

    log "Configurazione kernel RT generata in $kernel_config_file"
}

# Generazione permessi taskset/chrt e /proc access
generate_taskset_chrt_permissions() {
    log "Generazione permessi taskset/chrt e /proc access per $ACTUAL_USER..."
    
    local taskset_chrt_rules="/etc/udev/rules.d/99-olms-taskset-chrt.rules"
    
    # Contenuto delle regole taskset/chrt
    cat > "$taskset_chrt_rules" << EOF
# OLMS taskset/chrt Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di usare taskset e chrt senza sudo

# Permessi per taskset (CPU affinity)
KERNEL=="cpu*", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per chrt (scheduling)
KERNEL=="sched*", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per sched_setscheduler
KERNEL=="sched_setscheduler", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per sched_getscheduler
KERNEL=="sched_getscheduler", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per sched_getparam
KERNEL=="sched_getparam", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per sched_setparam
KERNEL=="sched_setparam", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "Regole taskset/chrt generate in $taskset_chrt_rules"
    
    # Aggiunta regole per l'accesso ai file /proc (necessari per la nuova implementazione)
    local proc_rules="/etc/udev/rules.d/99-olms-proc-access.rules"
    
    cat > "$proc_rules" << EOF
# OLMS /proc Access Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di accedere ai file /proc per CPU affinity e scheduling

# Permessi per /proc/*/cpuset (CPU affinity)
KERNEL=="cpuset", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per /proc/*/sched* (scheduling)
KERNEL=="sched*", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"

# Permessi per /proc/*/status (status processi)
KERNEL=="status", SUBSYSTEM=="cpu", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "Regole /proc access generate in $proc_rules"
}

# Configurazione PAM per caricare i limiti RT
configure_pam_limits() {
    log "Configurazione PAM per caricare i limiti RT..."
    
    # File PAM da modificare
    local pam_sudo="/etc/pam.d/sudo"
    local pam_common_session="/etc/pam.d/common-session"
    
    # Verifica e aggiunta regola PAM per sudo
    if [[ -f "$pam_sudo" ]]; then
        if ! grep -q "pam_limits.so" "$pam_sudo"; then
            log "Aggiunta regola PAM a $pam_sudo"
            echo "session required pam_limits.so" >> "$pam_sudo"
        else
            log "Regola PAM già presente in $pam_sudo"
        fi
    else
        warn "File PAM $pam_sudo non trovato"
    fi
    
    # Verifica e aggiunta regola PAM per common-session
    if [[ -f "$pam_common_session" ]]; then
        if ! grep -q "pam_limits.so" "$pam_common_session"; then
            log "Aggiunta regola PAM a $pam_common_session"
            echo "session required pam_limits.so" >> "$pam_common_session"
        else
            log "Regola PAM già presente in $pam_common_session"
        fi
    else
        warn "File PAM $pam_common_session non trovato"
    fi
    
    log "Configurazione PAM completata"
}

# Generazione regole Udev DMA Latency
generate_dma_latency_rules() {
    log "Generazione regole Udev DMA Latency per $ACTUAL_USER..."
    
    local dma_rules_file="/etc/udev/rules.d/99-olms-dma-latency.rules"
    
    # Contenuto delle regole DMA Latency
    cat > "$dma_rules_file" << EOF
# OLMS DMA Latency Permissions
# Generato automaticamente per l'utente $ACTUAL_USER
# Permette all'utente $ACTUAL_USER di impedire alla CPU di andare in risparmio energetico

# Permessi per /dev/cpu_dma_latency (impedisce C-states deep)
KERNEL=="cpu_dma_latency", MODE="0666", OWNER="$ACTUAL_USER", GROUP="$ACTUAL_USER"
EOF

    log "Regole DMA Latency generate in $dma_rules_file"
}

# Configurazione gruppi utente
configure_user_groups() {
    log "Configurazione gruppi utente per $ACTUAL_USER..."
    
    # Aggiungi utente ai gruppi necessari
    local groups=("audio" "realtime" "plugdev")
    
    for group in "${groups[@]}"; do
        if getent group "$group" >/dev/null 2>&1; then
            if ! groups "$ACTUAL_USER" | grep -q "\b$group\b"; then
                log "Aggiunta utente $ACTUAL_USER al gruppo $group"
                usermod -a -G "$group" "$ACTUAL_USER" 2>/dev/null || warn "Impossibile aggiungere $ACTUAL_USER al gruppo $group (potrebbe richiedere riavvio)"
            else
                log "Utente $ACTUAL_USER già nel gruppo $group"
            fi
        else
            log "Gruppo $group non esiste, creazione in corso..."
            groupadd "$group" 2>/dev/null || warn "Impossibile creare il gruppo $group"
            usermod -a -G "$group" "$ACTUAL_USER" 2>/dev/null || warn "Impossibile aggiungere $ACTUAL_USER al gruppo $group"
        fi
    done
}

# Configurazione volume audio USB al 100% per passaggio completo del segnale
configure_audio_volume() {
    log "Configurazione volume audio USB al 100% per passaggio completo del segnale..."
    
    # Trova dispositivi audio USB disponibili
    local usb_devices=$(aplay -l 2>/dev/null | grep -i "USB Audio" | grep -o "card [0-9]*" | cut -d' ' -f2)
    
    if [[ -z "$usb_devices" ]]; then
        log "Nessun dispositivo audio USB trovato"
        return 0
    fi
    
    for card_num in $usb_devices; do
        log "Configurazione volume per scheda audio USB: card $card_num"
        
        # Imposta volume PCM al 100% per passaggio completo del segnale
        if amixer -c "$card_num" set PCM 100% unmute >/dev/null 2>&1; then
            log "✅ Volume PCM impostato al 100% per card $card_num"
        else
            warn "⚠️ Impossibile impostare volume PCM per card $card_num"
        fi
        
        # Imposta volume Master al 100% per passaggio completo del segnale
        if amixer -c "$card_num" set Master 100% unmute >/dev/null 2>&1; then
            log "✅ Volume Master impostato al 100% per card $card_num"
        else
            warn "⚠️ Impossibile impostare volume Master per card $card_num"
        fi
        
        # Imposta volume digitale al 100% se disponibile
        if amixer -c "$card_num" set Digital 100% unmute >/dev/null 2>&1; then
            log "✅ Volume Digital impostato al 100% per card $card_num"
        else
            log "Volume Digital non disponibile per card $card_num (opzionale)"
        fi
    done
    
    log "Configurazione volume audio USB completata"
}

# Installazione Runtime Permission Manager
install_runtime_permission_manager() {
    log "Installazione Runtime Permission Manager..."
    
    local runtime_script="$ACTUAL_HOME/.olms/olms-runtime-permissions.sh"
    local system_script="/usr/local/bin/olms-runtime-permissions"
    
    # Copia lo script nella home directory dell'utente
    if [[ -f "$SCRIPT_DIR/olms-runtime-permissions.sh" ]]; then
        cp "$SCRIPT_DIR/olms-runtime-permissions.sh" "$runtime_script"
        chmod +x "$runtime_script"
        log "Runtime Permission Manager installato in $runtime_script"
    else
        warn "Script Runtime Permission Manager non trovato in $SCRIPT_DIR"
    fi
    
    # Copia lo script nel sistema (richiede sudo)
    if [[ -f "$SCRIPT_DIR/olms-runtime-permissions.sh" ]]; then
        cp "$SCRIPT_DIR/olms-runtime-permissions.sh" "$system_script"
        chmod +x "$system_script"
        log "Runtime Permission Manager installato in $system_script"
    fi
    
    # Configura esecuzione automatica all'avvio
    configure_autostart
}

# Configurazione esecuzione automatica all'avvio
configure_autostart() {
    log "Configurazione esecuzione automatica all'avvio..."
    
    # Crea script di avvio per systemd (se disponibile)
    if command -v systemctl >/dev/null 2>&1; then
        create_systemd_service
    fi
    
    # Crea script di avvio per rc.local (fallback)
    create_rc_local_script
    
    log "Configurazione autostart completata"
}

# Crea servizio systemd per Runtime Permission Manager
create_systemd_service() {
    log "Creazione servizio systemd per Runtime Permission Manager..."
    
    local service_file="/etc/systemd/system/olms-runtime-permissions.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=OLMS Runtime Permission Manager
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/olms-runtime-permissions
RemainAfterExit=yes
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Abilita il servizio
    systemctl daemon-reload
    systemctl enable olms-runtime-permissions.service
    
    log "Servizio systemd creato e abilitato: $service_file"
}

# Crea script rc.local per esecuzione all'avvio (fallback)
create_rc_local_script() {
    log "Creazione script rc.local per Runtime Permission Manager..."
    
    local rc_local="/etc/rc.local"
    local script_content="#!/bin/bash
# OLMS Runtime Permission Manager - Esecuzione all'avvio
if [ -x /usr/local/bin/olms-runtime-permissions ]; then
    /usr/local/bin/olms-runtime-permissions
fi
exit 0"
    
    # Se rc.local esiste, aggiungi la chiamata allo script
    if [[ -f "$rc_local" ]]; then
        # Verifica che la chiamata non sia già presente
        if ! grep -q "olms-runtime-permissions" "$rc_local"; then
            # Aggiungi la chiamata prima dell'exit 0
            sed -i '/^exit 0$/i\
# OLMS Runtime Permission Manager\
if [ -x /usr/local/bin/olms-runtime-permissions ]; then\
    /usr/local/bin/olms-runtime-permissions\
fi' "$rc_local"
            log "Chiamata a Runtime Permission Manager aggiunta a $rc_local"
        else
            log "Chiamata a Runtime Permission Manager già presente in $rc_local"
        fi
    else
        # Crea rc.local
        echo "$script_content" > "$rc_local"
        chmod +x "$rc_local"
        log "File rc.local creato con Runtime Permission Manager: $rc_local"
    fi
}

# Verifica e applicazione configurazioni
apply_configurations() {
    log "Applicazione configurazioni..."
    
    # Applica limiti realtime
    if [[ -f "/etc/security/limits.d/99-olms-realtime.conf" ]]; then
        log "Limiti realtime applicati (richiede riavvio sessione)"
    fi
    
    # Applica configurazione kernel
    if [[ -f "/etc/sysctl.d/99-olms-rt.conf" ]]; then
        log "Applicazione parametri kernel..."
        # Usiamo || true per evitare che set -e interrompa se un parametro è ignoto al kernel
        sysctl -p "/etc/sysctl.d/99-olms-rt.conf" || warn "Alcuni parametri sysctl non sono stati applicati."
        
        # Verifica che i parametri principali siano stati applicati correttamente
        local rt_runtime=$(sysctl -n kernel.sched_rt_runtime_us 2>/dev/null || echo "0")
        local rt_period=$(sysctl -n kernel.sched_rt_period_us 2>/dev/null || echo "0")
        
        if [[ "$rt_runtime" == "950000" ]] && [[ "$rt_period" == "1000000" ]]; then
            log "Configurazione kernel RT applicata"
            log "✅ Kernel parameters RT verificati: runtime=$rt_runtime, period=$rt_period"
        else
            warn "⚠️ Impossibile applicare completamente la configurazione kernel RT"
        fi
    fi
    
    # Applica regole sysfs
    if command -v systemd-tmpfiles >/dev/null 2>&1; then
        log "Applica regole sysfs tramite tmpfiles..."
        systemd-tmpfiles --create /etc/tmpfiles.d/olms-cpu.conf || warn "Errore tmpfiles"
    fi
    
    # Ricarica regole udev
    if command -v udevadm >/dev/null 2>&1; then
        log "Ricarica regole udev..."
        udevadm control --reload-rules
        udevadm trigger
    fi
    
    # Configura volume audio USB al 100% per passaggio completo del segnale
    configure_audio_volume
    
    # Installa Runtime Permission Manager
    install_runtime_permission_manager
    
    # CRITICO: Chiamata esplicita a X11 prima della fine
    configure_x11_environment
}

# Configurazione X11 per transizione root→utente
configure_x11_environment() {
    log "Configurazione ambiente X11 per transizione root→utente..."
    
    # Verifica se esiste un display X11 attivo
    local display_found=false
    local active_display=""
    
    # Ricerca display attivi
    for i in {0..9}; do
        if [[ -S "/tmp/.X11-unix/X$i" ]]; then
            active_display=":$i"
            display_found=true
            break
        fi
    done
    
    if [[ "$display_found" == "false" ]]; then
        warn "Nessun display X11 attivo trovato, creazione display virtuale..."
        # Creazione display virtuale per compatibilità
        active_display=":99"
    fi
    
    log "Display X11 attivo: $active_display"
    
    # Configura variabili d'ambiente X11
    local x11_env_file="/etc/profile.d/olms-x11.sh"
    
    cat > "$x11_env_file" << EOF
# OLMS X11 Environment Variables
# Generato automaticamente per l'utente $ACTUAL_USER

export DISPLAY="$active_display"
export XAUTHORITY="$ACTUAL_HOME/.Xauthority"
export XDG_RUNTIME_DIR="/run/user/$ACTUAL_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$ACTUAL_UID/bus"
export JACK_DEFAULT_SERVER="olms"
export JACK_NO_START_SERVER=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_SESSION_DIR="/dev/shm/jack_olms_0"
EOF

    chmod +x "$x11_env_file"
    log "Variabili d'ambiente X11 configurate in $x11_env_file"
    
    # Configura XAUTHORITY per root
    configure_xauthority_for_root
    
    # Configura permessi xhost
    configure_xhost_permissions
    
    log "Ambiente X11 configurato per transizione root→utente"
}

# Configura XAUTHORITY per root
configure_xauthority_for_root() {
    log "Configurazione XAUTHORITY per root..."
    
    local user_xauth="$ACTUAL_HOME/.Xauthority"
    local root_xauth="/root/.Xauthority"
    
    # Se esiste .Xauthority dell'utente, copialo per root
    if [[ -f "$user_xauth" ]]; then
        log "Copia .Xauthority da $user_xauth a $root_xauth"
        cp "$user_xauth" "$root_xauth"
        chown root:root "$root_xauth"
        chmod 600 "$root_xauth"
        log "✅ .Xauthority configurato per root"
    else
        warn "⚠️ File .Xauthority utente non trovato: $user_xauth"
        warn "⚠️ Root potrebbe non avere accesso al display X11"
    fi
}

# Configura permessi xhost
configure_xhost_permissions() {
    log "Configurazione avanzata permessi xhost..."
    
    # Forza il DISPLAY se non impostato
    export DISPLAY=${DISPLAY:-:0}
    
    # Tenta di autorizzare root a connettersi al server X dell'utente
    if command -v xhost >/dev/null 2>&1; then
        # Esegui xhost come utente reale, non come root, per aprire la porta
        su - "$ACTUAL_USER" -c "DISPLAY=$DISPLAY xhost +si:localuser:root" || \
        warn "xhost non è riuscito ad autorizzare root. Provare manualmente come utente: xhost +si:localuser:root"
    fi
}

# Verifica finale
verify_configuration() {
    log "Verifica configurazione..."
    
    # Verifica gruppi utente
    local groups_ok=true
    for group in "audio" "realtime"; do
        if groups "$ACTUAL_USER" | grep -q "\b$group\b"; then
            log "✅ Gruppo $group: OK"
        else
            warn "⚠️ Gruppo $group: NON CONFIGURATO"
            groups_ok=false
        fi
    done
    
    # Verifica file di configurazione
    local config_files=(
        "/etc/udev/rules.d/99-olms-usb-permissions.rules"
        "/etc/udev/rules.d/99-olms-jack-sockets.rules"
        "/etc/udev/rules.d/99-olms-cpu.rules"
        "/etc/udev/rules.d/99-olms-irq.rules"
        "/etc/tmpfiles.d/olms-cpu.conf"
        "/etc/security/limits.d/99-olms-realtime.conf"
        "/etc/sysctl.d/99-olms-rt.conf"
        "/etc/profile.d/olms-x11.sh"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "✅ File $file: OK"
        else
            warn "⚠️ File $file: NON TROVATO"
            groups_ok=false
        fi
    done
    
    # Verifica limiti utente
    local current_rtprio=$(ulimit -r 2>/dev/null || echo "0")
    local current_memlock=$(ulimit -l 2>/dev/null || echo "0")
    
    log "Limiti correnti: rtprio=$current_rtprio, memlock=${current_memlock}KB"
    
    # Verifica configurazione X11
    log "Verifica configurazione X11..."
    if [[ -f "/etc/profile.d/olms-x11.sh" ]]; then
        log "✅ Variabili d'ambiente X11: OK"
    else
        warn "⚠️ Variabili d'ambiente X11: NON CONFIGURATE"
        groups_ok=false
    fi
    
    if [[ -f "/root/.Xauthority" ]]; then
        log "✅ XAUTHORITY root: OK"
    else
        warn "⚠️ XAUTHORITY root: NON CONFIGURATO"
        groups_ok=false
    fi
    
    if [[ "$groups_ok" == "true" ]]; then
        log "✅ Configurazione completata con successo!"
        log "⚠️ Nota: Alcune modifiche richiedono il riavvio della sessione utente"
    else
        warn "⚠️ Configurazione parziale - alcune modifiche potrebbero non essere attive"
    fi
}

# Funzione principale
main() {
    log "=== OLMS BOOTSTRAP SCRIPT ==="
    log "Configurazione universale per qualsiasi utente Linux"
    
    # Verifica che lo script sia eseguito come root (necessario per modifiche di sistema)
    if [[ "$EUID" -ne 0 ]]; then
        error "Questo script deve essere eseguito come root per modificare i file di sistema"
        error "Esegui: sudo $0"
        exit 1
    fi
    
    detect_user_environment
    create_directories
    generate_usb_rules
    generate_jack_rules
    generate_realtime_limits
    generate_kernel_config
    generate_taskset_chrt_permissions
    configure_pam_limits
    generate_dma_latency_rules
    configure_user_groups
    generate_sysfs_rules
    apply_sysfs_permissions
    apply_configurations
    verify_configuration
    
    log "=== BOOTSTRAP COMPLETATO ==="
    log "L'utente $ACTUAL_USER è ora configurato per l'uso di OLMS"
    log "Per attivare tutte le modifiche, eseguire:"
    log "  - Riavvio della sessione utente"
    log "  - Riavvio del sistema (opzionale ma consigliato)"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
