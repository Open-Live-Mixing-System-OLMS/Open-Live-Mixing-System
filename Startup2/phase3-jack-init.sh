#!/bin/bash

# Fase 3: JACK Server Initialization
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
JACK_LOG_FILE="/tmp/jack_startup.log"
JACK_PID_FILE="/tmp/jack.pid"
JACK_CONFIG_FILE="/tmp/jack_config.conf"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE" >&2
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE" >&2
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE" >&2
}

# Rilevamento dispositivo audio USB
detect_usb_audio_device() {
    log "Rilevamento dispositivo audio USB..."
    
    # Leggi /proc/asound/cards per pattern USB
    if [[ -f "/proc/asound/cards" ]]; then
        local usb_cards=$(grep -i "usb" /proc/asound/cards 2>/dev/null || true)
        if [[ -n "$usb_cards" ]]; then
            log "Schede audio USB rilevate:"
            echo "$usb_cards" | while read -r card; do
                log "  $card"
            done
        fi
    fi
    
    # Usa aplay per filtrare dispositivi USB
    if command -v aplay >/dev/null 2>&1; then
        local usb_devices=$(aplay -l 2>/dev/null | grep -i "usb\|USB" || true)
        if [[ -n "$usb_devices" ]]; then
            log "Dispositivi audio USB trovati:"
            echo "$usb_devices" | while read -r device; do
                log "  $device"
            done
            
            # Estrai numero card in modo più robusto
            local card_line=$(echo "$usb_devices" | head -1)
            local card_number=$(echo "$card_line" | grep -o "card [0-9]" | grep -o "[0-9]" || echo "")
            
            if [[ -n "$card_number" ]]; then
                local device_string="hw:${card_number},0"
                log "Dispositivo audio selezionato: $device_string"
                echo "$device_string"
                return 0
            else
                warn "Impossibile estrarre numero card dal dispositivo USB"
            fi
        fi
    fi
    
    warn "Nessun dispositivo audio USB rilevato"
    return 1
}

# Verifica accessibilità dispositivo
validate_audio_device() {
    local device="$1"
    
    log "Validazione accessibilità dispositivo: $device"
    
    # Verifica permessi file
    if [[ -c "/dev/snd/pcmC${device#,}" ]] 2>/dev/null; then
        log "Dispositivo accessibile: /dev/snd/pcmC${device#,}"
    else
        warn "Dispositivo non accessibile: $device"
    fi
    
    # Test accesso hardware
    if command -v fuser >/dev/null 2>&1; then
        local device_users=$(fuser "/dev/snd/pcmC${device#,}" 2>/dev/null || true)
        if [[ -n "$device_users" ]]; then
            warn "Dispositivo in uso da PID: $device_users"
        else
            log "Dispositivo disponibile per JACK"
        fi
    fi
}

# Startup JACK con strategia adattiva
start_jack_with_strategy() {
    local device="$1"
    local strategy="$2"
    
    log "Avvio JACK con strategia: $strategy (device: $device)"
    
        # Costruisci comando JACK
    local jack_cmd="jackd"
    
    # Parametri base JACK (Globali - vanno PRIMA del backend)
    # Rimosso -r 48000 da qui, va messo nel backend
    local base_params="-R -S -P 80"
    
    # Parametri specifici per strategia (Backend - vanno DOPO il backend)
    local strategy_params=""
    case "$strategy" in
        "optimal")
            # Nota: -d hw:2,0 (minuscolo) e NON -device
            local dev_cmd=""
            [[ -n "$device" ]] && dev_cmd="-d $device"
            strategy_params="-d alsa -r 48000 -p 64 -n 3 $dev_cmd"
            ;;
        "fallback")
            local dev_cmd=""
            [[ -n "$device" ]] && dev_cmd="-d $device"
            strategy_params="-d alsa -r 48000 -p 128 -n 3 $dev_cmd"
            ;;
        "dummy")
            strategy_params="-d dummy -r 48000 -p 128"
            ;;
    esac
    
    # CPU isolation per core audio
    local audio_cores="2-3"
    
    # Verifica permessi realtime prima di avviare
    if ! ulimit -r >/dev/null 2>&1; then
        warn "Permessi realtime non disponibili, riduzione priorità"
        base_params="${base_params/-P 80/-P 50}"
    fi
    
    # Costruisci comando completo
    local full_cmd="$jack_cmd $base_params $strategy_params"
    
    # Avvia JACK con taskset e chrt
    log "Esecuzione: taskset -c $audio_cores chrt -f 80 $full_cmd"
    
    # Redirect output to log file with timeout
    timeout 10s bash -c "
        taskset -c $audio_cores chrt -f 80 $full_cmd 2>&1
    " | tee -a "$JACK_LOG_FILE" &
    
    local jack_pid=$!
    echo "$jack_pid" > "$JACK_PID_FILE"
    
    log "JACK avviato con PID: $jack_pid"
    
    # Attendi un po' per permettere l'avvio
    sleep 1
    
    # Verifica che il processo sia ancora attivo
    if kill -0 "$jack_pid" 2>/dev/null; then
        log "JACK processo confermato attivo"
        return 0
    else
        warn "JACK processo terminato immediatamente"
        return 1
    fi
}

# Verifica stabilità JACK
verify_jack_stability() {
    log "Verifica stabilità JACK..."
    
    local max_attempts=10
    local attempt=1
    local success_count=0
    
    while [[ $attempt -le $max_attempts ]]; do
        log "Verifica JACK (tentativo $attempt/$max_attempts)..."
        
        # Verifica processo
        local jack_pid=$(cat "$JACK_PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$jack_pid" ]] && kill -0 "$jack_pid" 2>/dev/null; then
            log "Processo JACK attivo (PID: $jack_pid)"
        else
            warn "Processo JACK non attivo"
            return 1
        fi
        
        # Verifica socket JACK
        local socket_found=false
        local user_id=$(id -u)
        
        # Cerca socket file
        local socket_patterns=(
            "/dev/shm/jack_default_${user_id}_0"
            "/tmp/.jack_default_${user_id}_0"
            "/tmp/jack_default_${user_id}_0"
        )
        
        for pattern in "${socket_patterns[@]}"; do
            if [[ -f "$pattern" ]]; then
                log "Socket JACK trovato: $pattern"
                socket_found=true
                break
            fi
        done
        
        if [[ "$socket_found" == "false" ]]; then
            warn "Socket JACK non trovato"
        fi
        
        # Verifica porte JACK con timeout
        local ports=""
        if command -v jack_lsp >/dev/null 2>&1; then
            # Timeout di 5 secondi per jack_lsp
            ports=$(timeout 5s jack_lsp 2>/dev/null || echo "")
            if [[ -n "$ports" ]]; then
                log "Porte JACK attive:"
                echo "$ports" | while read -r port; do
                    log "  $port"
                done
                success_count=$((success_count + 1))
            else
                warn "Nessuna porta JACK attiva"
            fi
        fi
        
        # Verifica buffer configuration
        local bufsize="unknown"
        if command -v jack_bufsize >/dev/null 2>&1; then
            bufsize=$(timeout 3s jack_bufsize 2>/dev/null || echo "unknown")
            log "Buffer size: $bufsize"
        fi
        
        local samplerate="unknown"
        if command -v jack_samplerate >/dev/null 2>&1; then
            samplerate=$(timeout 3s jack_samplerate 2>/dev/null || echo "unknown")
            log "Sample rate: $samplerate"
        fi
        
        # Calcolo latenza
        if [[ "$bufsize" != "unknown" ]] && [[ "$samplerate" != "unknown" ]] && [[ "$bufsize" != "0" ]] && [[ "$samplerate" != "0" ]]; then
            local latency_ms=$((bufsize * 1000 / samplerate))
            log "Latency stimata: ${latency_ms}ms"
            
            if [[ $latency_ms -le 10 ]]; then
                log "Latency accettabile (<10ms)"
                success_count=$((success_count + 1))
            else
                warn "Latency troppo alta: ${latency_ms}ms"
            fi
        fi
        
        # Se abbiamo abbastanza successi, consideriamo JACK stabile
        if [[ $success_count -ge 2 ]]; then
            log "JACK stabile rilevato dopo $attempt tentativi"
            return 0
        fi
        
        # Attendi prima del prossimo tentativo
        if [[ $attempt -lt $max_attempts ]]; then
            log "Attesa 3s prima del prossimo tentativo..."
            sleep 3
        fi
        
        attempt=$((attempt + 1))
    done
    
    warn "Verifica JACK completata con warning (successi: $success_count)"
    return 0
}

# Pulizia JACK in caso di fallimento
cleanup_jack() {
    log "Pulizia JACK in corso..."
    
    # Termina processo JACK se esiste
    local jack_pid=$(cat "$JACK_PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$jack_pid" ]] && kill -0 "$jack_pid" 2>/dev/null; then
        log "Terminazione processo JACK (PID: $jack_pid)"
        kill -TERM "$jack_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$jack_pid" 2>/dev/null || true
    fi
    
    # Rimuovi file PID
    rm -f "$JACK_PID_FILE"
    
    # Rimuovi socket JACK
    local user_id=$(id -u)
    local socket_patterns=(
        "/dev/shm/jack_default_${user_id}_0"
        "/tmp/.jack_default_${user_id}_0"
        "/tmp/jack_default_${user_id}_0"
    )
    
    for pattern in "${socket_patterns[@]}"; do
        if [[ -f "$pattern" ]]; then
            log "Rimozione socket JACK: $pattern"
            rm -f "$pattern"
        fi
    done
    
    log "Pulizia JACK completata"
}

# Funzione principale
main() {
    log "=== FASE 3: JACK SERVER INITIALIZATION ==="
    
    # Rilevamento dispositivo audio
    local audio_device=""
    if audio_device=$(detect_usb_audio_device); then
        validate_audio_device "$audio_device"
    else
        warn "Dispositivo audio USB non rilevato, uso strategia fallback"
        audio_device=""
    fi
    
    # Tentativo 1: Strategia ottimale (64 samples)
    log "Tentativo 1: Strategia ottimale (64 samples)..."
    if start_jack_with_strategy "$audio_device" "optimal"; then
        if verify_jack_stability; then
            log "JACK avviato con successo (strategia ottimale)"
            return 0
        fi
    fi
    
    # Cleanup dopo fallimento tentativo 1
    cleanup_jack
    
    # Tentativo 2: Strategia fallback (128 samples)
    log "Tentativo 2: Strategia fallback (128 samples)..."
    if start_jack_with_strategy "$audio_device" "fallback"; then
        if verify_jack_stability; then
            log "JACK avviato con successo (strategia fallback)"
            return 0
        fi
    fi
    
    # Cleanup dopo fallimento tentativo 2
    cleanup_jack
    
    # Tentativo 3: Backend dummy (ultimo fallback)
    log "Tentativo 3: Backend dummy (ultimo fallback)..."
    if start_jack_with_strategy "" "dummy"; then
        if verify_jack_stability; then
            warn "JACK avviato in modalità dummy (virtuale)"
            return 0
        fi
    fi
    
    # Cleanup finale
    cleanup_jack
    
    error "Impossibile avviare JACK con nessuna strategia"
    return 1
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi