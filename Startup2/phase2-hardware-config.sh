#!/bin/bash

# Fase 2: Hardware Configuration & IRQ Pinning
# Versione: 2.0

set -euo pipefail

# Configurazione
OLMS_HOME="$HOME/.olms"
mkdir -p "$OLMS_HOME"
LOG_FILE="$OLMS_HOME/olms-orchestrator.log"
AUDIO_CORE=1  # Core dedicato per IRQ audio
CPU_MASK_CORE_1="0x2"  # Maschera hex per core 1

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

# Rilevamento hardware audio - VERSIONE DINAMICA
detect_audio_hardware() {
    log "Rilevamento hardware audio (approccio dinamico)..."
    local audio_irqs=()
    # Pattern specifici per evitare falsi positivi
    local patterns="snd|audio|sound|hda|xhci_hcd|ehci_hcd"
    
    # Prendiamo SOLO le righe da /proc/interrupts che iniziano con un numero
    # Ignoriamo completamente i messaggi di log o timestamp
    while read -r irq; do
        if [[ -n "$irq" ]]; then
            audio_irqs+=("$irq")
            log "IRQ $irq identificato per ottimizzazione."
        fi
    done < <(grep -iE "$patterns" /proc/interrupts | awk -F: '{print $1}' | tr -d ' ')
    
    printf '%s\n' "${audio_irqs[@]}" | sort -nu
}

# Funzione per trovare IRQ USB in modo dinamico (soluzione al problema IRQ 122)
find_usb_irq_dynamic() {
    log "Ricerca IRQ USB dinamico per xhci_hcd..."
    
    # Cerca l'IRQ associato a xhci_hcd (controller USB)
    # Formato /proc/interrupts: "122:      40313    4390635          0          0 PCI-MSI-0000:00:14.0    0-edge      xhci_hcd"
    local usb_irq=$(grep "xhci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':')
    
    if [[ -n "$usb_irq" ]]; then
        log "IRQ USB trovato dinamicamente: $usb_irq (driver: xhci_hcd)"
        echo "$usb_irq"
    else
        # Fallback: cerca altri pattern USB
        local usb_irq_alt=$(grep -E "usb.*hcd|ehci_hcd" /proc/interrupts | awk '{print $1}' | tr -d ':' | head -1)
        if [[ -n "$usb_irq_alt" ]]; then
            log "IRQ USB alternativo trovato: $usb_irq_alt"
            echo "$usb_irq_alt"
        else
            log "Nessun IRQ USB trovato dinamicamente"
            echo ""
        fi
    fi
}

# Configurazione IRQ affinity - ENHANCED VERSION with IRQ 126 Fix
configure_irq_affinity() {
    local audio_irqs=("$@")
    [[ ${#audio_irqs[@]} -eq 0 ]] && { log "Nessun IRQ audio rilevato dai pattern standard"; }
    
    log "Configurazione IRQ affinity per IRQ rilevati..."
    
    # Uniamo gli IRQ rilevati con quello USB dinamico per processarli tutti insieme
    local usb_irq=$(find_usb_irq_dynamic)
    if [[ -n "$usb_irq" ]]; then
        audio_irqs+=("$usb_irq")
    fi

    # Rimuovi duplicati
    local unique_irqs=($(printf "%s\n" "${audio_irqs[@]}" | sort -u))

    for irq in "${unique_irqs[@]}"; do
        local affinity_file="/proc/irq/${irq}/smp_affinity"
        
        if [[ ! -f "$affinity_file" ]]; then 
            log "IRQ $irq non presente in /proc/irq, salto..."
            continue 
        fi

        log "Tentativo pinning IRQ $irq sul core $AUDIO_CORE..."
        
        local success=false
        # Tentativo 1: Maschera esadecimale (0x2 per core 1)
        if { echo "0x2" > "$affinity_file"; } 2>/dev/null; then
            log "IRQ $irq: OK (Core $AUDIO_CORE) - Maschera esadecimale"
            success=true
        # Tentativo 2: ID core numerico
        elif { echo "$AUDIO_CORE" > "/proc/irq/$irq/smp_affinity_list"; } 2>/dev/null; then
            log "IRQ $irq: OK (Core $AUDIO_CORE) - ID core numerico"
            success=true
        fi
        
        if [[ "$success" == "false" ]]; then
            log "WARNING: IRQ $irq non rilocabile (permesso negato o hardware fisso)"
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
        # Non bloccare l'avvio se audio è disabilitato
        local enable_status=$(cat /sys/module/snd_hda_intel/parameters/enable 2>/dev/null || echo "")
        if [[ "$enable_status" =~ ^N, ]]; then
            log "Nessun IRQ audio configurato (audio disabilitato via kernel parameter - normale)"
        else
            warn "Nessun IRQ audio configurato"
        fi
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

# Funzione per preparare il sistema
prepare_system() {
    if systemctl is-active --quiet irqbalance; then
        log "Disattivazione permanente irqbalance per sbloccare gli IRQ..."
        systemctl stop irqbalance
        systemctl mask irqbalance
    fi
}

# Funzione per configurare i volumi hardware dopo il reload dei moduli
fix_hardware_volumes() {
    log "Configurazione volumi hardware per PCM2902..."
    
    # Prova diversi metodi per impostare il volume al 100% e sbloccare
    local success=false
    
    # Metodo 1: Usa il nome del controllo PCM
    if amixer -c 1 sset 'PCM' 100% unmute 2>/dev/null; then
        log "✅ Volume PCM impostato al 100% (metodo 1)"
        success=true
    fi
    
    # Metodo 2: Usa il controllo specifico numid=4 (se il primo fallisce)
    if [[ "$success" == "false" ]] && amixer -c 1 cset numid=4 128 2>/dev/null; then
        log "✅ Volume impostato tramite numid=4 (metodo 2)"
        success=true
    fi
    
    # Metodo 3: Prova con Capture se PCM non è disponibile
    if [[ "$success" == "false" ]] && amixer -c 1 sset 'Capture' 100% unmute 2>/dev/null; then
        log "✅ Volume Capture impostato al 100% (metodo 3)"
        success=true
    fi
    
    # Metodo 4: Prova con Master se altri metodi falliscono
    if [[ "$success" == "false" ]] && amixer -c 1 sset 'Master' 100% unmute 2>/dev/null; then
        log "✅ Volume Master impostato al 100% (metodo 4)"
        success=true
    fi
    
    if [[ "$success" == "false" ]]; then
        warn "Impossibile configurare il volume hardware automaticamente"
        warn "Suggerimento: eseguire manualmente 'amixer -c 1 cset numid=4 128'"
    else
        log "Volume hardware configurato correttamente"
    fi
}

# Funzione principale
main() {
    prepare_system
    
    log "=== FASE 2: OTTIMIZZAZIONE HARDWARE ==="
    info "Core audio dedicato: $AUDIO_CORE (maschera: $CPU_MASK_CORE_1)"
    
    # Rilevamento hardware
    local audio_irqs=($(detect_audio_hardware))
    
    # Configurazione IRQ affinity
    configure_irq_affinity "${audio_irqs[@]}"
    
    # Verifica configurazione
    verify_irq_configuration
    
    # Configurazione volumi hardware (nuova funzione per prevenire il problema del volume a zero)
    fix_hardware_volumes
    
    # Hardware check finale
    final_hardware_check
    
    log "Configurazione hardware, IRQ pinning e volumi completata"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi