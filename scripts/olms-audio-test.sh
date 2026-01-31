# Copyright (C) 2024 Francesco Nano and AI
# 
# This file is part of the Open Live Mixing System (OLMS) project.
# Created by Francesco Nano with AI assistance at https://openlivemixingsystem.org/
#
# Connect, collaborate, and stay updated with announcements at:
# https://openlivemixingsystem.org/
#
# Licensed under the GNU General Public License v3.0 (GPL-3.0)
# See LICENSE file for full license terms and conditions.
#
# This software is provided 'as-is', without any express or implied warranty.
# In no event will the authors be held liable for any damages arising from
# the use of this software.

#!/bin/bash

# OLMS Audio Engine Test Script
# 
# Questo script testa le funzionalità problematiche del ciclo di startup OLMS
# in modo isolato e controllato per identificare i punti di fallimento.
# 
# Basato sull'analisi dei problemi JACK/Ardour nel sistema OLMS.
# 
# Modalità di test:
# --cleanup-only     Testa solo il cleanup
# --jack-only        Testa solo JACK startup
# --ardour-only      Testa solo Ardour startup  
# --full-test        Testa l'intero ciclo
# --debug            Modalità debug con output dettagliato
# --help, -h         Mostra l'aiuto

set -e

# Configurazione
SCRIPT_NAME="OLMS Audio Engine Test"
SCRIPT_VERSION="1.0"
DEBUG_MODE=false
TEST_MODE="full"
JACK_SAMPLE_RATE=${JACK_SAMPLE_RATE:-48000}
JACK_PERIOD_SIZE=${JACK_PERIOD_SIZE:-64}
JACK_STABILITY_TIMEOUT=30
MAX_JACK_ATTEMPTS=10

# Variabili di stato
CLEANUP_SUCCESS=false
JACK_START_SUCCESS=false
JACK_STABILITY_SUCCESS=false
ARDUOR_START_SUCCESS=false
JACK_PID=""
ARDUOR_PID=""

# Funzioni di logging
print_status() {
    echo "[$(date '+%H:%M:%S')] $1" >&2
}

print_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "[$(date '+%H:%M:%S')] DEBUG: $1" >&2
    fi
}

print_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

print_success() {
    echo "[$(date '+%H:%M:%S')] SUCCESS: $1" >&2
}

print_warning() {
    echo "[$(date '+%H:%M:%S')] WARNING: $1" >&2
}

# Funzione per mostrare l'aiuto
show_help() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo ""
    echo "Questo script testa le funzionalità problematiche del ciclo di startup OLMS"
    echo "in modo isolato e controllato per identificare i punti di fallimento."
    echo ""
    echo "Uso: $0 [OPZIONI]"
    echo ""
    echo "OPZIONI:"
    echo "  --cleanup-only     Testa solo il cleanup (fase 0)"
    echo "  --jack-only        Testa solo JACK startup (fase 3)"
    echo "  --ardour-only      Testa solo Ardour startup (fase 4)"
    echo "  --full-test        Testa l'intero ciclo (default)"
    echo "  --debug            Modalità debug con output dettagliato"
    echo "  --help, -h         Mostra questo messaggio"
    echo ""
    echo "VARIABILI D'AMBIENTE:"
    echo "  JACK_SAMPLE_RATE     Sample rate per JACK (default: 48000)"
    echo "  JACK_PERIOD_SIZE     Period size per JACK (default: 64)"
    echo "  JACK_STABILITY_TIMEOUT Timeout per stabilizzazione JACK (default: 30)"
    echo "  MAX_JACK_ATTEMPTS    Numero massimo di tentativi per JACK (default: 10)"
    echo ""
    echo "ESEMPI:"
    echo "  $0                           # Test completo"
    echo "  $0 --cleanup-only            # Testa solo cleanup"
    echo "  $0 --jack-only --debug       # Testa solo JACK con debug"
    echo "  $0 --full-test --debug       # Test completo con debug"
    echo ""
    echo "CODICI DI RITORNO:"
    echo "  0  - Test completato con successo"
    echo "  1  - Errore generale"
    echo "  2  - Errore nel cleanup"
    echo "  3  - Errore nell'avvio JACK"
    echo "  4  - Errore nella stabilizzazione JACK"
    echo "  5  - Errore nell'avvio Ardour"
    echo "  6  - Errore nella sincronizzazione processi"
}

# Funzione per analizzare i parametri
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup-only)
                TEST_MODE="cleanup"
                shift
                ;;
            --jack-only)
                TEST_MODE="jack"
                shift
                ;;
            --ardour-only)
                TEST_MODE="ardour"
                shift
                ;;
            --full-test)
                TEST_MODE="full"
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Opzione sconosciuta: $1"
                echo "Usa --help per vedere le opzioni disponibili"
                exit 1
                ;;
        esac
    done
}

# Funzione per pulire i processi audio esistenti
force_cleanup_audio_processes() {
    print_status "=== TEST CLEANUP AUDIO PROCESSES ==="
    print_status "Inizio cleanup processi audio esistenti..."
    
    local cleanup_success=true
    
    # 1. Termina processi JACK
    print_debug "Cerco processi JACK in esecuzione..."
    local jack_pids=$(pgrep -f jackd 2>/dev/null)
    if [ -n "$jack_pids" ]; then
        print_status "Trovati processi JACK: $jack_pids"
        print_status "Termino processi JACK..."
        echo "$jack_pids" | xargs -r sudo kill -9 2>/dev/null || true
        sleep 2
        local remaining_jack=$(pgrep -f jackd 2>/dev/null)
        if [ -n "$remaining_jack" ]; then
            print_error "Alcuni processi JACK non sono stati terminati: $remaining_jack"
            cleanup_success=false
        else
            print_success "Processi JACK terminati correttamente"
        fi
    else
        print_status "Nessun processo JACK trovato"
    fi
    
    # 2. Termina processi Ardour
    print_debug "Cerco processi Ardour in esecuzione..."
    local ardour_pids=$(pgrep -f ardour 2>/dev/null)
    if [ -n "$ardour_pids" ]; then
        print_status "Trovati processi Ardour: $ardour_pids"
        print_status "Termino processi Ardour..."
        echo "$ardour_pids" | xargs -r kill -9 2>/dev/null || true
        sleep 2
        local remaining_ardour=$(pgrep -f ardour 2>/dev/null)
        if [ -n "$remaining_ardour" ]; then
            print_error "Alcuni processi Ardour non sono stati terminati: $remaining_ardour"
            cleanup_success=false
        else
            print_success "Processi Ardour terminati correttamente"
        fi
    else
        print_status "Nessun processo Ardour trovato"
    fi
    
    # 3. Termina processi Pipewire
    print_debug "Cerco processi Pipewire in esecuzione..."
    local pipewire_pids=$(pgrep -f pipewire 2>/dev/null)
    if [ -n "$pipewire_pids" ]; then
        print_status "Trovati processi Pipewire: $pipewire_pids"
        print_status "Termino processi Pipewire..."
        echo "$pipewire_pids" | xargs -r sudo kill -9 2>/dev/null || true
        sleep 2
        local remaining_pipewire=$(pgrep -f pipewire 2>/dev/null)
        if [ -n "$remaining_pipewire" ]; then
            print_error "Alcuni processi Pipewire non sono stati terminati: $remaining_pipewire"
            cleanup_success=false
        else
            print_success "Processi Pipewire terminati correttamente"
        fi
    else
        print_status "Nessun processo Pipewire trovato"
    fi
    
    # 4. Rimuovi socket JACK
    print_debug "Rimuovo socket JACK..."
    local socket_files="/tmp/jack_* /dev/shm/jack_* /var/run/jack_* /run/jack_* /tmp/.jack* /var/lock/.jack*"
    for socket_file in $socket_files; do
        if [ -f "$socket_file" ]; then
            print_debug "Rimuovo socket: $socket_file"
            sudo rm -f "$socket_file" 2>/dev/null || true
        fi
    done
    print_success "Socket JACK rimossi"
    
    # 5. Rimuovi socket Pipewire
    print_debug "Rimuovo socket Pipewire..."
    local pipewire_socket_files="/tmp/pipewire* /dev/shm/pipewire* /var/run/pipewire* /run/pipewire* /tmp/.pipewire* /var/lock/.pipewire*"
    for socket_file in $pipewire_socket_files; do
        if [ -f "$socket_file" ]; then
            print_debug "Rimuovo socket: $socket_file"
            sudo rm -f "$socket_file" 2>/dev/null || true
        fi
    done
    print_success "Socket Pipewire rimossi"
    
    # 6. Pulisci memoria condivisa
    print_debug "Pulisco memoria condivisa..."
    for shm_id in $(ipcs -m | grep jack | awk '{print $2}' 2>/dev/null); do
        if [ -n "$shm_id" ]; then
            print_debug "Rimuovo shared memory ID: $shm_id"
            sudo ipcrm -m "$shm_id" 2>/dev/null || true
        fi
    done
    for sem_id in $(ipcs -s | grep jack | awk '{print $2}' 2>/dev/null); do
        if [ -n "$sem_id" ]; then
            print_debug "Rimuovo semaphore ID: $sem_id"
            sudo ipcrm -s "$sem_id" 2>/dev/null || true
        fi
    done
    print_success "Memoria condivisa pulita"
    
    # 7. Verifica cleanup
    print_debug "Verifico stato finale cleanup..."
    local remaining_processes=$(pgrep -f "jackd|pipewire|ardour" 2>/dev/null | wc -l)
    if [ "$remaining_processes" -eq 0 ]; then
        print_success "Cleanup completato con successo - nessun processo audio residuo"
        CLEANUP_SUCCESS=true
        return 0
    else
        print_error "Cleanup fallito - processi audio residui: $remaining_processes"
        print_error "Processi residui:"
        pgrep -f "jackd|pipewire|ardour" 2>/dev/null | while read pid; do
            ps -p "$pid" -o pid,cmd 2>/dev/null | tail -n 1
        done
        CLEANUP_SUCCESS=false
        return 1
    fi
}

# Funzione per rilevare il dispositivo audio USB
detect_usb_audio_device() {
    print_status "=== TEST USB AUDIO DEVICE DETECTION ===" >&2
    print_status "Rilevo dispositivo audio USB..." >&2
    
    # Metodo 1: Rilevamento tramite /proc/asound/cards
    print_debug "Metodo 1: Controllo /proc/asound/cards..." >&2
    local usb_cards=$(grep -i "usb.*audio\|audio.*usb" /proc/asound/cards 2>/dev/null | grep -E "^[0-9]+" | awk '{print $1}' | head -1)
    
    if [ -n "$usb_cards" ]; then
        local detected_device="hw:$usb_cards,0"
        print_success "Dispositivo USB rilevato tramite /proc/asound/cards: $detected_device" >&2
        echo "$detected_device"
        return 0
    fi
    
    # Metodo 2: Rilevamento tramite aplay -l
    print_debug "Metodo 2: Controllo aplay -l..." >&2
    local usb_devices=$(aplay -l 2>/dev/null | grep -i "usb.*audio\|audio.*usb" | grep -E "card [0-9]+:" | head -1 | sed 's/.*card \([0-9]*\):.*/\1/')
    
    if [ -n "$usb_devices" ]; then
        local detected_device="hw:$usb_devices,0"
        print_success "Dispositivo USB rilevato tramite aplay -l: $detected_device" >&2
        echo "$detected_device"
        return 0
    fi
    
    # Metodo 3: Rilevamento tramite arecord -l
    print_debug "Metodo 3: Controllo arecord -l..." >&2
    local usb_capture_devices=$(arecord -l 2>/dev/null | grep -i "usb.*audio\|audio.*usb" | grep -E "card [0-9]+:" | head -1 | sed 's/.*card \([0-9]*\):.*/\1/')
    
    if [ -n "$usb_capture_devices" ]; then
        local detected_device="hw:$usb_capture_devices,0"
        print_success "Dispositivo USB rilevato tramite arecord -l: $detected_device" >&2
        echo "$detected_device"
        return 0
    fi
    
    # Metodo 4: Rilevamento tramite lsusb
    print_debug "Metodo 4: Controllo lsusb..." >&2
    if command -v lsusb >/dev/null 2>&1; then
        local audio_usb_devices=$(lsusb 2>/dev/null | grep -i "audio" | head -1)
        if [ -n "$audio_usb_devices" ]; then
            print_warning "Dispositivo audio USB rilevato via lsusb ma non configurato in ALSA" >&2
            print_debug "Dispositivo: $audio_usb_devices" >&2
        fi
    fi
    
    print_warning "Nessun dispositivo audio USB rilevato, utilizzerò backend dummy" >&2
    echo "dummy"
    return 1
}

