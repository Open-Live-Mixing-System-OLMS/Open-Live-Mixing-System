#!/bin/bash

# Fase 5: Ardour DAW Startup
# Versione: 2.0

set -euo pipefail

# Configurazione
LOG_FILE="/tmp/olms-orchestrator.log"
ARDOUR_LOG_FILE="/tmp/ardour_startup.log"
ARDOUR_SESSION_FILE=""
ARDOUR_PID_FILE="/tmp/ardour.pid"

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

# Preparazione ambiente JACK
prepare_jack_environment() {
    log "Preparazione ambiente JACK per Ardour..."
    
    # Imposta variabili criticali
    export JACK_NO_START_SERVER=1
    export PIPEWIRE_RUNTIME_DIR=/dev/null
    export JACK_NO_AUDIO_RESERVATION=1
    
    log "Variabili JACK impostate:"
    log "  JACK_NO_START_SERVER=$JACK_NO_START_SERVER"
    log "  PIPEWIRE_RUNTIME_DIR=$PIPEWIRE_RUNTIME_DIR"
    log "  JACK_NO_AUDIO_RESERVATION=$JACK_NO_AUDIO_RESERVATION"
    
    # Verifica JACK server running
    if command -v jack_control >/dev/null 2>&1; then
        local jack_status=$(jack_control status 2>/dev/null || echo "unknown")
        if echo "$jack_status" | grep -q "running"; then
            log "JACK server running (verificato con jack_control)"
        else
            warn "JACK server non in esecuzione (jack_control: $jack_status)"
        fi
    fi
    
    # Verifica PID JACK
    local jack_pid=$(cat /tmp/jack.pid 2>/dev/null || echo "")
    if [[ -n "$jack_pid" ]] && kill -0 "$jack_pid" 2>/dev/null; then
        log "JACK PID attivo: $jack_pid"
    else
        warn "JACK PID non attivo o non trovato"
    fi
}

# Identificazione utente e gestione privilegi
identify_user_and_privileges() {
    log "Identificazione utente e gestione privilegi..."
    
    # Root detection
    if [[ "$EUID" -eq 0 ]]; then
        log "Esecuzione come root rilevata"
        
        # Identifica utente originale
        local original_user="${SUDO_USER:-$USER}"
        if [[ -z "$original_user" ]] || [[ "$original_user" == "root" ]]; then
            original_user="francesco_ssh"  # Default user
        fi
        
        log "Utente originale: $original_user"
        
        # Verifica esistenza utente
        if id "$original_user" >/dev/null 2>&1; then
            log "Utente $original_user esistente"
        else
            warn "Utente $original_user non esistente, uso root"
            original_user="root"
        fi
        
        export TARGET_USER="$original_user"
    else
        log "Esecuzione come utente normale: $USER"
        export TARGET_USER="$USER"
    fi
    
    # Verifica appartenenza gruppi realtime
    if groups "$TARGET_USER" 2>/dev/null | grep -q "realtime\|audio"; then
        log "Utente $TARGET_USER appartiene ai gruppi realtime/audio"
    else
        warn "Utente $TARGET_USER NON appartiene ai gruppi realtime/audio"
    fi
}

# Rilevamento sessione Ardour
detect_ardour_session() {
    log "Rilevamento sessione Ardour..."
    
    # Path specifica per OLMS
    local olms_base="/home/${TARGET_USER:-$USER}/Progetti/OLMS-Core/engine/session-template/OLMS-POC"
    local olms_file="$olms_base/OLMS-POC.ardour"

    if [[ -f "$olms_file" ]]; then
        ARDOUR_SESSION_FILE="$olms_file"
        log "Sessione OLMS-POC trovata correttamente: $ARDOUR_SESSION_FILE"
        return 0
    else
        warn "File sessione $olms_file non trovato. Cerco fallback..."
        
        # Fallback: cerca in altre directory
        local session_dirs=(
            "/home/${TARGET_USER:-$USER}/.ardour8/sessions"
            "/home/${TARGET_USER:-$USER}/Documents/Ardour/sessions"
            "/home/${TARGET_USER:-$USER}/Music/Ardour/sessions"
            "/home/${TARGET_USER:-$USER}/Ardour/sessions"
            "engine/session-template"
        )
        
        for session_dir in "${session_dirs[@]}"; do
            if [[ -d "$session_dir" ]]; then
                log "Directory sessioni trovata: $session_dir"
                
                # Cerca altri file .ardour nella directory
                local ardour_files=$(find "$session_dir" -name "*.ardour" -type f 2>/dev/null || true)
                if [[ -n "$ardour_files" ]]; then
                    log "File Ardour trovati:"
                    echo "$ardour_files" | while read -r file; do
                        log "  $file"
                    done
                    
                    # Usa il primo file trovato
                    ARDOUR_SESSION_FILE=$(find "$session_dir" -name "*.ardour" -type f | head -1)
                    if [[ -n "$ARDOUR_SESSION_FILE" ]]; then
                        log "Sessione Ardour selezionata: $ARDOUR_SESSION_FILE"
                        return 0
                    fi
                fi
            fi
        done
    fi
    
    warn "Nessuna sessione Ardour trovata"
    return 1
}

# Avvio Ardour con configurazione appropriata
start_ardour() {
    log "Avvio Ardour DAW..."
    
    # Verifica che JACK sia in modalità reale prima di avviare Ardour
    local jack_mode="unknown"
    if [[ -f "/tmp/jack_startup.log" ]]; then
        if grep -q "dummy" "/tmp/jack_startup.log"; then
            jack_mode="dummy"
            warn "JACK è in modalità dummy (virtuale), Ardour potrebbe non funzionare correttamente"
        else
            jack_mode="real"
            log "JACK è in modalità reale"
        fi
    fi
    
    # Determina modalità di avvio
    local launch_mode="test"  # Default
    if [[ -n "${OLMS_MODE:-}" ]]; then
        launch_mode="$OLMS_MODE"
    fi
    
    log "Modalità di lancio: $launch_mode"
    
    # Costruisci comando Ardour - Rilevamento automatico versione
    local ardour_exe=""
    
    # Rilevamento automatico dell'eseguibile Ardour
    if command -v ardour8 >/dev/null 2>&1; then
        ardour_exe="ardour8"
        log "Ardour 8 rilevato: $ardour_exe"
    elif command -v ardour7 >/dev/null 2>&1; then
        ardour_exe="ardour7"
        log "Ardour 7 rilevato: $ardour_exe"
    elif command -v ardour >/dev/null 2>&1; then
        ardour_exe="ardour"
        log "Ardour generico rilevato: $ardour_exe"
    else
        error "Nessun eseguibile Ardour trovato (ardour8, ardour7, ardour)"
        return 1
    fi
    
    local ardour_cmd=()
    
    # Parametri base - Ardour 8 non accetta --jack né --no-gui
    if [[ "$ardour_exe" == "ardour8" ]]; then
        # Ardour 8 si connette automaticamente a JACK, non serve --jack
        # Usa -n per evitare splash screen (equivalente a --no-gui)
        ardour_cmd+=("-n")  # No splash screen
    else
        # Versioni precedenti di Ardour potrebbero aver bisogno di --jack
        ardour_cmd+=("--jack")
        # Per versioni precedenti, --no-gui potrebbe essere disponibile
        if [[ "$ardour_exe" == "ardour7" ]] || [[ "$ardour_exe" == "ardour" ]]; then
            ardour_cmd+=("--no-gui")  # Avvio headless di default
        else
            ardour_cmd+=("-n")  # No splash screen come fallback
        fi
    fi
    
    # Parametri specifici per modalità
    case "$launch_mode" in
        "test")
            if [[ -n "${DISPLAY:-}" ]] && [[ "$DISPLAY" != *":99"* ]] && [[ "$DISPLAY" != *":100"* ]]; then
                # Rimuovi -n per permettere l'apertura della GUI
                log "Modalità test: GUI abilitata (DISPLAY=$DISPLAY)"
                # Non aggiungere -n per permettere l'apertura della finestra
            else
                log "Modalità test: DISPLAY non disponibile, uso headless"
            fi
            ;;
        "prod")
            # Ardour 8 non accetta --no-gui, usa solo -n per no splash screen
            log "Modalità prod: GUI disabilitata"
            ;;
        "virtual")
            # Ardour 8 non accetta --no-gui, usa solo -n per no splash screen
            log "Modalità virtuale: backend dummy"
            ;;
    esac
    
    # Aggiungi sessione se disponibile
    if [[ -n "${ARDOUR_SESSION_FILE:-}" ]] && [[ -f "$ARDOUR_SESSION_FILE" ]]; then
        log "Sessione caricata: $ARDOUR_SESSION_FILE"
    else
        warn "Nessuna sessione specificata, avvio Ardour vuoto"
    fi
    
    # Esegui Ardour con taskset e chrt
    local audio_cores="2-3"
    local ardour_priority="70"  # Priorità leggermente inferiore a JACK (80) per evitare conflitti
    
    # Gestione headless con xvfb-run per VSTFX X connection
    local launcher=""
    if [[ -z "${DISPLAY:-}" ]] || [[ "${DISPLAY:-}" == *":99"* ]] || [[ "${DISPLAY:-}" == *":100"* ]]; then
        if command -v xvfb-run >/dev/null 2>&1; then
            launcher="xvfb-run -a"
            log "Headless mode: uso xvfb-run -a per VSTFX X connection (DISPLAY=${DISPLAY:-})"
        else
            warn "xvfb-run non disponibile, tentativo senza display (potrebbe fallire per VSTFX)"
        fi
    else
        log "GUI mode: DISPLAY disponibile ($DISPLAY)"
    fi
    
    log "Esecuzione: taskset -c $audio_cores chrt -f $ardour_priority $ardour_exe ${ardour_cmd[*]} $ARDOUR_SESSION_FILE"
    
    # Ambiente X11 per utente (se root)
    local env_vars=""
    if [[ "$EUID" -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]]; then
        env_vars="DISPLAY=${DISPLAY:-} XAUTHORITY=${XAUTHORITY:-} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
        log "Ambiente X11 per utente $TARGET_USER: $env_vars"
    fi
    
    # Avvia Ardour
    local ardour_pid=""
    if [[ "$EUID" -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]]; then
        # Root: esegui come utente con ambiente X11
        if [[ -n "$launcher" ]]; then
            (
                export $env_vars
                $launcher taskset -c $audio_cores chrt -f $ardour_priority sudo -u "$TARGET_USER" -E env $env_vars "$ardour_exe" "${ardour_cmd[@]}" "$ARDOUR_SESSION_FILE" 2>&1
            ) | tee -a "$ARDOUR_LOG_FILE" &
        else
            (
                export $env_vars
                taskset -c $audio_cores chrt -f $ardour_priority sudo -u "$TARGET_USER" -E env $env_vars "$ardour_exe" "${ardour_cmd[@]}" "$ARDOUR_SESSION_FILE" 2>&1
            ) | tee -a "$ARDOUR_LOG_FILE" &
        fi
        ardour_pid=$!
    else
        # Utente normale: esegui direttamente
        if [[ -n "$launcher" ]]; then
            (
                $launcher taskset -c $audio_cores chrt -f $ardour_priority "$ardour_exe" "${ardour_cmd[@]}" "$ARDOUR_SESSION_FILE" 2>&1
            ) | tee -a "$ARDOUR_LOG_FILE" &
        else
            (
                taskset -c $audio_cores chrt -f $ardour_priority "$ardour_exe" "${ardour_cmd[@]}" "$ARDOUR_SESSION_FILE" 2>&1
            ) | tee -a "$ARDOUR_LOG_FILE" &
        fi
        ardour_pid=$!
    fi
    
    # Verifica che il processo sia stato avviato correttamente
    if [[ -z "$ardour_pid" ]] || ! kill -0 "$ardour_pid" 2>/dev/null; then
        warn "Ardour non avviato correttamente (PID: $ardour_pid)"
        return 1
    fi
    
    echo "$ardour_pid" > "$ARDOUR_PID_FILE"
    
    log "Ardour avviato con PID: $ardour_pid"
    
    # Attendi avvio con timeout aumentato per sessioni DAW complesse
    local timeout=40  # 40 secondi timeout per Ardour (sessioni complesse)
    local wait_time=0
    local ardour_ready=false
    
    log "Attesa avvio Ardour (timeout: ${timeout}s)..."
    
    while [[ $wait_time -lt $timeout ]]; do
        if kill -0 "$ardour_pid" 2>/dev/null; then
            # Verifica che Ardour sia effettivamente pronto usando jack_lsp
            if command -v jack_lsp >/dev/null 2>&1; then
                local ports=$(jack_lsp 2>/dev/null || true)
                if echo "$ports" | grep -q "ardour"; then
                    log "Ardour è PRONTO (Porte JACK rilevate) dopo ${wait_time}s"
                    ardour_ready=true
                    break
                fi
            fi
            
            # Fallback: verifica PID
            if pgrep -f "ardour.*$ardour_pid" >/dev/null 2>&1; then
                log "Ardour avviato correttamente dopo ${wait_time}s"
                ardour_ready=true
                break
            fi
        else
            # Processo terminato inaspettatamente
            warn "Processo Ardour terminato inaspettatamente (PID: $ardour_pid)"
            break
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
        
        # Messaggi di progresso
        log "Attesa Ardour: ${wait_time}s/${timeout}s..."
    done
    
    # Verifica finale
    if [[ "$ardour_ready" != "true" ]]; then
        warn "Timeout avvio Ardour scaduto dopo ${timeout}s"
        
        # Prova a terminare il processo se è ancora in esecuzione
        if kill -0 "$ardour_pid" 2>/dev/null; then
            warn "Terminazione processo Ardour ($ardour_pid)..."
            kill -TERM "$ardour_pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$ardour_pid" 2>/dev/null || true
        fi
        
        # Fallback: se Ardour non riesce ad avviarsi, prosegui comunque
        warn "Ardour non è riuscito ad avviarsi entro il timeout, ma proseguo con l'orchestrator..."
        return 0  # Ritorna successo per permettere il proseguimento
    fi
}

# Verifica connessione JACK-Ardour
verify_jack_ardour_connection() {
    log "Verifica connessione JACK-Ardour..."
    
    local ardour_pid=$(cat "$ARDOUR_PID_FILE" 2>/dev/null || echo "")
    if [[ -z "$ardour_pid" ]] || ! kill -0 "$ardour_pid" 2>/dev/null; then
        warn "Ardour non attivo"
        return 1
    fi
    
    log "Ardour PID: $ardour_pid"
    
    # Attendi un po' per permettere a JACK di creare i socket
    log "Attesa creazione socket JACK (3 secondi)..."
    sleep 3
    
    # Verifica porte JACK con timeout
    local jack_timeout=10
    local jack_ready=false
    
    for ((i=1; i<=jack_timeout; i++)); do
        if command -v jack_lsp >/dev/null 2>&1; then
            local ports=$(jack_lsp 2>/dev/null || true)
            if echo "$ports" | grep -q "ardour"; then
                log "Porte Ardour trovate dopo ${i}s:"
                echo "$ports" | grep -i ardour | while read -r port; do
                    log "  $port"
                done
                jack_ready=true
                break
            fi
        fi
        if [[ $i -lt $jack_timeout ]]; then
            log "Attesa porte Ardour: ${i}s/${jack_timeout}s..."
            sleep 1
        fi
    done
    
    if [[ "$jack_ready" != "true" ]]; then
        warn "Timeout attesa porte Ardour dopo ${jack_timeout}s"
        warn "Verifica manuale richiesta: eseguire 'jack_lsp' per controllare le porte"
    fi
    
    # Verifica connessioni JACK
    if command -v jack_connect >/dev/null 2>&1; then
        log "Verifica connessioni JACK..."
        # Questo è un controllo base, le connessioni specifiche verranno fatte altrove
    fi
    
    # Verifica processi audio
    local audio_processes=$(pgrep -f "ardour|jack" 2>/dev/null || true)
    if [[ -n "$audio_processes" ]]; then
        log "Processi audio attivi:"
        echo "$audio_processes" | while read -r pid; do
            local proc_info=$(ps -p "$pid" -o pid,cmd --no-headers 2>/dev/null || echo "$pid: unknown")
            log "  $proc_info"
        done
    else
        warn "Nessun processo audio attivo"
    fi
    
    # Verifica socket JACK
    local jack_socket_dirs=("/dev/shm" "/tmp")
    for socket_dir in "${jack_socket_dirs[@]}"; do
        if [[ -d "$socket_dir" ]]; then
            local jack_sockets=$(find "$socket_dir" -name "*jack*" -type s 2>/dev/null || true)
            if [[ -n "$jack_sockets" ]]; then
                log "Socket JACK trovati in $socket_dir:"
                echo "$jack_sockets" | while read -r socket; do
                    log "  $socket"
                done
            fi
        fi
    done
}

# Funzione principale
main() {
    log "=== FASE 5: ARDOUR DAW STARTUP ==="
    
    # Assicura che le variabili X11 siano disponibili per Ardour
    export DISPLAY="${DISPLAY:-:0}"
    export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
    
    log "Variabili X11 impostate per Ardour: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY, XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    
    # Preparazione ambiente
    prepare_jack_environment
    
    # Identificazione utente
    identify_user_and_privileges
    
    # Rilevamento sessione
    detect_ardour_session
    
    # Avvio Ardour
    if ! start_ardour; then
        warn "Avvio Ardour fallito, tentativo senza sessione..."
        ARDOUR_SESSION_FILE=""
        if ! start_ardour; then
            error "Impossibile avviare Ardour"
            return 1
        fi
    fi
    
    # Verifica connessione
    verify_jack_ardour_connection
    
    log "Ardour DAW startup completato"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi