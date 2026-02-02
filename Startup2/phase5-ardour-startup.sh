
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

# Preparazione ambiente JACK - Enhanced for Fixed-Path Socket Strategy
prepare_jack_environment() {
    log "Preparazione ambiente JACK per Ardour (Fixed-Path Socket Strategy)..."
    
    # FORZA ARDOUR A CERCARE IL SERVER 'olms' (Shared Name Fix)
    export JACK_DEFAULT_SERVER="olms"
    
    # FIXED: Ensure JACK_NO_AUDIO_RESERVATION is properly set for Ardour
    export JACK_NO_AUDIO_RESERVATION=1
    export JACK_NO_START_SERVER=1
    export PIPEWIRE_RUNTIME_DIR=/dev/null
    
    # CRITICAL FIX: This flag tells JACK clients to connect to a server 
    # even if the UID doesn't match the current user.
    export JACK_PROMISCUOUS_SERVER=1 
    
    # Enhanced socket path configuration for UID bridging
    export JACK_SESSION_DIR="/dev/shm/jack-olms-0"
    
    log "Variabili JACK impostate:"
    log "  JACK_DEFAULT_SERVER=$JACK_DEFAULT_SERVER"
    log "  JACK_NO_START_SERVER=$JACK_NO_START_SERVER"
    log "  PIPEWIRE_RUNTIME_DIR=$PIPEWIRE_RUNTIME_DIR"
    log "  JACK_NO_AUDIO_RESERVATION=$JACK_NO_AUDIO_RESERVATION"
    log "  JACK_PROMISCUOUS_SERVER=$JACK_PROMISCUOUS_SERVER"
    log "  JACK_SESSION_DIR=$JACK_SESSION_DIR"
    
    # Enhanced JACK server verification with multiple methods
    log "Verifica stato JACK server..."
    
    # Method 1: Check JACK process
    local jack_pid=$(cat /tmp/jack.pid 2>/dev/null || echo "")
    if [[ -n "$jack_pid" ]] && kill -0 "$jack_pid" 2>/dev/null; then
        log "JACK PID attivo: $jack_pid"
    else
        warn "JACK PID non attivo o non trovato"
    fi
    
    # Method 2: Check JACK control status
    if command -v jack_control >/dev/null 2>&1; then
        local jack_status=$(jack_control status 2>/dev/null || echo "unknown")
        if echo "$jack_status" | grep -q "running"; then
            log "JACK server running (verificato con jack_control)"
        else
            warn "JACK server non in esecuzione (jack_control: $jack_status)"
        fi
    fi
    
    # Method 3: Check socket directory
    local socket_found=false
    for socket_dir in /dev/shm/jack-olms-* /tmp/jack-olms-*; do
        if [[ -d "$socket_dir" ]]; then
            log "Socket JACK trovato: $socket_dir"
            socket_found=true
            break
        fi
    done
    
    if [[ "$socket_found" == "false" ]]; then
        warn "Nessun socket JACK trovato"
    fi
    
    # Enhanced socket path verification and linking
    # This ensures Ardour can find the JACK server regardless of UID
    if [[ "$EUID" -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]]; then
        local user_uid=$(id -u "${TARGET_USER:-francesco_ssh}" 2>/dev/null || echo "1000")
        local target_user="${TARGET_USER:-francesco_ssh}"
        
        # Create comprehensive socket links for all possible paths
        local socket_links=(
            "/dev/shm/jack-olms-${user_uid}"
            "/dev/shm/jack-0/default"
            "/tmp/jack-olms-${user_uid}"
            "/tmp/jack-0/default"
            "/dev/shm/jack-default_${user_uid}_0"
            "/tmp/jack-default_${user_uid}_0"
        )
        
        for link_path in "${socket_links[@]}"; do
            local link_dir=$(dirname "$link_path")
            sudo mkdir -p "$link_dir"
            
            # Find the actual socket directory
            local actual_socket=""
            for socket_dir in /dev/shm/jack-olms-* /tmp/jack-olms-*; do
                if [[ -d "$socket_dir" ]]; then
                    actual_socket="$socket_dir"
                    break
                fi
            done
            
            if [[ -n "$actual_socket" ]] && [[ ! -L "$link_path" ]]; then
                sudo ln -sfn "$actual_socket" "$link_path" 2>/dev/null || true
                log "Link simbolico socket creato: $actual_socket -> $link_path"
            fi
        done
        
        # Enhanced permission patch for UID bridging
        # Use 777 for maximum compatibility (as per the Fixed-Path Socket Strategy)
        sudo chmod -R 777 /dev/shm/jack-* 2>/dev/null || true
        sudo chmod -R 777 /tmp/jack-* 2>/dev/null || true
        sudo chmod 777 /dev/shm/jack-shm-registry 2>/dev/null || true
        log "Permessi socket JACK aggiornati per utente $target_user (UID: $user_uid)"
        log "Socket permissions set to 777 for maximum compatibility"
    fi
    
    # Final connectivity test for Ardour with enhanced verification
    log "Testing JACK connectivity for Ardour..."
    
    # Test with multiple socket paths
    local connectivity_tested=false
    local test_paths=(
        "/dev/shm/jack-olms-0"
        "/dev/shm/jack-olms-1000"
        "/tmp/jack-olms-0"
        "/tmp/jack-olms-1000"
    )
    
    for test_path in "${test_paths[@]}"; do
        if [[ -d "$test_path" ]]; then
            export JACK_SESSION_DIR="$test_path"
            if sudo -E JACK_DEFAULT_SERVER=olms JACK_SESSION_DIR="$test_path" jack_lsp >/dev/null 2>&1; then
                log "✅ JACK connectivity verified for Ardour (path: $test_path)"
                connectivity_tested=true
                break
            fi
        fi
    done
    
    if [[ "$connectivity_tested" == "false" ]]; then
        warn "JACK connectivity test failed - Ardour may not connect properly"
        warn "This could indicate socket permission or path issues"
        warn "Available socket directories:"
        find /dev/shm /tmp -name "*jack*" -type d 2>/dev/null | while read -r dir; do
            warn "  $dir"
        done
    fi
}

# Verifica accesso XAuthority (Suggerimento utente)
verify_xauthority_access() {
    log "Verifica accesso XAuthority per utente $TARGET_USER..."
    
    local xauth_file="/home/${TARGET_USER}/.Xauthority"
    
    # Controlla se il file esiste
    if [[ ! -f "$xauth_file" ]]; then
        warn "File XAuthority non trovato: $xauth_file"
        return 1
    fi
    
    # Controlla i permessi di lettura
    if [[ ! -r "$xauth_file" ]]; then
        warn "File XAuthority non leggibile: $xauth_file"
        warn "Cercando alternative..."
        
        # Prova a trovare altri file .Xauthority
        local alt_xauth=$(find "/home/${TARGET_USER}" -name ".Xauthority*" -type f 2>/dev/null | head -1)
        if [[ -n "$alt_xauth" ]] && [[ -r "$alt_xauth" ]]; then
            export XAUTHORITY="$alt_xauth"
            log "Usando file XAuthority alternativo: $alt_xauth"
            return 0
        fi
        
        # Ultima risorsa: crea un file vuoto (non ideale ma permette il funzionamento)
        warn "Creando file XAuthority vuoto come ultima risorsa..."
        touch "$xauth_file"
        chmod 644 "$xauth_file"
        chown "${TARGET_USER}:${TARGET_USER}" "$xauth_file"
    fi
    
    # Verifica che l'utente possa effettivamente leggere il file
    if sudo -u "$TARGET_USER" cat "$xauth_file" >/dev/null 2>&1; then
        log "XAuthority access verificato: $xauth_file"
        export XAUTHORITY="$xauth_file"
        return 0
    else
        warn "L'utente $TARGET_USER non può leggere il file XAuthority"
        return 1
    fi
}

# Identificazione utente e gestione privilegi
identify_user_and_privileges() {
    log "Identificazione utente e gestione privilegi..."
    
    # Root detection
    if [[ "$EUID" -eq 0 ]]; then
        log "Esecuzione come root rilevata"
        
        # Identifica utente originale con validazione robusta
        local potential_user="${SUDO_USER:-$(id -un 1000 2>/dev/null || echo "")}"
        
        if [[ -n "$potential_user" ]] && getent passwd "$potential_user" >/dev/null; then
            export TARGET_USER="$potential_user"
            log "Target user identificato: $TARGET_USER"
        else
            warn "Impossibile validare utente originale, resto root (Sconsigliato per Ardour)"
            export TARGET_USER="root"
        fi
    else
        export TARGET_USER="$USER"
        log "Esecuzione come utente normale: $USER"
    fi
    
    # Verifica appartenenza gruppi realtime
    if groups "$TARGET_USER" 2>/dev/null | grep -q "realtime\|audio"; then
        log "Utente $TARGET_USER appartiene ai gruppi realtime/audio"
    else
        warn "Utente $TARGET_USER NON appartiene ai gruppi realtime/audio"
    fi
    
    # Verifica accesso XAuthority (Suggerimento utente)
    verify_xauthority_access
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
    
    # 0. Pulizia istanze precedenti (Previene conflitti di lock) - Miglioramento suggerito
    log "Pulizia istanze Ardour precedenti..."
    pkill -u "${TARGET_USER}" -9 ardour8 || true
    sleep 1
    rm -f /tmp/ardour.pid
    
    # 1. Setup variabili d'ambiente (Essenziali per il bridging root -> user)
    local user_uid=$(id -u "${TARGET_USER}")
    export JACK_DEFAULT_SERVER="olms"
    export DISPLAY="${DISPLAY:-:0}"
    export XAUTHORITY="/home/${TARGET_USER}/.Xauthority"
    export XDG_RUNTIME_DIR="/run/user/${user_uid}"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_uid}/bus"
    
    # 1.1 Forza la sessione JACK nella directory del server root
    export JACK_SESSION_DIR="/dev/shm/jack-olms-0"

    # 2. Correzione permessi SHM (Senza questo JACK fallisce il bridge)
    # Ardour deve poter leggere la memoria condivisa creata da root
    chmod 777 /dev/shm/jack-olms-* 2>/dev/null || true

    # 3. Costruzione comando pulita - Senza runuser per evitare problemi di UID
    local ARDOUR_CMD=(
        taskset -c 2-3 
        chrt -f 70 
        env 
        DISPLAY="${DISPLAY}" 
        XAUTHORITY="${XAUTHORITY}" 
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" 
        DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" 
        JACK_DEFAULT_SERVER="olms" 
        JACK_NO_START_SERVER=1 
        JACK_SESSION_DIR="/dev/shm/jack-olms-0" 
        ardour8 -n "${ARDOUR_SESSION_FILE}"
    )

    log "Esecuzione Ardour su core 2-3..."

    # Esegui direttamente senza runuser
    "${ARDOUR_CMD[@]}" >> "${ARDOUR_LOG_FILE}" 2>&1 &
    
    local ardour_pid=$!
    echo "$ardour_pid" > "$ARDOUR_PID_FILE"
    
    # Logica di wait più intelligente - Miglioramento suggerito
    log "Monitoraggio avvio Ardour..."
    local wait_timeout=15
    local ardour_ready=false
    
    for ((i=1; i<=wait_timeout; i++)); do
        if kill -0 "$ardour_pid" 2>/dev/null; then
            # Controlla se Ardour ha caricato gli script GUI (indicatore di avvio completo)
            if [[ -f "$ARDOUR_LOG_FILE" ]] && tail -n 50 "$ARDOUR_LOG_FILE" 2>/dev/null | grep -q "GUI scripts loaded\|Ready\|startup complete"; then
                log "✅ Ardour avviato con PID: $ardour_pid (pronto dopo ${i}s)"
                ardour_ready=true
                break
            else
                log "Ardour in avvio... (${i}s/${wait_timeout}s)"
                sleep 1
            fi
        else
            error "Ardour è morto subito. Controlla ${ARDOUR_LOG_FILE}"
            return 1
        fi
    done
    
    if [[ "$ardour_ready" != "true" ]]; then
        warn "Timeout attesa avvio Ardour dopo ${wait_timeout}s"
        warn "Ardour potrebbe essere in esecuzione ma non completamente pronto"
        
        # Verifica comunque se il processo è attivo
        if kill -0 "$ardour_pid" 2>/dev/null; then
            log "Ardour è ancora in esecuzione (PID: $ardour_pid)"
        else
            error "Ardour non è più in esecuzione"
            return 1
        fi
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
        
        # Debug aggiuntivo per troubleshooting
        log "Debug: Verifica stato JACK e Ardour..."
        
        # Controlla se JACK è ancora attivo
        if command -v jack_control >/dev/null 2>&1; then
            local jack_status=$(jack_control status 2>/dev/null || echo "unknown")
            log "Stato JACK: $jack_status"
        fi
        
        # Controlla se Ardour è ancora in esecuzione
        if kill -0 "$ardour_pid" 2>/dev/null; then
            log "Ardour è ancora in esecuzione (PID: $ardour_pid)"
        else
            warn "Ardour non è più in esecuzione (PID: $ardour_pid)"
        fi
        
        # Controlla log di Ardour per errori
        if [[ -f "$ARDOUR_LOG_FILE" ]]; then
            log "Controllo errori in $ARDOUR_LOG_FILE..."
            local ardour_errors=$(tail -n 20 "$ARDOUR_LOG_FILE" 2>/dev/null | grep -i "error\|fail\|cannot\|unable" || true)
            if [[ -n "$ardour_errors" ]]; then
                warn "Errori trovati in ardour_startup.log:"
                echo "$ardour_errors" | while read -r line; do
                    warn "  $line"
                done
            else
                log "Nessun errore evidente in ardour_startup.log"
            fi
        fi
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
    
    # Fix XAuthority per root
    if [[ "$EUID" -eq 0 ]]; then
        # Permette a X11 di accettare connessioni dall'utente target
        xhost +SI:localuser:"${TARGET_USER:-francesco_ssh}" >/dev/null 2>&1 || true
        # Punta all'authority dell'utente, non di root
        export XAUTHORITY="/home/${TARGET_USER:-francesco_ssh}/.Xauthority"
    fi
    
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