# Funzione per avviare JACK
start_jack_test() {
    local backend="$1"
    local jack_cmd=""
    
    print_status "=== TEST JACK STARTUP ==="
    print_status "Avvio JACK con backend: $backend"
    
    # Verifica cleanup preliminare
    if ! force_cleanup_audio_processes; then
        print_error "Cleanup preliminare fallito, impossibile avviare JACK"
        return 1
    fi
    
    # Attendi ulteriore cleanup
    print_status "Attendo 3 secondi per cleanup completo..."
    sleep 3
    
    case "$backend" in
        "dummy")
            print_status "Configuro JACK con backend dummy (audio virtuale)..."
            # Backend dummy non supporta -n, usa solo opzioni supportate
            local audio_cores="2-$(($(nproc)-1))"
            jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d dummy -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -C 2 -P 2"
            ;;
        "alsa")
            print_status "Configuro JACK con backend ALSA (USB Audio)..."
            # Rileva dispositivo USB
            local usb_device=$(detect_usb_audio_device)
            if [ "$usb_device" != "dummy" ]; then
                # Parametri JACK ottimizzati
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 3 -d $usb_device"
                print_status "Dispositivo USB rilevato: $usb_device"
                print_status "Parametri JACK: -R (realtime), -n 3 (periodi), -p $JACK_PERIOD_SIZE (buffer)"
                print_status "Core audio: $audio_cores"
            else
                # Fallback a primo dispositivo ALSA disponibile
                local audio_cores="2-$(($(nproc)-1))"
                jack_cmd="taskset -c $audio_cores chrt -f 80 jackd -R -d alsa -r$JACK_SAMPLE_RATE -p$JACK_PERIOD_SIZE -n 3"
                print_status "Nessun dispositivo USB rilevato, uso ALSA default"
                print_status "Parametri JACK: -R (realtime), -n 3 (periodi), -p $JACK_PERIOD_SIZE (buffer)"
                print_status "Core audio: $audio_cores"
            fi
            ;;
        *)
            print_error "Backend JACK sconosciuto: $backend"
            return 1
            ;;
    esac
    
    print_status "Comando JACK: $jack_cmd"
    
    # Avvia JACK in background
    eval $jack_cmd &
    JACK_PID=$!
    
    # Attendi avvio JACK
    print_status "Attendo avvio JACK (PID: $JACK_PID)..."
    sleep 3
    
    # Verifica se JACK è in esecuzione
    if kill -0 $JACK_PID 2>/dev/null; then
        print_success "JACK avviato correttamente (PID: $JACK_PID)"
        JACK_START_SUCCESS=true
        return 0
    else
        print_error "JACK non è stato avviato correttamente"
        return 1
    fi
}

# Funzione per verificare la stabilità di JACK
verify_jack_stability_test() {
    print_status "=== TEST JACK STABILITY VERIFICATION ==="
    print_status "Verifico stabilità JACK..."
    
    if [ -z "$JACK_PID" ]; then
        print_error "Nessun processo JACK attivo da verificare"
        return 1
    fi
    
    if ! kill -0 $JACK_PID 2>/dev/null; then
        print_error "Processo JACK non attivo (PID: $JACK_PID)"
        return 1
    fi
    
    # Attendi ulteriore inizializzazione
    print_status "Attendo inizializzazione completa JACK..."
    sleep 5
    
    local attempt=1
    local jack_ready=false
    
    while [ $attempt -le $MAX_JACK_ATTEMPTS ] && [ "$jack_ready" = false ]; do
        print_status "Verifica stabilità JACK (tentativo $attempt/$MAX_JACK_ATTEMPTS)..."
        
        # Test 1: Verifica connettività jack_lsp
        print_debug "Test 1: Verifica jack_lsp..."
        if ! timeout 3 jack_lsp >/dev/null 2>&1; then
            print_status "  JACK non risponde a jack_lsp, attendo 3 secondi..."
            sleep 3
            attempt=$((attempt + 1))
            continue
        fi
        
        # Test 2: Verifica stato jack_control (commentato per evitare conflitti D-Bus)
        # print_debug "Test 2: Verifica jack_control status..."
        # if ! timeout 3 jack_control status >/dev/null 2>&1; then
        #     print_status "  JACK control non pronto, attendo 3 secondi..."
        #     sleep 3
        #     attempt=$((attempt + 1))
        #     continue
        # fi
        
        # Test 3: Verifica configurazione buffer
        print_debug "Test 3: Verifica jack_bufsize..."
        if ! timeout 3 jack_bufsize >/dev/null 2>&1; then
            print_status "  Buffer JACK non configurato, attendo 3 secondi..."
            sleep 3
            attempt=$((attempt + 1))
            continue
        fi
        
        # Test 4: Verifica porte attive
        print_debug "Test 4: Verifica porte JACK..."
        local port_count=$(timeout 3 jack_lsp 2>/dev/null | wc -l || echo "0")
        if [ "$port_count" -lt 2 ]; then
            print_status "  Porte JACK non completamente inizializzate ($port_count porte trovate), attendo 3 secondi..."
            sleep 3
            attempt=$((attempt + 1))
            continue
        fi
        
        # Tutti i test superati
        print_success "JACK stabilità verificata con successo"
        jack_ready=true
        break
    done
    
    if [ "$jack_ready" = true ]; then
        print_success "JACK è completamente operativo e pronto per la connessione Ardour"
        
        # Mostra informazioni di debug
        print_debug "Porte JACK disponibili:"
        jack_lsp 2>/dev/null | head -10 || echo "  Nessuna porta listata"
        
        print_debug "Stato JACK:"
        jack_control status 2>/dev/null | head -5 || echo "  Stato non disponibile"
        
        JACK_STABILITY_SUCCESS=true
        return 0
    else
        print_error "JACK non è riuscito a stabilizzarsi dopo $MAX_JACK_ATTEMPTS tentativi"
        print_error "Questo indica un problema di configurazione JACK o hardware"
        print_error "Controlla: parametri JACK, hardware audio, e risorse di sistema"
        return 1
    fi
}

# Funzione per configurare l'ambiente X11
setup_x11_environment_test() {
    print_status "=== TEST X11 ENVIRONMENT SETUP ==="
    print_status "Configuro ambiente X11 per Ardour GUI..."
    
    # Metodo 1: Usa existing DISPLAY se funzionante
    if [ -n "$DISPLAY" ] && xset -display "$DISPLAY" q >/dev/null 2>&1; then
        print_success "DISPLAY esistente funzionante: $DISPLAY"
        return 0
    fi
    
    # Metodo 2: Ricerca socket X11
    print_debug "Metodo 2: Ricerca socket X11..."
    for display_num in 0 1 2 3 4 5; do
        local socket_path="/tmp/.X11-unix/X$display_num"
        if [ -S "$socket_path" ]; then
            export DISPLAY=":$display_num"
            print_success "Socket X11 rilevato: $DISPLAY (socket: $socket_path)"
            break
        fi
    done
    
    # Metodo 3: Verifica xauth
    if command -v xauth >/dev/null 2>&1; then
        print_debug "Metodo 3: Verifica xauth..."
        local auth_entries=$(xauth list 2>/dev/null)
        if [ -n "$auth_entries" ]; then
            local display=$(echo "$auth_entries" | grep -E ":[0-9]+" | grep -v "MIT-MAGIC-COOKIE" | head -1 | awk '{print $1}' | sed 's/.*\(:[0-9]*\)$/\1/')
            if [ -n "$display" ]; then
                export DISPLAY="$display"
                print_success "DISPLAY rilevato da xauth: $DISPLAY"
            fi
        fi
    fi
    
    # Metodo 4: Test display comuni
    if [ -z "$DISPLAY" ]; then
        print_debug "Metodo 4: Test display comuni..."
        for common_display in ":0" ":1" ":2" ":3"; do
            if xset -display "$common_display" q >/dev/null 2>&1; then
                export DISPLAY="$common_display"
                print_success "DISPLAY funzionante trovato: $DISPLAY"
                break
            fi
        done
    fi
    
    # Metodo 5: Setup XAUTHORITY
    if [ -z "$XAUTHORITY" ]; then
        local possible_xauth="$HOME/.Xauthority"
        if [ -f "$possible_xauth" ]; then
            export XAUTHORITY="$possible_xauth"
            print_success "XAUTHORITY impostato: $XAUTHORITY"
        else
            export XAUTHORITY="$HOME/.Xauthority"
            print_status "XAUTHORITY impostato al default: $XAUTHORITY"
        fi
    fi
    
    # Metodo 6: Setup XDG_RUNTIME_DIR
    if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        print_status "XDG_RUNTIME_DIR impostato: $XDG_RUNTIME_DIR"
    fi
    
    # Verifica finale X11
    if [ -n "$DISPLAY" ]; then
        print_status "Verifica connessione X11 con DISPLAY=$DISPLAY..."
        if timeout 5 xset q >/dev/null 2>&1; then
            print_success "Connessione X11 verificata con successo"
            return 0
        else
            print_error "Connessione X11 fallita per DISPLAY=$DISPLAY"
        fi
    fi
    
    # FALLBACK: Setup Xvfb per modalità headless
    print_status "X11 non disponibile, setup Xvfb per modalità headless..."
    
    if ! command -v Xvfb >/dev/null 2>&1; then
        print_error "Xvfb non installato. Installare con: sudo pacman -S xorg-server-xvfb"
        return 1
    fi
    
    # Trova un display number libero
    local display_num=99
    while [ -f "/tmp/.X${display_num}-lock" ] || [ -S "/tmp/.X11-unix/X${display_num}" ]; do
        display_num=$((display_num + 1))
        if [ $display_num -gt 200 ]; then
            print_error "Impossibile trovare un display number libero"
            return 1
        fi
    done
    
    print_status "Avvio Xvfb su display :$display_num..."
    Xvfb :${display_num} -screen 0 800x600x24 -nolisten tcp -ac +extension GLX -noreset >/dev/null 2>&1 &
    XVFB_PID=$!
    
    sleep 2
    
    if kill -0 $XVFB_PID 2>/dev/null; then
        export DISPLAY=":${display_num}"
        print_success "Xvfb avviato con successo (PID: $XVFB_PID, DISPLAY: :${display_num})"
        print_success "Ambiente X11 virtuale pronto per Ardour"
        return 0
    else
        print_error "Errore nell'avvio di Xvfb"
        return 1
    fi
}

# Funzione per avviare Ardour
start_ardour_test() {
    print_status "=== TEST ARDOUR STARTUP ==="
    print_status "Avvio Ardour come client JACK..."
    
    # Configura ambiente JACK
    export JACK_NO_START_SERVER=1
    export PIPEWIRE_RUNTIME_DIR=/dev/null
    export JACK_NO_AUDIO_RESERVATION=1
    export JACK_SERVER_NAME=default
    export JACK_CONNECT_TIMEOUT=10
    
    print_status "Ambiente JACK configurato:"
    echo "  - JACK_NO_START_SERVER=1 (Ardour come client)"
    echo "  - PIPEWIRE_RUNTIME_DIR=/dev/null (Bypass Pipewire)"
    echo "  - JACK_NO_AUDIO_RESERVATION=1 (Bypass device reservation)"
    
    # Configura ambiente X11 per modalità GUI
    if ! setup_x11_environment_test; then
        print_error "Configurazione X11 fallita, impossibile avviare Ardour in modalità GUI"
        return 1
    fi
    
    # Verifica JACK prima di avviare Ardour
    print_status "Verifica JACK prima dell'avvio Ardour..."
    if ! verify_jack_stability_test; then
        print_error "JACK non stabile, impossibile avviare Ardour"
        return 1
    fi
    
    # Avvia Ardour
    local ardour_cmd="taskset -c 2-$(($(nproc)-1)) chrt -f 75 /usr/bin/ardour8 --no-splash"
    print_status "Avvio Ardour con comando: $ardour_cmd"
    
    $ardour_cmd &
    ARDOUR_PID=$!
    
    # Attendi avvio Ardour
    print_status "Attendo avvio Ardour (PID: $ARDOUR_PID)..."
    sleep 3
    
    # Verifica se Ardour è in esecuzione
    if kill -0 $ARDOUR_PID 2>/dev/null; then
        print_success "Ardour avviato correttamente come client JACK (PID: $ARDOUR_PID)"
        ARDOUR_START_SUCCESS=true
        return 0
    else
        print_error "Ardour non è stato avviato correttamente"
        return 1
    fi
}

# Funzione per testare la sincronizzazione processi
test_process_synchronization() {
    print_status "=== TEST PROCESS SYNCHRONIZATION ==="
    print_status "Testo sincronizzazione tra processi audio..."
    
    # Verifica processi attivi
    local jack_pids=$(pgrep -f jackd 2>/dev/null)
    local ardour_pids=$(pgrep -f ardour 2>/dev/null)
    
    if [ -z "$jack_pids" ] && [ -z "$ardour_pids" ]; then
        print_error "Nessun processo audio attivo"
        return 1
    fi
    
    if [ -n "$jack_pids" ]; then
        print_success "Processi JACK attivi: $jack_pids"
        for pid in $jack_pids; do
            local process_info=$(ps -p "$pid" -o pid,cmd 2>/dev/null | tail -n 1)
            print_debug "  PID $pid: $process_info"
        done
    fi
    
    if [ -n "$ardour_pids" ]; then
        print_success "Processi Ardour attivi: $ardour_pids"
        for pid in $ardour_pids; do
            local process_info=$(ps -p "$pid" -o pid,cmd 2>/dev/null | tail -n 1)
            print_debug "  PID $pid: $process_info"
        done
    fi
    
    # Verifica connessione JACK-Ardour
    print_status "Verifica connessione JACK-Ardour..."
    if jack_lsp 2>/dev/null | grep -q "ardour"; then
        print_success "Ardour connesso correttamente a JACK"
    else
        print_warning "Ardour potrebbe non essere connesso a JACK (connessione potrebbe richiedere più tempo)"
    fi
    
    # Verifica priorità RT
    print_status "Verifica priorità realtime..."
    if [ -n "$jack_pids" ]; then
        for pid in $jack_pids; do
            local rt_info=$(chrt -p "$pid" 2>/dev/null | grep "policy" | awk '{print $3}')
            if [ "$rt_info" = "SCHED_FIFO" ]; then
                print_success "JACK PID $pid ha priorità RT corretta (SCHED_FIFO)"
            else
                print_warning "JACK PID $pid priorità RT non corretta: $rt_info"
            fi
        done
    fi
    
    if [ -n "$ardour_pids" ]; then
        for pid in $ardour_pids; do
            local rt_info=$(chrt -p "$pid" 2>/dev/null | grep "policy" | awk '{print $3}')
            if [ "$rt_info" = "SCHED_FIFO" ]; then
                print_success "Ardour PID $pid ha priorità RT corretta (SCHED_FIFO)"
            else
                print_warning "Ardour PID $pid priorità RT non corretta: $rt_info"
            fi
        done
    fi
    
    print_success "Sincronizzazione processi completata"
    return 0
}

# Funzione per mostrare il riepilogo test
show_test_summary() {
    print_status "=== TEST SUMMARY ==="
    echo ""
    echo "Risultati test:"
    echo "  - Cleanup audio processes: $([ "$CLEANUP_SUCCESS" = true ] && echo "✓ SUCCESS" || echo "✗ FAILED")"
    echo "  - JACK startup: $([ "$JACK_START_SUCCESS" = true ] && echo "✓ SUCCESS" || echo "✗ FAILED")"
    echo "  - JACK stability: $([ "$JACK_STABILITY_SUCCESS" = true ] && echo "✓ SUCCESS" || echo "✗ FAILED")"
    echo "  - Ardour startup: $([ "$ARDUOR_START_SUCCESS" = true ] && echo "✓ SUCCESS" || echo "✗ FAILED")"
    echo ""
    
    # Stato processi correnti
    echo "Stato processi correnti:"
    local current_jack=$(pgrep -f jackd 2>/dev/null | wc -l)
    local current_ardour=$(pgrep -f ardour 2>/dev/null | wc -l)
    echo "  - Processi JACK attivi: $current_jack"
    echo "  - Processi Ardour attivi: $current_ardour"
    echo ""
    
    # Comandi utili
    echo "Comandi utili per il debug:"
    echo "  - Stato JACK: jack_control status"
    echo "  - Porte JACK: jack_lsp"
    echo "  - Buffer JACK: jack_bufsize"
    echo "  - Processi audio: pgrep -f 'jackd|ardour'"
    echo "  - Priorità RT: chrt -p [PID]"
    echo ""
    
    # Valutazione complessiva
    if [ "$CLEANUP_SUCCESS" = true ] && [ "$JACK_START_SUCCESS" = true ] && [ "$JACK_STABILITY_SUCCESS" = true ] && [ "$ARDUOR_START_SUCCESS" = true ]; then
        print_success "TUTTI I TEST COMPLETATI CON SUCCESSO!"
        print_success "Il sistema audio OLMS è funzionante"
        return 0
    else
        print_error "ALCUNI TEST SONO FALLITI"
        print_error "Controlla i log sopra per identificare i problemi specifici"
        return 1
    fi
}

# Funzione di cleanup finale
cleanup_on_exit() {
    print_status "Pulizia finale..."
    
    # Termina processi test se attivi
    if [ -n "$JACK_PID" ] && kill -0 $JACK_PID 2>/dev/null; then
        print_status "Termino processo JACK (PID: $JACK_PID)..."
        kill $JACK_PID 2>/dev/null || true
        sleep 1
    fi
    
    if [ -n "$ARDUOR_PID" ] && kill -0 $ARDUOR_PID 2>/dev/null; then
        print_status "Termino processo Ardour (PID: $ARDUOR_PID)..."
        kill $ARDUOR_PID 2>/dev/null || true
        sleep 1
    fi
    
    # Cleanup finale
    force_cleanup_audio_processes >/dev/null 2>&1 || true
    
    print_status "Pulizia finale completata"
}

# Funzione principale di test
run_test() {
    case "$TEST_MODE" in
        "cleanup")
            print_status "=== TEST MODE: CLEANUP ONLY ==="
            if force_cleanup_audio_processes; then
                print_success "Test cleanup completato con successo"
                return 0
            else
                print_error "Test cleanup fallito"
                return 2
            fi
            ;;
        "jack")
            print_status "=== TEST MODE: JACK ONLY ==="
            if force_cleanup_audio_processes && start_jack_test "alsa" && verify_jack_stability_test; then
                print_success "Test JACK completato con successo"
                return 0
            else
                print_error "Test JACK fallito"
                return 3
            fi
            ;;
        "ardour")
            print_status "=== TEST MODE: ARDOUR ONLY ==="
            if force_cleanup_audio_processes && start_jack_test "alsa" && verify_jack_stability_test && start_ardour_test; then
                print_success "Test Ardour completato con successo"
                return 0
            else
                print_error "Test Ardour fallito"
                return 5
            fi
            ;;
        "full")
            print_status "=== TEST MODE: FULL TEST ==="
            if force_cleanup_audio_processes && start_jack_test "alsa" && verify_jack_stability_test && start_ardour_test && test_process_synchronization; then
                show_test_summary
                print_success "Test completo completato con successo"
                return 0
            else
                show_test_summary
                print_error "Test completo fallito"
                return 1
            fi
            ;;
        *)
            print_error "Modalità test sconosciuta: $TEST_MODE"
            return 1
            ;;
    esac
}

# Funzione principale
main() {
    print_status "=== $SCRIPT_NAME v$SCRIPT_VERSION ==="
    print_status "Inizio test funzionalità audio OLMS"
    print_status "Modalità: $TEST_MODE"
    print_status "Debug: $([ "$DEBUG_MODE" = true ] && echo "ON" || echo "OFF")"
    echo ""
    
    # Imposta trap per cleanup
    trap cleanup_on_exit EXIT
    
    # Esegui test
    local test_result=0
    run_test
    test_result=$?
    
    # Mostra riepilogo finale se non in modalità specifica
    if [ "$TEST_MODE" = "full" ]; then
        show_test_summary
    fi
    
    # Esci con codice appropriato
    exit $test_result
}

# Esegui script
main "$@"