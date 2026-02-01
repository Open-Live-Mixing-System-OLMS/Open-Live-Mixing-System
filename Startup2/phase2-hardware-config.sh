#!/bin/bash

# Fase 2: Hardware Configuration & IRQ Pinning
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
AUDIO_CORE=1  # Core dedicato per IRQ audio
CPU_MASK_CORE_1="0x2"  # Maschera hex per core 1

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

# Rilevamento hardware audio
detect_audio_hardware() {
    log "Rilevamento hardware audio..."
    
    local audio_irqs=()
    
    # Metodo 1: Ricerca IRQ tradizionale - Parsing robusto
    log "Metodo 1: Ricerca IRQ tradizionale..."
    local traditional_patterns=("snd" "audio" "sound" "hda" "hdaudio" "intel.*audio" "realtek" "creative" "emu")
    
    # Leggi /proc/interrupts con parsing sicuro
    while IFS= read -r line; do
        # Salta intestazioni e linee vuote
        if [[ ! "$line" =~ ^[0-9]+: ]]; then
            continue
        fi
        
        # Estrai IRQ number in modo sicuro
        local irq=$(echo "$line" | grep -o '^[0-9]*:' | tr -d ':')
        local description=$(echo "$line" | sed 's/^[0-9]*:[[:space:]]*//')
        
        # Verifica range IRQ valido
        if [[ "$irq" =~ ^[0-9]+$ ]] && [[ $irq -ge 0 ]] && [[ $irq -le 4095 ]]; then
            # Controlla pattern tradizionali
            for pattern in "${traditional_patterns[@]}"; do
                if echo "$description" | grep -iqE "$pattern"; then
                    audio_irqs+=("$irq")
                    log "IRQ $irq identificato come audio: $description"
                    break
                fi
            done
        fi
    done < /proc/interrupts
    
    # Metodo 2: USB Audio Controller
    log "Metodo 2: Rilevamento controller USB audio..."
    local usb_patterns=("xhci_hcd" "ehci_hcd" "uhci_hcd")
    
    while IFS= read -r line; do
        local irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        local description=$(echo "$line" | cut -d' ' -f2-)
        
        if [[ "$irq" =~ ^[0-9]+$ ]] && [[ $irq -ge 0 ]] && [[ $irq -le 4095 ]]; then
            for pattern in "${usb_patterns[@]}"; do
                if echo "$description" | grep -iqE "$pattern"; then
                    # Verifica se ci sono dispositivi ALSA USB
                    if arecord -l 2>/dev/null | grep -i "USB\|usb" || aplay -l 2>/dev/null | grep -i "USB\|usb"; then
                        audio_irqs+=("$irq")
                        log "IRQ $irq identificato come USB audio controller: $description"
                        break
                    fi
                fi
            done
        fi
    done < /proc/interrupts
    
    # Metodo 3: ALSA device verification
    log "Metodo 3: Verifica dispositivi ALSA..."
    if command -v arecord >/dev/null 2>&1; then
        local alsa_devices=$(arecord -l 2>/dev/null | grep -i "USB\|usb\|audio" || true)
        if [[ -n "$alsa_devices" ]]; then
            log "Dispositivi ALSA USB trovati:"
            echo "$alsa_devices" | while read -r device; do
                log "  $device"
            done
        fi
    fi
    
    # Rimuovi duplicati e restituisci
    printf '%s\n' "${audio_irqs[@]}" | sort -u
}

# Configurazione IRQ affinity
configure_irq_affinity() {
    local audio_irqs=("$@")
    
    if [[ ${#audio_irqs[@]} -eq 0 ]]; then
        warn "Nessun IRQ audio rilevato"
        return 0
    fi
    
    log "Configurazione IRQ affinity per ${#audio_irqs[@]} IRQ audio..."
    
    for irq in "${audio_irqs[@]}"; do
        local affinity_file="/proc/irq/${irq}/smp_affinity"
        
        # Verifica se il file esiste e è scrivibile
        if [[ ! -f "$affinity_file" ]]; then
            warn "File affinity non trovato per IRQ $irq"
            continue
        fi
        
        # Verifica configurabilità
        local current_affinity=$(cat "$affinity_file" 2>/dev/null || echo "")
        if [[ -z "$current_affinity" ]]; then
            warn "Impossibile leggere affinity per IRQ $irq"
            continue
        fi
        
        log "Configurazione IRQ $irq (core $AUDIO_CORE, maschera: $CPU_MASK_CORE_1)"
        
        # Tentativo 1: Pinning standard
        if echo "$CPU_MASK_CORE_1" > "$affinity_file" 2>/dev/null; then
            log "IRQ $irq pinato al core $AUDIO_CORE"
        else
            # Tentativo 2: Con sudo
            if echo "$CPU_MASK_CORE_1" | sudo tee "$affinity_file" >/dev/null 2>&1; then
                log "IRQ $irq pinato al core $AUDIO_CORE (con sudo)"
            else
                warn "Impossibile pinare IRQ $irq al core $AUDIO_CORE (permessi insufficienti)"
                
                # Tentativo 3: Fallback strategies con sudo
                log "Applicando fallback strategies per IRQ $irq..."
                
                # Fallback 1: Maschera estesa (core audio + core adiacente)
                local extended_mask="0x3"  # Core 0 + 1
                if echo "$extended_mask" | sudo tee "$affinity_file" >/dev/null 2>&1; then
                    log "IRQ $irq pinato a maschera estesa: $extended_mask"
                    continue
                fi
                
                # Fallback 2: Prova altri core con sudo
                for fallback_core in 2 3 4; do
                    local fallback_mask=$(printf "0x%x" $((1 << fallback_core)))
                    if echo "$fallback_mask" | sudo tee "$affinity_file" >/dev/null 2>&1; then
                        log "IRQ $irq pinato al core $fallback_core (fallback)"
                        break
                    fi
                done
                
                # Fallback 3: Registra l'IRQ per configurazione systemd
                log "Registrazione IRQ $irq per configurazione systemd..."
                echo "$irq:$CPU_MASK_CORE_1" >> /tmp/olms-irq-config.txt
            fi
        fi
        
        # Verifica pinning
        local final_affinity=$(cat "$affinity_file" 2>/dev/null || echo "")
        if [[ "$final_affinity" == "$CPU_MASK_CORE_1" ]]; then
            log "Verifica IRQ $irq: pinning confermato"
        else
            warn "Verifica IRQ $irq: pinning non confermato (attuale: $final_affinity)"
        fi
    done
}

# Verifica IRQ configuration
verify_irq_configuration() {
    log "Verifica configurazione IRQ..."
    
    local verified_irqs=0
    local total_irqs=0
    
    # Leggi tutti gli IRQ e verifica quelli audio
    while IFS= read -r line; do
        local irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        local description=$(echo "$line" | cut -d' ' -f2-)
        
        if [[ "$irq" =~ ^[0-9]+$ ]] && [[ $irq -ge 0 ]] && [[ $irq -le 4095 ]]; then
            total_irqs=$((total_irqs + 1))
            
            # Verifica se è un IRQ audio
            if echo "$description" | grep -iqE "snd|audio|sound|hda|usb.*audio|audio.*usb"; then
                local affinity_file="/proc/irq/${irq}/smp_affinity"
                local current_affinity=$(cat "$affinity_file" 2>/dev/null || echo "")
                
                if [[ -n "$current_affinity" ]]; then
                    log "IRQ $irq: $description -> affinity: $current_affinity"
                    verified_irqs=$((verified_irqs + 1))
                else
                    warn "IRQ $irq: impossibile leggere affinity"
                fi
            fi
        fi
    done < /proc/interrupts
    
    log "Verifica completata: $verified_irqs IRQ audio su $total_irqs totali"
    
    if [[ $verified_irqs -gt 0 ]]; then
        log "IRQ pinning: $verified_irqs IRQ audio configurati"
    else
        warn "Nessun IRQ audio configurato"
    fi
}

# Hardware reset e rilevamento finale
final_hardware_check() {
    log "Hardware check finale..."
    
    # Verifica dispositivi audio
    if [[ -d "/dev/snd" ]]; then
        log "Dispositivi audio rilevati:"
        ls -la /dev/snd/ | while read -r line; do
            log "  $line"
        done
        
        # Verifica permessi
        local device_users=$(fuser /dev/snd/* 2>/dev/null || true)
        if [[ -n "$device_users" ]]; then
            warn "Dispositivi audio in uso da PID: $device_users"
        else
            log "Dispositivi audio liberi"
        fi
    else
        warn "Nessun dispositivo audio rilevato in /dev/snd"
    fi
    
    # Verifica ALSA
    if command -v aplay >/dev/null 2>&1; then
        local alsa_cards=$(aplay -l 2>/dev/null | head -10 || true)
        if [[ -n "$alsa_cards" ]]; then
            log "Schede audio ALSA:"
            echo "$alsa_cards" | while read -r card; do
                log "  $card"
            done
        fi
    fi
    
    # Verifica USB audio
    if lsusb >/dev/null 2>&1; then
        local usb_audio=$(lsusb 2>/dev/null | grep -i audio || true)
        if [[ -n "$usb_audio" ]]; then
            log "Dispositivi USB audio:"
            echo "$usb_audio" | while read -r device; do
                log "  $device"
            done
        fi
    fi
}

# Funzione principale
main() {
    log "=== FASE 2: CONFIGURAZIONE HARDWARE & IRQ PINNING ==="
    info "Core audio dedicato: $AUDIO_CORE (maschera: $CPU_MASK_CORE_1)"
    
    # Rilevamento hardware
    local audio_irqs=($(detect_audio_hardware))
    
    # Configurazione IRQ affinity
    configure_irq_affinity "${audio_irqs[@]}"
    
    # Verifica configurazione
    verify_irq_configuration
    
    # Hardware check finale
    final_hardware_check
    
    log "Configurazione hardware e IRQ pinning completata"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi