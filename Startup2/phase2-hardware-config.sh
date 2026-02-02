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
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Rilevamento hardware audio - VERSIONE PULITA
detect_audio_hardware() {
    log "Rilevamento hardware audio..."
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

# Configurazione IRQ affinity - ENHANCED VERSION with IRQ 126 Fix
configure_irq_affinity() {
    local audio_irqs=("$@")
    [[ ${#audio_irqs[@]} -eq 0 ]] && { warn "Nessun IRQ audio rilevato"; return 0; }
    
    log "Configurazione IRQ affinity per ${#audio_irqs[@]} IRQ audio (ENHANCED)..."
    
    # Assicuriamoci che il file di log di fallback sia scrivibile
    # Controllo proprietà file prima della rimozione
    if [[ -f "$OLMS_HOME/olms-irq-config.txt" ]]; then
        file_owner=$(stat -c '%U' "$OLMS_HOME/olms-irq-config.txt" 2>/dev/null || echo "unknown")
        if [[ "$file_owner" == "$(whoami)" ]]; then
            rm -f "$OLMS_HOME/olms-irq-config.txt" 2>/dev/null || warn "Impossibile rimuovere $OLMS_HOME/olms-irq-config.txt (permesso negato)"
        else
            log "Saltato $OLMS_HOME/olms-irq-config.txt (appartiene a $file_owner)"
        fi
    fi
    touch "$OLMS_HOME/olms-irq-config.txt" 2>/dev/null || warn "Impossibile creare $OLMS_HOME/olms-irq-config.txt (permesso negato)"
    
    for irq in "${audio_irqs[@]}"; do
        local affinity_file="/proc/irq/${irq}/smp_affinity"
        
        if [[ ! -f "$affinity_file" ]]; then continue; fi

        log "Tentativo pinning IRQ $irq sul core $AUDIO_CORE..."
        
        # Proviamo entrambi i metodi: smp_affinity (mask) e smp_affinity_list (ID core)
        # DOPPIO TENTATIVO con formati diversi per risolvere il problema IRQ 126
        local success=false
        
        # Tentativo 1: Maschera esadecimale (0x2)
        if { echo "0x2" > "$affinity_file"; } 2>/dev/null; then
            log "IRQ $irq: OK (Core $AUDIO_CORE) - Maschera esadecimale"
            success=true
        elif { echo "$CPU_MASK_CORE_1" > "$affinity_file"; } 2>/dev/null; then
            log "IRQ $irq: OK (Core $AUDIO_CORE) - Maschera esadecimale alternativa"
            success=true
        fi
        
        # Tentativo 2: ID core numerico
        if [[ "$success" == "false" ]] && { echo "$AUDIO_CORE" > "/proc/irq/$irq/smp_affinity_list"; } 2>/dev/null; then
            log "IRQ $irq: OK (Core $AUDIO_CORE) - ID core numerico"
            success=true
        fi
        
        # Tentativo 3: Maschera binaria
        if [[ "$success" == "false" ]] && { echo "2" > "$affinity_file"; } 2>/dev/null; then
            log "IRQ $irq: OK (Core $AUDIO_CORE) - Maschera binaria"
            success=true
        fi
        
        if [[ "$success" == "false" ]]; then
            # Se ancora fallisce, verifichiamo se l'IRQ è rilocabile
            local mask=$(cat "$affinity_file" 2>/dev/null || echo "unknown")
            warn "IRQ $irq bloccato su affinity: $mask. Tentativo di forzatura fallito."
            
            # Notifica specifica per IRQ 126
            if [[ "$irq" == "126" ]]; then
                warn "IRQ 126: Problema specifico rilevato - potrebbe richiedere riavvio del kernel"
                warn "Suggerimento: Verifica che il kernel supporti il pinning IRQ 126"
            fi
        fi
    done
    
    # Gestione specifica per IRQ 122 (Controller USB)
    log "Gestione specifica per IRQ 122 (Controller USB)..."
    if [[ -f "/proc/irq/122/smp_affinity" ]]; then
        log "Tentativo pinning IRQ 122 sul core $AUDIO_CORE..."
        local success=false
        
        # Doppio tentativo per IRQ 122
        if { echo "0x2" > "/proc/irq/122/smp_affinity"; } 2>/dev/null; then
            log "IRQ 122: OK (Core $AUDIO_CORE) - Maschera esadecimale"
            success=true
        elif { echo "$AUDIO_CORE" > "/proc/irq/122/smp_affinity_list"; } 2>/dev/null; then
            log "IRQ 122: OK (Core $AUDIO_CORE) - ID core numerico"
            success=true
        fi
        
        if [[ "$success" == "false" ]]; then
            local mask=$(cat "/proc/irq/122/smp_affinity" 2>/dev/null || echo "unknown")
            warn "IRQ 122 bloccato su affinity: $mask. Tentativo di forzatura fallito."
        fi
    else
        warn "IRQ 122 non trovato o non accessibile"
    fi
    
    # Gestione specifica per IRQ 126 (PROBLEMA PRINCIPALE)
    log "Gestione specifica per IRQ 126 (CORREZIONE SPECIFICA)..."
    if [[ -f "/proc/irq/126/smp_affinity" ]]; then
        log "Tentativo pinning IRQ 126 sul core $AUDIO_CORE (CORREZIONE SPECIFICA)..."
        
        # CORREZIONE: Forza la maschera esadecimale corretta
        if { echo "0x2" > "/proc/irq/126/smp_affinity"; } 2>/dev/null; then
            local new_affinity=$(cat "/proc/irq/126/smp_affinity" 2>/dev/null || echo "unknown")
            log "IRQ 126: CORRETTO (Core $AUDIO_CORE) - Maschera esadecimale 0x2 impostata"
            log "IRQ 126: Nuova affinity: $new_affinity"
        else
            local current_affinity=$(cat "/proc/irq/126/smp_affinity" 2>/dev/null || echo "unknown")
            warn "IRQ 126: Impossibile correggere affinity (corrente: $current_affinity)"
            warn "IRQ 126: Potrebbe richiedere riavvio del kernel o modifica GRUB"
            warn "Suggerimento: Aggiungi 'irqaffinity=2' a GRUB_CMDLINE_LINUX"
        fi
    else
        warn "IRQ 126 non trovato o non accessibile"
    fi
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

# Funzione per preparare il sistema
prepare_system() {
    if systemctl is-active --quiet irqbalance; then
        log "Disattivazione permanente irqbalance per sbloccare gli IRQ..."
        systemctl stop irqbalance
        systemctl mask irqbalance
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
    
    # Hardware check finale
    final_hardware_check
    
    log "Configurazione hardware e IRQ pinning completata"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi