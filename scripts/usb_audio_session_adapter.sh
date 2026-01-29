#!/bin/bash

# USB Audio Session Adapter
# 
# Questo script rileva automaticamente la scheda audio USB collegata,
# analizza la sessione Ardour e la adatta ai nomi specifici delle porte della scheda.

set -e

print_status() {
    echo "[$(date '+%H:%M:%S')] $1" >&2
}

# Funzione per rilevare la scheda audio USB e ottenere i nomi delle porte
detect_usb_audio_ports() {
    print_status "Phase 1: USB Audio Hardware Detection"
    print_status "Scanning for USB audio devices..."
    
    local ports=()
    
    # Rilevamento tramite aplay -l
    print_status "Checking audio playback devices with aplay -l..."
    local usb_cards=$(aplay -l 2>/dev/null | grep -i "usb.*audio\|audio.*usb" | grep -E "card [0-9]+:" | head -1)
    
    if [ -n "$usb_cards" ]; then
        print_status "USB audio card detected in playback list"
        local card_number=$(echo "$usb_cards" | sed 's/.*card \([0-9]*\):.*/\1/')
        local device_name=$(echo "$usb_cards" | sed 's/.*: \([^,]*\).*/\1/')
        
        print_status "Card number: $card_number"
        print_status "Device name: $device_name"
        
        # Otteniamo il nome completo della scheda da arecord -l
        print_status "Getting detailed card information with arecord -l..."
        local full_card_info=$(arecord -l 2>/dev/null | grep "card $card_number:" | head -1)
        if [ -n "$full_card_info" ]; then
            # Estraiamo il nome completo della scheda (es. "USB Audio CODEC")
            local full_device_name=$(echo "$full_card_info" | sed 's/.*\[ *\([^]]*\) *\].*/\1/')
            
            print_status "Full device name: $full_device_name"
            
            # Per una scheda USB a 2 canali, creiamo i nomi delle porte
            # Basandoci sul fatto che abbiamo 2 canali, creiamo solo 2 porte
            ports+=("$full_device_name:capture_1")
            ports+=("$full_device_name:capture_2")
            
            # Stampa i risultati solo alla fine per evitare problemi di parsing
            print_status "✓ USB audio device detection completed successfully"
            print_status "Scheda USB rilevata: $device_name (card $card_number)"
            print_status "Nome completo scheda: $full_device_name"
            
            # Restituiamo le porte usando un separatore specifico per evitare problemi di parsing
            local port_output=""
            for port in "${ports[@]}"; do
                if [ -n "$port" ]; then
                    port_output="${port_output}${port}\n"
                fi
            done
            echo -e "$port_output"
            return 0
        else
            print_status "Warning: Could not get detailed card information"
        fi
    else
        print_status "No USB audio cards found in playback list"
    fi
    
    # Fallback: rilevamento generico
    print_status "Using generic USB audio device fallback..."
    local generic_name="USB Audio Device"
    for i in {1..2}; do
        ports+=("$generic_name:capture_$i")
    done
    
    print_status "Rilevamento dettagliato fallito, uso fallback generico"
    
    # Restituiamo le porte usando un separatore specifico per evitare problemi di parsing
    local port_output=""
    for port in "${ports[@]}"; do
        port_output="${port_output}${port}\n"
    done
    echo -e "$port_output"
    return 0
}

# Funzione per analizzare la sessione Ardour e trovare le connessioni system:capture
analyze_session_connections() {
    local session_file="$1"
    local connections=()
    
    if [ ! -f "$session_file" ]; then
        print_status "Errore: sessione non trovata: $session_file"
        return 1
    fi
    
    # Cerchiamo tutte le connessioni system:capture_X nel file XML
    local capture_connections=$(grep -o 'system:capture_[0-9]*' "$session_file" | sort -u)
    
    if [ -n "$capture_connections" ]; then
        while IFS= read -r conn; do
            connections+=("$conn")
        done <<< "$capture_connections"
        
        print_status "Trovate ${#connections[@]} connessioni system:capture nella sessione"
        echo "${connections[@]}"
        return 0
    else
        print_status "Nessuna connessione system:capture trovata nella sessione"
        return 1
    fi
}


# Funzione per analizzare la sessione Ardour e trovare le connessioni system:playback
analyze_session_playback_connections() {
    local session_file="$1"
    local connections=()
    
    if [ ! -f "$session_file" ]; then
        print_status "Errore: sessione non trovata: $session_file"
        return 1
    fi
    
    # Cerchiamo tutte le connessioni system:playback_X nel file XML
    local playback_connections=$(grep -o 'system:playback_[0-9]*' "$session_file" | sort -u)
    
    if [ -n "$playback_connections" ]; then
        while IFS= read -r conn; do
            connections+=("$conn")
        done <<< "$playback_connections"
        
        print_status "Trovate ${#connections[@]} connessioni system:playback nella sessione"
        echo "${connections[@]}"
        return 0
    else
        print_status "Nessuna connessione system:playback trovata nella sessione"
        return 1
    fi
}

# Funzione per adattare la sessione ai nomi delle porte USB
adapt_session_to_usb_ports() {
    local session_file="$1"
    local usb_ports=("${@:2}")
    local num_usb_ports=${#usb_ports[@]}
    
    print_status "Adattamento sessione per $num_usb_ports porte USB disponibili"
    
    # Analizziamo le connessioni nella sessione
    local session_connections=($(analyze_session_connections "$session_file"))
    local num_connections=${#session_connections[@]}
    
    if [ $num_connections -eq 0 ]; then
        print_status "Nessuna connessione system:capture da adattare trovata"
    else
        # Creiamo un file temporaneo per le modifiche
        local temp_file=$(mktemp)
        cp "$session_file" "$temp_file"
        
        # Mappiamo le connessioni di input
        local mapping_info=""
        
        for conn in "${session_connections[@]}"; do
            # Estraiamo il numero dalla connessione (es. system:capture_1 -> 1)
            local conn_num=$(echo "$conn" | sed 's/system:capture_//')
            
            # Determiniamo quale porta USB usare
            local usb_port_index=0
            
            if [ $num_usb_ports -eq 2 ]; then
                # Logica per schede con solo 2 canali:
                # Tracce dispari -> input 1, tracce pari -> input 2
                if [ $((conn_num % 2)) -eq 1 ]; then
                    usb_port_index=0  # Primo canale (input 1)
                else
                    usb_port_index=1  # Secondo canale (input 2)
                fi
            else
                # Per schede con più canali, mappiamo direttamente
                usb_port_index=$((conn_num - 1))
            fi
            
            # Verifichiamo che l'indice sia valido
            if [ $usb_port_index -lt $num_usb_ports ]; then
                local new_port="${usb_ports[$usb_port_index]}"
                
                # Sostituiamo nella sessione
                sed -i "s/$conn/$new_port/g" "$temp_file"
                
                mapping_info="$mapping_info\n  $conn -> $new_port"
                print_status "Mappato $conn a $new_port"
            else
                print_status "Attenzione: connessione $conn non mappabile (solo $num_usb_ports porte disponibili)"
            fi
        done
        
        # Analizziamo e mappiamo le connessioni di output (playback)
        local playback_connections=($(analyze_session_playback_connections "$session_file"))
        local num_playback_connections=${#playback_connections[@]}
        
        if [ $num_playback_connections -gt 0 ]; then
            # Per le uscite, creiamo i nomi delle porte di playback
            local playback_ports=()
            for i in "${!usb_ports[@]}"; do
                # Sostituiamo "capture" con "playback" nei nomi delle porte
                local playback_port=$(echo "${usb_ports[$i]}" | sed 's/capture/playback/')
                playback_ports+=("$playback_port")
            done
            
            for conn in "${playback_connections[@]}"; do
                # Estraiamo il numero dalla connessione (es. system:playback_1 -> 1)
                local conn_num=$(echo "$conn" | sed 's/system:playback_//')
                
                # Determiniamo quale porta USB usare
                local usb_port_index=0
                
                if [ $num_usb_ports -eq 2 ]; then
                    # Logica per schede con solo 2 canali:
                    # Canale 1 -> output 1, canale 2 -> output 2
                    if [ $conn_num -eq 1 ]; then
                        usb_port_index=0  # Primo canale (output 1)
                    else
                        usb_port_index=1  # Secondo canale (output 2)
                    fi
                else
                    # Per schede con più canali, mappiamo direttamente
                    usb_port_index=$((conn_num - 1))
                fi
                
                # Verifichiamo che l'indice sia valido
                if [ $usb_port_index -lt $num_usb_ports ]; then
                    local new_port="${playback_ports[$usb_port_index]}"
                    
                    # Sostituiamo nella sessione
                    sed -i "s/$conn/$new_port/g" "$temp_file"
                    
                    mapping_info="$mapping_info\n  $conn -> $new_port"
                    print_status "Mappato $conn a $new_port"
                else
                    print_status "Attenzione: connessione $conn non mappabile (solo $num_usb_ports porte disponibili)"
                fi
            done
        fi
        
        # Sostituiamo il file originale con quello modificato
        mv "$temp_file" "$session_file"
        
        print_status "Sessione adattata con successo"
        echo -e "Mappatura effettuata:$mapping_info"
    fi
}

# Funzione principale
main() {
    local session_file="${OLMS_SESSION_PATH:-engine/session-template/OLMS-POC/OLMS-POC.ardour}"
    
    print_status "=== USB Audio Session Adapter ==="
    print_status "Sessione: $session_file"
    
    # Rileviamo le porte USB disponibili
    print_status "Rilevamento porte audio USB..."
    local usb_ports=()
    mapfile -t usb_ports < <(detect_usb_audio_ports)
    local num_ports=${#usb_ports[@]}
    
    if [ $num_ports -eq 0 ]; then
        print_status "Errore: nessuna porta USB rilevata"
        return 1
    fi
    
    print_status "Porte USB rilevate: $num_ports"
    for i in "${!usb_ports[@]}"; do
        print_status "  Porta $((i+1)): ${usb_ports[$i]}"
    done
    
    # Adattiamo la sessione
    adapt_session_to_usb_ports "$session_file" "${usb_ports[@]}"
    
    print_status "=== Adattamento completato ==="
}

# Eseguiamo il main se lo script viene chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi