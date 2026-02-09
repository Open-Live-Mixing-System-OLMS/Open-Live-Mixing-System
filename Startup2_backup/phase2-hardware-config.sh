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

# Rilevamento hardware audio - VERSIONE DINAMICA CON CONTROLLO USB
detect_audio_hardware() {
    log "Rilevamento hardware audio (approccio dinamico)..."
    local audio_irqs=()
    local usb_devices=()
    
    # Pattern specifici per evitare falsi positivi
    local patterns="snd|audio|sound|hda|xhci_hcd|ehci_hcd"
    
    # Raccogli tutti i risultati prima di elaborarli
    local irq_results=$(grep -iE "$patterns" /proc/interrupts | awk -F: '{print $1}' | tr -d ' ')
    local usb_results=$(grep -iE "xhci_hcd|ehci_hcd" /proc/interrupts | wc -l)
    
    # Controlla se ci sono troppi dispositivi USB
    if [[ $usb_results -gt 3 ]]; then
        warn "Troppi dispositivi USB rilevati sullo stesso bus ($usb_results dispositivi)"
        warn "Questo può causare blocchi durante l'IRQ pinning"
        warn "SUGGERIMENTO: Scollegare HD esterni o altri dispositivi USB non essenziali"
        warn "ESEGUIRE: sudo /home/francesco_ssh/Progetti/OLMS-Core/Startup2/olms-orchestrator.sh dopo aver scollegato i dispositivi"
        exit 1
    fi
    
    # Elabora i risultati in modo sicuro
    while read -r irq; do
        if [[ -n "$irq" ]]; then
            audio_irqs+=("$irq")
            log "IRQ $irq identificato per ottimizzazione."
        fi
    done <<< "$irq_results"
    
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

# Funzione per rilevare i controlli di volume disponibili su una scheda audio
detect_volume_controls() {
    local card_index=$1
    local controls=()
    
    log "Rilevamento controlli di volume disponibili per scheda $card_index..."
    
    # Ottieni tutti i controlli disponibili per la scheda
    local all_controls=$(amixer -c "$card_index" controls 2>/dev/null | grep -E "numid=[0-9]+" || true)
    
    if [[ -z "$all_controls" ]]; then
        log "Nessun controllo trovato per la scheda $card_index"
        return 1
    fi
    
    # Filtra i controlli che sono probabilmente controlli di volume
    while IFS= read -r control; do
        local numid=$(echo "$control" | grep -o "numid=[0-9]*" | cut -d'=' -f2)
        local control_name=$(amixer -c "$card_index" cget numid="$numid" 2>/dev/null | grep -o "name='[^']*'" | head -1 | tr -d "'" || true)
        
        if [[ -n "$control_name" ]]; then
            # Controlli di volume comuni
            if echo "$control_name" | grep -iqE "volume|pcm|master|capture|playback|headphone|speaker"; then
                controls+=("$numid:$control_name")
                log "Controllo volume trovato: numid=$numid, name='$control_name'"
            fi
        fi
    done <<< "$all_controls"
    
    if [[ ${#controls[@]} -eq 0 ]]; then
        log "Nessun controllo di volume specifico trovato, provo con nomi generici..."
        
        # Prova con nomi generici di controllo volume
        local generic_controls=("PCM" "Master" "Capture" "Playback" "Headphone" "Speaker")
        for control_name in "${generic_controls[@]}"; do
            if amixer -c "$card_index" sget "$control_name" >/dev/null 2>&1; then
                controls+=("generic:$control_name")
                log "Controllo volume generico trovato: $control_name"
            fi
        done
    fi
    
    if [[ ${#controls[@]} -eq 0 ]]; then
        log "Nessun controllo di volume trovato sulla scheda $card_index"
        return 1
    fi
    
    # Restituisce i controlli trovati
    printf '%s\n' "${controls[@]}"
    return 0
}

# Funzione per ottenere il range massimo di un controllo volume
get_volume_range() {
    local card_index=$1
    local numid=$2
    local max_value=""
    
    # Estrai il range massimo dal controllo
    max_value=$(amixer -c "$card_index" cget numid="$numid" 2>/dev/null | grep -o "max=[0-9]*" | cut -d'=' -f2)
    
    # Verifica che max_value sia un numero valido
    if [[ -n "$max_value" ]] && [[ "$max_value" =~ ^[0-9]+$ ]]; then
        echo "$max_value"
    else
        # Fallback a valori standard
        echo "128"
    fi
}

# Funzione per applicare la configurazione dei volumi in modo sicuro
apply_volume_settings() {
    local card_index=$1
    shift
    local controls=("$@")
    local success=false
    local critical_controls=("PCM" "Master" "Playback" "Headphone")
    
    log "Applicazione configurazione volumi sicura per scheda $card_index..."
    
    # Prima prova con i controlli critici (massimo 3 controlli)
    local critical_found=0
    for control in "${controls[@]}"; do
        local numid=$(echo "$control" | cut -d':' -f1)
        local control_name=$(echo "$control" | cut -d':' -f2-)
        
        # Limita a massimo 3 controlli critici per evitare overload
        if [[ $critical_found -ge 3 ]]; then
            log "⚠️ Limite controlli critici raggiunto (3), saltando ulteriori modifiche"
            break
        fi
        
        # Controlla se è un controllo critico
        local is_critical=false
        for critical in "${critical_controls[@]}"; do
            if [[ "$control_name" == *"$critical"* ]]; then
                is_critical=true
                break
            fi
        done
        
        if [[ "$is_critical" == "true" ]] || [[ "$numid" == "generic" ]]; then
            critical_found=$((critical_found + 1))
            
            # Metodo 1: Prova con il nome del controllo (se non è un numid numerico)
            if [[ "$numid" == "generic" ]]; then
                # Imposta volume al 70% per evitare overload
                if amixer -c "$card_index" sset "$control_name" 70% unmute >/dev/null 2>&1; then
                    log "✅ Volume impostato per controllo critico: $control_name (70%)"
                    success=true
                fi
            # Metodo 2: Prova con il numid specifico (con controllo range)
            elif [[ "$numid" =~ ^[0-9]+$ ]]; then
                local max_range=$(get_volume_range "$card_index" "$numid")
                local safe_value=$((max_range * 70 / 100))
                
                # Imposta volume al 70% del range massimo
                if amixer -c "$card_index" cset numid="$numid" "$safe_value" >/dev/null 2>&1; then
                    log "✅ Volume impostato per numid=$numid (valore sicuro: $safe_value su $max_range)"
                    success=true
                # Fallback a valore medio se il 70% non funziona
                elif amixer -c "$card_index" cset numid="$numid" $((max_range / 2)) >/dev/null 2>&1; then
                    log "✅ Volume impostato per numid=$numid (valore medio: $((max_range / 2)))"
                    success=true
                # Metodo 3: Prova con unmute
                elif amixer -c "$card_index" cset numid="$numid" on >/dev/null 2>&1; then
                    log "✅ Controllo abilitato per numid=$numid"
                    success=true
                fi
            fi
        fi
    done
    
    # Se non abbiamo trovato controlli critici, prova con i primi 2 controlli generici
    if [[ "$success" == "false" ]] && [[ ${#controls[@]} -gt 0 ]]; then
        log "⚠️ Nessun controllo critico trovato, provo con i primi 2 controlli generici..."
        
        local generic_count=0
        for control in "${controls[@]}"; do
            if [[ $generic_count -ge 2 ]]; then
                break
            fi
            
            local numid=$(echo "$control" | cut -d':' -f1)
            local control_name=$(echo "$control" | cut -d':' -f2-)
            
            if [[ "$numid" == "generic" ]]; then
                if amixer -c "$card_index" sset "$control_name" 50% unmute >/dev/null 2>&1; then
                    log "✅ Volume impostato per controllo generico: $control_name (50%)"
                    success=true
                    generic_count=$((generic_count + 1))
                fi
            elif [[ "$numid" =~ ^[0-9]+$ ]]; then
                local max_range=$(get_volume_range "$card_index" "$numid")
                local safe_value=$((max_range * 50 / 100))
                
                if amixer -c "$card_index" cset numid="$numid" "$safe_value" >/dev/null 2>&1; then
                    log "✅ Volume impostato per numid=$numid (valore sicuro: $safe_value su $max_range)"
                    success=true
                    generic_count=$((generic_count + 1))
                fi
            fi
        done
    fi
    
    if [[ "$success" == "false" ]]; then
        log "⚠️ Impossibile configurare i volumi automaticamente"
        log "Suggerimento: verificare i controlli disponibili con 'amixer -c $card_index controls'"
        return 1
    else
        log "✅ Configurazione volumi sicura completata correttamente"
        return 0
    fi
}


# Funzione principale per la configurazione universale dei volumi hardware
fix_hardware_volumes() {
    log "Configurazione volumi hardware universale per schede UAC..."
    
    # Trova la scheda audio UAC (stesso approccio della Fase 3)
    local uac_card=""
    
    # Cerchiamo la scheda UAC usando lo stesso metodo della Fase 3
    for card_path in /sys/class/sound/card*; do
        [ -e "$card_path" ] || continue
        CARD_ID=$(basename "$card_path" | sed 's/card//')
        
        # Verifica se la scheda è USB controllando il percorso del dispositivo fisico
        if readlink "$card_path/device" 2>/dev/null | grep -q "usb"; then
            CARD_NAME=$(cat "$card_path/id" 2>/dev/null || echo "Unknown")
            log "✅ Dispositivo UAC Hardware rilevato: card $CARD_ID ($CARD_NAME)"
            uac_card="$CARD_ID"
            break
        fi
    done
    
    # Se non troviamo dispositivi UAC via kernel, proviamo il metodo fallback con aplay
    if [ -z "$uac_card" ]; then
        log "⚠️ Nessun dispositivo UAC trovato via kernel, fallback a rilevamento ALSA..."
        
        # Cerchiamo qualsiasi scheda USB (contiene "USB" nel nome)
        uac_card=$(aplay -l | grep -i "USB" | grep -E "card [0-9]+:" | head -n1 | cut -d' ' -f2 | tr -d ':')
        
        if [ -n "$uac_card" ]; then
            log "✅ Scheda USB generica trovata: card $uac_card"
        fi
    fi
    
    # Se non troviamo schede USB, non procediamo con la configurazione volumi
    if [ -z "$uac_card" ]; then
        log "⚠️ Nessuna scheda USB UAC trovata, saltando configurazione volumi"
        log "   Possibili cause:"
        log "   - La scheda audio non è Class Compliant (richiede driver proprietari)"
        log "   - La scheda non è collegata correttamente"
        log "   - La scheda è disattivata nei permessi USB"
        log "   - La scheda non supporta lo standard UAC"
        return 0
    fi
    
    log "Configurazione volumi per scheda UAC: card $uac_card"
    
    # Aggiungiamo un controllo di disponibilità prima di procedere
    if ! amixer -c "$uac_card" info >/dev/null 2>&1; then
        log "⚠️ Scheda rilevata ma non ancora pronta per ALSA. Attendo..."
        sleep 2
    fi
    
    # Rileva i controlli di volume disponibili
    local volume_controls=($(detect_volume_controls "$uac_card"))
    
    if [[ ${#volume_controls[@]} -eq 0 ]]; then
        log "⚠️ Nessun controllo di volume trovato sulla scheda $uac_card"
        log "Saltando configurazione volumi (non è un errore critico)"
        return 0
    fi
    
    # Applica la configurazione dei volumi
    if apply_volume_settings "$uac_card" "${volume_controls[@]}"; then
        log "✅ Configurazione volumi hardware completata con successo"
        return 0
    else
        log "⚠️ Configurazione volumi non riuscita, ma non è critico per l'avvio"
        log "   La scheda audio dovrebbe comunque funzionare"
        return 0
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