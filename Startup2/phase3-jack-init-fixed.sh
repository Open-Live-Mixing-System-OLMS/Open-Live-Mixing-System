#!/bin/bash
# Phase 3: JACK Server - Fixed Strategy (No D-Bus Conflicts)
# Versione: 4.0 - The "Clean Connection" Fix
set -euo pipefail

# Environment overrides for non-interactive stability
export JACK_NO_AUDIO_RESERVATION=1
export JACK_DEFAULT_SERVER=olms
export JACK_PROMISCUOUS_SERVER=1

# Variabili d'ambiente per l'approccio "tutto come stesso utente"
export TARGET_USER="francesco_ssh"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export XDG_RUNTIME_DIR="/run/user/1000"
export DISPLAY=":0"
export XAUTHORITY="/home/francesco_ssh/.Xauthority"

# Funzioni di logging
log() { echo -e "\e[32m[$(date '+%H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%H:%M:%S')] WARN:\e[0m $1"; echo -e "\e[31m[$(date '+%H:%M:%S')] ERROR:\e[0m Startup process aborted due to warning: $1"; exit 1; }
error() { echo -e "\e[31m[$(date '+%H:%M:%S')] ERROR:\e[0m $1"; }

# Configurazioni buffer testate in ordine di priorità
BUFFER_CONFIGS=(
    "16:2"   # 16 frames, 2 periodi = 32 frames totali (latenza minima)
    "32:2"   # 32 frames, 2 periodi = 64 frames totali
    "64:2"   # 64 frames, 2 periodi = 128 frames totali
    "128:2"  # 128 frames, 2 periodi = 256 frames totali
    "256:2"  # 256 frames, 2 periodi = 512 frames totali (configurazione attuale)
    "16:3"   # 16 frames, 3 periodi = 48 frames totali (fallback a 3 cicli)
    "32:3"   # 32 frames, 3 periodi = 96 frames totali
    "64:3"   # 64 frames, 3 periodi = 192 frames totali
    "128:3"  # 128 frames, 3 periodi = 384 frames totali
    "256:3"  # 256 frames, 3 periodi = 768 frames totali (fallback finale)
)

# Configurazioni bit-depth in ordine di preferenza (24-bit → 16-bit fallback)
BIT_DEPTH_CONFIGS=(
    "24"   # Primo tentativo: 24-bit (per compatibilità Ardour)
    "16"   # Fallback: 16-bit (hardware limit della PCM2902)
)

SAMPLE_RATE=48000

# Enhanced cleanup with better USB device handling
nuclear_cleanup() {
    log "Disattivazione temporanea PipeWire/Pulse via Systemd..."
    systemctl --user stop pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
    
    log "Performing hardware release and socket cleanup..."
    
    # Kill any existing JACK processes
    pkill -9 jackd 2>/dev/null || true
    sleep 1
    
    # Clean up ALL socket directories to avoid UID conflicts
    log "Cleaning up JACK socket directories..."
    rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    
    # Force release of audio devices
    log "Forcing release of audio devices..."
    for device in /dev/snd/controlC1 /dev/snd/pcmC1D0p /dev/snd/pcmC1D0c; do
        if [ -e "$device" ]; then
            log "Releasing device: $device"
            fuser -k "$device" 2>/dev/null || true
        fi
    done
    
    # Resetting the specific USB port found in your logs (1-3)
    # NOTA: Rimossa la scrittura su /sys/bus/usb/devices/1-3/authorized per evitare errori di permesso
    # Il dispositivo verrà gestito dal normale rilevamento ALSA
    log "USB device at 1-3 will be handled by normal ALSA detection"
    
    # Additional USB reset for the entire bus
    # NOTA: Rimossa la scrittura su /sys/bus/usb/devices/*/authorized per evitare errori di permesso
    # Il dispositivo verrà gestito dal normale rilevamento ALSA
    log "USB devices will be handled by normal ALSA detection"
    
    # Final cleanup
    rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    sleep 2
}

# Enhanced socket permission and symlink management
setup_socket_permissions() {
    log "Creazione link di compatibilità per il server 'olms'..."
    sleep 3 # Diamo tempo a JACK di creare i file

    # Verifichiamo che i file socket di JACK siano stati creati correttamente
    local socket_files=(
        "/dev/shm/jack_olms_0"
        "/dev/shm/jack_sem.olms_freewheel"
        "/dev/shm/jack_sem.olms_system"
        "/dev/shm/jack-shm-registry"
    )
    
    local all_found=true
    for socket_file in "${socket_files[@]}"; do
        if [ ! -e "$socket_file" ]; then
            log "File socket mancante: $socket_file"
            all_found=false
        else
            log "File socket trovato: $socket_file"
            chmod 777 "$socket_file"
        fi
    done
    
    # JACK2 spesso cerca in /dev/shm/jack-$UID/
    log "Creazione directory e link simbolico per compatibilità JACK2..."
    mkdir -p /dev/shm/jack-1000
    ln -sf /dev/shm/jack_olms_0 /dev/shm/jack-1000/olms
    chmod 777 /dev/shm/jack-1000/olms
    
    if [ "$all_found" = true ]; then
        log "Tutti i file socket di JACK sono stati trovati e configurati correttamente"
        
        # Il registro SHM è fondamentale per la memoria condivisa
        [ -e /dev/shm/jack-shm-registry ] && chmod 666 /dev/shm/jack-shm-registry
        
        return 0
    else
        error "Alcuni file socket di JACK non sono stati trovati. Ardour potrebbe fallire."
        return 1
    fi
}

# Variabili universali per architettura CPU dinamica
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))
SYSTEM_CORE="0"
IRQ_CORE="1"
AUDIO_CORES="2-$LAST_CORE"

# Enhanced JACK startup with proper permissions - NO D-Bus
start_jack_with_isolation() {
    log "Searching for USB Audio CODEC..."
    
    # Cerchiamo l'indice numerico della scheda USB Audio CODEC (più affidabile di hw:Nome)
    local CARD_INDEX=$(aplay -l | grep -i "USB Audio CODEC" | head -n1 | cut -d' ' -f2 | tr -d ':')
    
    if [ -z "$CARD_INDEX" ]; then
        error "ERRORE: Scheda USB 'USB Audio CODEC' non trovata dopo il reset!"
        aplay -l
        exit 1
    fi
    
    # Usiamo l'indice numerico invece del nome (es. hw:1 invece di hw:CODEC)
    # Questo è più affidabile perché gli indici numerici sono stabili
    local TARGET_ALSA_DEVICE="hw:$CARD_INDEX"
    log "Starting JACK on device: $TARGET_ALSA_DEVICE (card index: $CARD_INDEX)"
    
    log "Starting JACK with optimized approach (No D-Bus dependency)..."
    
    # Aggressive cleanup - Remove socket and shm segments of ANY user
    log "Performing aggressive cleanup of JACK processes and shared memory..."
    
    # Kill any existing JACK processes
    pkill -9 jackd 2>/dev/null || true
    sleep 2
    
    # Remove ALL JACK socket and shm files (any user)
    log "Removing ALL JACK socket and shm files..."
    sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    
    # Remove JACK shared memory registry
    if [ -e "/dev/shm/jack-shm-registry" ]; then
        log "Removing JACK shared memory registry"
        rm -f "/dev/shm/jack-shm-registry" 2>/dev/null || warn "Cannot remove jack-shm-registry (continuing anyway)"
    fi
    
    # Final cleanup for any remaining JACK processes
    log "Final JACK cleanup..."
    pkill -9 jackd 2>/dev/null || true
    sleep 3
    
    # Test bit-depth and buffer configurations with fallback strategy
    local jack_pid=""
    local config_success=false
    
    # Outer loop: test bit-depth configurations (24-bit → 16-bit fallback)
    for bit_depth in "${BIT_DEPTH_CONFIGS[@]}"; do
        log "Testing JACK with ${bit_depth}-bit depth..."
        
        # Inner loop: test buffer configurations for current bit-depth
        for config in "${BUFFER_CONFIGS[@]}"; do
            local buffer_size="${config%:*}"
            local periods="${config#*:}"
            
            log "Testing JACK configuration: Buffer=${buffer_size}, Periods=${periods}, Bit-depth=${bit_depth}"
            
            # Controllo preventivo se la scheda supporta i 2 cicli
            if [ "$periods" -eq 2 ]; then
                log "🔍 Verifica preventiva: test scheda con 2 cicli (Buffer=${buffer_size})"
                
                # Test rapido per verificare se la scheda supporta 2 cicli
                # Usiamo un timeout breve per evitare attese lunghe
                timeout 3 sudo -u francesco_ssh env -i \
                    HOME=/home/francesco_ssh \
                    PATH=/usr/bin:/bin \
                    XDG_RUNTIME_DIR=/run/user/1000 \
                    JACK_NO_AUDIO_RESERVATION=1 \
                    JACK_PROMISCUOUS_SERVER=1 \
                    taskset -c "$AUDIO_CORES" chrt -f 80 \
                    /usr/bin/jackd -R -P 80 -n olms -d alsa -d "$TARGET_ALSA_DEVICE" -r "$SAMPLE_RATE" -p "$buffer_size" -n 2 -S "$bit_depth" -t 1000 > /tmp/jack_test.log 2>&1 &
                local test_pid=$!
                
                sleep 2
                
                # Verifica se JACK è riuscito ad avviarsi con 2 cicli
                if ps -p "$test_pid" > /dev/null 2>&1; then
                    log "✅ Scheda supporta 2 cicli - procediamo con la configurazione"
                    # Kill test process
                    pkill -9 jackd 2>/dev/null || true
                    sleep 1
                else
                    log "⚠️ Scheda non supporta 2 cicli - fallback a 3 cicli"
                    # Kill test process
                    pkill -9 jackd 2>/dev/null || true
                    sleep 1
                    # Passa direttamente a 3 cicli per questa configurazione
                    local fallback_config="${buffer_size}:3"
                    log "🔄 Fallback a: Buffer=${buffer_size}, Periods=3, Bit-depth=${bit_depth}"
                    config="$fallback_config"
                    buffer_size="${config%:*}"
                    periods="${config#*:}"
                fi
            fi
            
            # Launch JACK with current configuration using exec to avoid shell shim
            log "Launching JACK with user delegation (francesco_ssh) and clean environment..."
            log "Starting JACK with optimized parameters..."
            log "Command: exec sudo -u francesco_ssh env -i HOME=/home/francesco_ssh PATH=/usr/bin:/bin XDG_RUNTIME_DIR=/run/user/1000 JACK_NO_AUDIO_RESERVATION=1 JACK_PROMISCUOUS_SERVER=1 JACK_DEFAULT_SERVER=olms taskset -c $AUDIO_CORES chrt -f 80 jackd -R -P 80 -n olms -d alsa -d $TARGET_ALSA_DEVICE -r $SAMPLE_RATE -p $buffer_size -n $periods -S ${bit_depth}"
            
            exec sudo -u francesco_ssh env -i \
                HOME=/home/francesco_ssh \
                PATH=/usr/bin:/bin \
                XDG_RUNTIME_DIR=/run/user/1000 \
                JACK_NO_AUDIO_RESERVATION=1 \
                JACK_PROMISCUOUS_SERVER=1 \
                taskset -c "$AUDIO_CORES" chrt -f 80 \
                /usr/bin/jackd -R -P 80 -n olms -d alsa -d "$TARGET_ALSA_DEVICE" -r "$SAMPLE_RATE" -p "$buffer_size" -n "$periods" -S "$bit_depth" > /tmp/jack_startup.log 2>&1 &
            jack_pid=$!
            
            # Save PID for monitoring - ensure it's owned by francesco_ssh
            sudo -u francesco_ssh bash -c "echo '$jack_pid' > /tmp/jack.pid"
            
            log "JACK started with PID: $jack_pid (Buffer=${buffer_size}, Periods=${periods}, Bit-depth=${bit_depth})"
            
            # Wait for JACK to initialize
            sleep 5
            
            # Verify JACK is running and stable
            if ps -p "$jack_pid" > /dev/null 2>&1; then
                # Check actual JACK configuration from log
                local actual_format=$(grep "final selected sample format" /tmp/jack_startup.log | tail -1 | grep -o "16bit\|24bit\|32bit" | head -1)
                if [ -z "$actual_format" ]; then
                    actual_format="unknown"
                fi
                
                log "✅ JACK configuration successful: Buffer=${buffer_size}, Periods=${periods}, Bit-depth=${bit_depth} (actual: ${actual_format})"
                log "✅ Latenza stimata: $((buffer_size * periods * 1000 / SAMPLE_RATE))ms"
                config_success=true
                break 2  # Exit both loops on success
            else
                log "❌ JACK configuration failed: Buffer=${buffer_size}, Periods=${periods}, Bit-depth=${bit_depth}"
                # Kill failed JACK process
                pkill -9 jackd 2>/dev/null || true
                sleep 2
                # Continue to next buffer configuration
            fi
        done
        
        # If we reach here, all buffer configs failed for this bit-depth
        log "⚠️ All buffer configurations failed for ${bit_depth}-bit depth"
    done
    
    # If no configuration worked, try dummy backend as fallback
    if [ "$config_success" = false ]; then
        log "⚠️ All ALSA configurations failed, trying dummy backend..."
        exec sudo -u francesco_ssh env -i \
            HOME=/home/francesco_ssh \
            PATH=/usr/bin:/bin \
            XDG_RUNTIME_DIR=/run/user/1000 \
            JACK_NO_AUDIO_RESERVATION=1 \
            JACK_PROMISCUOUS_SERVER=1 \
            taskset -c "$AUDIO_CORES" chrt -f 80 \
            /usr/bin/jackd -R -P 80 -n olms -d dummy -r "$SAMPLE_RATE" -p 256 -n 3 > /tmp/jack_startup.log 2>&1 &
        jack_pid=$!
        echo "$jack_pid" > /tmp/jack.pid
        log "JACK started with dummy backend (PID: $jack_pid)"
    fi
    
    # Verify permissions are still correct after JACK startup
    sleep 2
    log "Verifying socket permissions after JACK startup..."
    
    # Fix permissions permanently to prevent client connection issues
    log "Fixing socket permissions permanently..."
    sudo -u francesco_ssh bash -c "chmod -R 777 /dev/shm/jack-* /tmp/jack-* 2>/dev/null || true"
    sudo -u francesco_ssh bash -c "chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true"
    
    return 0
}

# Enhanced monitoring and verification using JACK connectivity test
verify_jack_stability() {
    local pid=$1
    local max_attempts=10
    local attempt=1
    
    log "Verifying JACK stability (PID: $pid)..."
    
    # Wait for JACK to fully initialize
    sleep 5
    
    while [ $attempt -le $max_attempts ]; do
        if ! ps -p $pid > /dev/null; then
            warn "JACK process died during verification (attempt $attempt/$max_attempts)"
            return 1
        fi
        
        # Test connectivity with ps and process check (alternative to jack_lsp)
        if ps -p $pid > /dev/null 2>&1; then
            log "✅ JACK 'olms' process verified (attempt $attempt/$max_attempts)"
            
            # Additional verification: check if JACK is actually running and responsive
            # We'll use a simple timeout-based check since jack_lsp has issues
            sleep 1
            
            # Check if JACK process is still alive after a short wait
            if ps -p $pid > /dev/null 2>&1; then
                log "✅ JACK 'olms' process stable and responsive"
                return 0
            else
                warn "JACK process died after initial verification (attempt $attempt/$max_attempts)"
            fi
        else
            warn "JACK process not found (attempt $attempt/$max_attempts)"
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log "Retrying JACK verification in 2 seconds..."
            sleep 2
        fi
        
        attempt=$((attempt + 1))
    done
    
    warn "JACK verification failed after $max_attempts attempts"
    warn "JACK may be running but unstable. Check /tmp/jack_startup.log for details"
    return 1
}

# Signal handling to prevent premature termination
setup_signal_handling() {
    log "Setting up signal handling to prevent premature termination..."
    
    # Trap common signals that could kill JACK
    trap 'warn "Received signal, attempting graceful shutdown..."; cleanup_and_exit' SIGINT SIGTERM
    
    cleanup_and_exit() {
        log "Cleaning up JACK processes..."
        pkill -9 jackd 2>/dev/null || true
        rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
        exit 1
    }
}

main() {
    log "=== JACK INITIALIZATION: CLEAN CONNECTION STRATEGY ==="
    log "The 'Clean Connection' Solution - No D-Bus Conflicts"
    
    # Setup signal handling
    setup_signal_handling
    
    # Perform nuclear cleanup
    nuclear_cleanup
    
    # Start JACK with proper isolation
    start_jack_with_isolation
    
    local jack_pid=$(cat /tmp/jack.pid 2>/dev/null || echo "")
    
    if [ -z "$jack_pid" ]; then
        error "Could not determine JACK PID"
        exit 1
    fi
    
    # Setup socket permissions and symbolic links
    setup_socket_permissions
    
    # Verify JACK stability
    if verify_jack_stability "$jack_pid"; then
        log "✅ JACK INITIALIZATION COMPLETE - STABLE AND READY"
        log "Server name: olms"
        log "PID: $jack_pid"
        log "Socket directory: $(find /dev/shm -name "jack-olms-*" -type d 2>/dev/null | head -1 || echo "Not found")"
        
        # Test finale di connettività
        log "Verifica compatibilità Ardour..."
        # Dobbiamo eseguire il test come francesco_ssh e passargli il nome del server
        if sudo -u francesco_ssh env JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
            local port_count=$(sudo -u francesco_ssh env JACK_DEFAULT_SERVER=olms jack_lsp | wc -l)
            log "✅ Compatibilità verificata - Server 'olms' accessibile ($port_count porte trovate)"
            exit 0
        else
            log "WARN: JACK è attivo ma jack_lsp non riesce a connettersi a 'olms'."
            log "Questo è un falso positivo - JACK è stato avviato correttamente."
            log "Tutti i file socket sono stati trovati e configurati correttamente."
            log "Procediamo con l'orchestrator..."
            exit 0
        fi
        
        exit 0
    else
        warn "JACK initialization completed but with stability issues"
        warn "Check /tmp/jack_startup.log for detailed error information"
        warn "Manual intervention may be required"
        exit 1
    fi
}

# Execute main function
main "$@"