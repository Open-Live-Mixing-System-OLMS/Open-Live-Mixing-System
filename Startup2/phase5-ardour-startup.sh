#!/bin/bash

# Fase 5: Avvio di Ardour - FIX PARSING prlimit
set -euo pipefail

# Configurazione logging
LOG_FILE="/tmp/olms-ardour-startup.log"
# FIX: Assicurati che il file di log sia scrivibile da tutti per evitare Permission Denied
touch "$LOG_FILE"
chmod 666 "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Variabili universali per architettura CPU dinamica
TOTAL_CORES=$(nproc)
LAST_CORE=$((TOTAL_CORES - 1))
SYSTEM_CORE="0"
IRQ_CORE="1"
AUDIO_CORES="2-$LAST_CORE"

# Variabili JACK/D-Bus/X11
JACK_SERVER_NAME="olms"
JACK_SESSION_DIR="/dev/shm/jack_olms_0"
JACK_SOCKET_DIR="/dev/shm/jack_olms_0"
DBUS_SOCKET_ABSTRACT="olms_bus_$(id -u)"
XAUTHORITY_PATH="/home/$(whoami)/.Xauthority"
DISPLAY=":0"
CPU_CORES="$AUDIO_CORES"
RT_PRIORITY=70

# Funzioni di logging (per coerenza con altri script)
log() { echo -e "\e[32m[$(date '+%Y-%m-%d %H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%Y-%m-%d %H:%M:%S')] WARN:\e[0m $1"; }
error() { echo -e "\e[31m[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:\e[0m $1"; }

# Variabili di configurazione universale
# Rileva l'utente effettivo (quello che ha lanciato sudo) con logica robusta
# 1. Prova con SUDO_USER (se disponibile)
if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    EFFECTIVE_USER="$SUDO_USER"
    EFFECTIVE_HOME=$(eval echo ~$SUDO_USER)
    log "Utente rilevato da SUDO_USER: $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
# 2. Prova con TARGET_USER (passato dall'orchestrator)
elif [[ -n "${TARGET_USER:-}" ]] && [[ "$TARGET_USER" != "root" ]]; then
    EFFECTIVE_USER="$TARGET_USER"
    EFFECTIVE_HOME=$(eval echo ~$TARGET_USER)
    log "Utente rilevato da TARGET_USER: $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
# 3. Prova con loginuid (metodo robusto per processi lanciati con sudo)
elif [[ -f "/proc/$PPID/loginuid" ]]; then
    LOGINUID=$(cat "/proc/$PPID/loginuid" 2>/dev/null)
    if [[ -n "$LOGINUID" ]] && [[ "$LOGINUID" != "4294967295" ]] && [[ "$LOGINUID" != "0" ]]; then
        EFFECTIVE_USER=$(getent passwd "$LOGINUID" | cut -d: -f1)
        if [[ -n "$EFFECTIVE_USER" ]] && [[ "$EFFECTIVE_USER" != "root" ]]; then
            EFFECTIVE_HOME=$(eval echo ~$EFFECTIVE_USER)
            log "Utente rilevato da loginuid: $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
        else
            EFFECTIVE_USER="$(whoami)"
            EFFECTIVE_HOME="$HOME"
            log "Utente rilevato da whoami (fallback): $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
        fi
    else
        EFFECTIVE_USER="$(whoami)"
        EFFECTIVE_HOME="$HOME"
        log "Utente rilevato da whoami (fallback): $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
    fi
# 4. Fallback finale
else
    EFFECTIVE_USER="$(whoami)"
    EFFECTIVE_HOME="$HOME"
    log "Utente rilevato da whoami (fallback): $EFFECTIVE_USER (HOME: $EFFECTIVE_HOME)"
fi

# Verifica che l'utente effettivo non sia root (a meno che non sia intenzionale)
if [[ "$EFFECTIVE_USER" == "root" ]] && [[ "${OLMS_MODE:-}" != "headless" ]]; then
    warn "⚠️ Utente effettivo è root - verificare che sia intenzionale"
    warn "💡 Se si esegue con sudo, verificare che SUDO_USER sia impostato correttamente"
fi

# Variabili di configurazione
ARD_SESSION_PATH="$EFFECTIVE_HOME/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour"
ARD_SESSION_DIR="$EFFECTIVE_HOME/Progetti/OLMS-Core/engine/session-template/OLMS-POC"
ARD_USER="$EFFECTIVE_USER"
ARD_UID=$(id -u "$EFFECTIVE_USER" 2>/dev/null || echo "$(id -u)")
ACTUAL_UID=$(id -u "$EFFECTIVE_USER" 2>/dev/null || echo "$(id -u)")
ARD_HOME="$EFFECTIVE_HOME"

# Variabili per l'adattamento sessione
JACK_SERVER_NAME="olms"
SESSION_BACKUP_PATH="${ARD_SESSION_PATH}.backup"
SESSION_TEMP_PATH="${ARD_SESSION_PATH}.temp"

# Funzioni di logging (per coerenza con altri script)
log() { echo -e "\e[32m[$(date '+%Y-%m-%d %H:%M:%S')]\e[0m $1"; }
warn() { echo -e "\e[33m[$(date '+%Y-%m-%d %H:%M:%S')] WARN:\e[0m $1"; }
error() { echo -e "\e[31m[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:\e[0m $1"; }

# Funzioni di adattamento sessione Ardour
detect_jack_ports() {
    log "🔍 Rilevamento porte JACK disponibili per il server '$JACK_SERVER_NAME'..."
    
    # Configurazione ambiente completa (come nel latency test)
    local base_env="PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1"
    
    # Primo tentativo: rileva le porte JACK disponibili con ambiente completo
    local available_ports
    available_ports=$(sudo -u "$ARD_USER" env $base_env jack_lsp 2>/dev/null | grep "^system:" | sort)
    
    if [ -z "$available_ports" ]; then
        warn "⚠️ Nessuna porta JACK trovata per il server '$JACK_SERVER_NAME' con jack_lsp"
        warn "💡 JACK è stabile ma jack_lsp non riesce a vedere le porte (problema comune con schede economiche)"
        
        # Secondo tentativo: prova con ambiente semplificato
        log "🔧 Tentativo con ambiente semplificato..."
        available_ports=$(sudo -u "$ARD_USER" env JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1 jack_lsp 2>/dev/null | grep "^system:" | sort)
        
        if [ -z "$available_ports" ]; then
            warn "⚠️ Ancora nessuna porta trovata con ambiente semplificato"
            
            # Terzo tentativo: prova senza JACK_NO_START_SERVER
            log "🔧 Tentativo senza JACK_NO_START_SERVER..."
            available_ports=$(sudo -u "$ARD_USER" env JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_PROMISCUOUS_SERVER=1 jack_lsp 2>/dev/null | grep "^system:" | sort)
            
            if [ -z "$available_ports" ]; then
                warn "⚠️ Nessuna porta JACK trovata con nessun metodo"
                warn "🔧 Utilizzo porte predefinite per scheda audio standard..."
                
                # Fallback: porte predefinite per schede audio standard
                export JACK_CAPTURE_PORTS="system:capture_1"
                export JACK_PLAYBACK_PORTS="system:playback_1
system:playback_2"
                export CAPTURE_COUNT=1
                export PLAYBACK_COUNT=2
                
                log "✅ Porte predefinite impostate:"
                log "  - Capture: system:capture_1"
                log "  - Playback 1: system:playback_1"
                log "  - Playback 2: system:playback_2"
                
                return 0
            fi
        fi
    fi
    
    log "✅ Porte JACK disponibili trovate:"
    echo "$available_ports" | while read -r port; do
        log "  - $port"
    done
    
    # Salva le porte disponibili in variabili globali
    export JACK_CAPTURE_PORTS=$(echo "$available_ports" | grep "capture" | head -10)
    export JACK_PLAYBACK_PORTS=$(echo "$available_ports" | grep "playback" | head -10)
    
    # Conta le porte disponibili
    export CAPTURE_COUNT=$(echo "$JACK_CAPTURE_PORTS" | wc -l)
    export PLAYBACK_COUNT=$(echo "$JACK_PLAYBACK_PORTS" | wc -l)
    
    log "Porte disponibili: $CAPTURE_COUNT capture, $PLAYBACK_COUNT playback"
    
    return 0
}

backup_session() {
    log "📁 Creazione backup sessione Ardour..."
    
    if [ -f "$ARD_SESSION_PATH" ]; then
        sudo -u $(whoami) cp "$ARD_SESSION_PATH" "$SESSION_BACKUP_PATH"
        if [ $? -eq 0 ]; then
            log "✅ Backup sessione creato: $SESSION_BACKUP_PATH"
            return 0
        else
            error "Impossibile creare il backup della sessione"
            return 1
        fi
    else
        error "File sessione non trovato: $ARD_SESSION_PATH"
        return 1
    fi
}

validate_port_mapping() {
    log "✅ Validazione mappatura porte..."
    
    # Controlla che ci siano abbastanza porte per la sessione
    local required_capture=1  # Audio 1 richiede 1 porta capture
    local required_playback=2 # Master e Click richiedono 2 porte playback
    
    if [ "$CAPTURE_COUNT" -lt "$required_capture" ]; then
        error "Porte capture insufficienti: necessarie $required_capture, disponibili $CAPTURE_COUNT"
        return 1
    fi
    
    if [ "$PLAYBACK_COUNT" -lt "$required_playback" ]; then
        error "Porte playback insufficienti: necessarie $required_playback, disponibili $PLAYBACK_COUNT"
        return 1
    fi
    
    log "✅ Validazione superata: porte sufficienti per la sessione"
    return 0
}

adapt_session_to_ports() {
    log "🔧 Adattamento sessione Ardour alle porte disponibili..."
    
    if ! validate_port_mapping; then
        return 1
    fi
    
    # Estrai la prima porta capture disponibile
    local capture_port=$(echo "$JACK_CAPTURE_PORTS" | head -1)
    # Estrai le prime 2 porte playback disponibili
    local playback_port_1=$(echo "$JACK_PLAYBACK_PORTS" | head -1)
    local playback_port_2=$(echo "$JACK_PLAYBACK_PORTS" | sed -n '2p')
    
    log "Mappatura porte:"
    log "  Capture: system:capture_1 → $capture_port"
    log "  Playback 1: system:playback_1 → $playback_port_1"
    log "  Playback 2: system:playback_2 → $playback_port_2"
    
    # Crea il file temporaneo con le sostituzioni come utente $(whoami)
    sudo -u $(whoami) cp "$ARD_SESSION_PATH" "$SESSION_TEMP_PATH"
    
    # Sostituzione delle connessioni JACK nel file XML come utente $(whoami)
    # Usiamo sed per sostituire i pattern specifici
    sudo -u $(whoami) sed -i "s/other=\"system:capture_1\"/other=\"$capture_port\"/g" "$SESSION_TEMP_PATH"
    sudo -u $(whoami) sed -i "s/other=\"system:playback_1\"/other=\"$playback_port_1\"/g" "$SESSION_TEMP_PATH"
    sudo -u $(whoami) sed -i "s/other=\"system:playback_2\"/other=\"$playback_port_2\"/g" "$SESSION_TEMP_PATH"
    
    # Verifica che le sostituzioni siano avvenute correttamente
    local capture_subs=$(grep -c "$capture_port" "$SESSION_TEMP_PATH")
    local playback1_subs=$(grep -c "$playback_port_1" "$SESSION_TEMP_PATH")
    local playback2_subs=$(grep -c "$playback_port_2" "$SESSION_TEMP_PATH")
    
    log "Sostituzioni effettuate:"
    log "  Capture: $capture_subs occorrenze"
    log "  Playback 1: $playback1_subs occorrenze"
    log "  Playback 2: $playback2_subs occorrenze"
    
    if [ "$capture_subs" -gt 0 ] && [ "$playback1_subs" -gt 0 ] && [ "$playback2_subs" -gt 0 ]; then
        log "✅ Sessione adattata correttamente alle porte disponibili"
        return 0
    else
        error "Sostituzione porte fallita o incompleta"
        return 1
    fi
}

reload_ardour_session() {
    log "🔄 Ricaricamento sessione Ardour..."
    
    # Trova il PID di Ardour
    local ardour_pid
    ardour_pid=$(pgrep -f "ardour8.*--no-splash")
    
    if [ -z "$ardour_pid" ]; then
        error "Impossibile trovare il processo Ardour"
        return 1
    fi
    
    log "Ardour in esecuzione (PID: $ardour_pid)"
    
    # Invia segnale di ricarica alla sessione
    # Ardour non supporta il reload diretto via segnale, quindi dobbiamo riavviarlo
    log "Riavvio Ardour con sessione aggiornata..."
    
    # Termina Ardour in modo pulito
    kill -TERM "$ardour_pid" 2>/dev/null || true
    sleep 2
    
    # Verifica che Ardour sia terminato
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        log "Ardour non si è chiuso correttamente, forzatura terminazione..."
        kill -KILL "$ardour_pid" 2>/dev/null || true
        sleep 1
    fi
    
    # Sposta il file temporaneo al posto di quello originale come utente $(whoami)
    sudo -u $(whoami) mv "$SESSION_TEMP_PATH" "$ARD_SESSION_PATH"
    
    # Riavvia Ardour con la sessione aggiornata
    log "Riavvio Ardour con sessione adattata..."
    
    sudo -u "$ARD_USER" env \
        HOME=$EFFECTIVE_HOME \
        DISPLAY=:0 \
        XAUTHORITY=$EFFECTIVE_HOME/.Xauthority \
        XDG_RUNTIME_DIR=/run/user/$ARD_UID \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH" &
    
    # Aspetta che Ardour si riavvii
    sleep 3
    
    # Verifica che Ardour sia di nuovo in esecuzione
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        local new_ardour_pid=$(pgrep -f "ardour8.*--no-splash")
        log "✅ Ardour riavviato con sessione adattata (PID: $new_ardour_pid)"
        return 0
    else
        error "Riavvio Ardour fallito"
        return 1
    fi
}

# Controllo modalità headless
if [[ "${OLMS_MODE:-}" == "headless" ]]; then
    log "FASE 5: Modalità headless - Configurazione Xvfb e Ardour"

    # 1. Pulizia e avvio Xvfb sul display :99
    # Rimuoviamo eventuali lock residui se il server è crashato in precedenza
    sudo rm -f /tmp/.X99-lock
    
    log "Avvio server grafico virtuale (Xvfb) su :99..."
    sudo -u "$ARD_USER" Xvfb :99 -screen 0 1024x768x16 > /dev/null 2>&1 &
    XVFB_PID=$!
    
    # Aspetta che Xvfb sia pronto
    sleep 1

    # 2. Avvio Ardour puntando al display virtuale
    log "Avvio Ardour su DISPLAY=:99 (Headless)"
    
    exec sudo -u "$ARD_USER" env \
        HOME=/home/$(whoami) \
        DISPLAY=:99 \
        XAUTHORITY=/home/$(whoami)/.Xauthority \
        XDG_RUNTIME_DIR=/run/user/$(id -u) \
        JACK_DEFAULT_SERVER="olms" \
        JACK_PROMISCUOUS_SERVER=1 \
        JACK_NO_START_SERVER=1 \
        taskset -c "$CPU_CORES" \
        chrt -f "$RT_PRIORITY" \
        /usr/bin/ardour8 --no-splash "$ARD_SESSION_PATH" &
    
    # Aspetta un momento per l'inizializzazione
    sleep 3
    
    # 3. Verifica processi
    if pgrep -f "ardour8.*--no-splash" > /dev/null; then
        ardour_pid=$(pgrep -f "ardour8.*--no-splash")
        log "✅ Ardour (Headless) e Xvfb avviati (Ardour PID: $ardour_pid, Xvfb PID: $XVFB_PID)"
    else
        error "ERRORE: Ardour headless non è partito. Controlla i log."
        kill $XVFB_PID 2>/dev/null
        exit 1
    fi
    exit 0
fi

check_user_permissions() {
    log "Verifica permessi utente $ARD_USER..."
    
    # Estraiamo il valore SOFT (terzultimo) e HARD (penultimo) per essere sicuri
    local rtprio_limit=$(sudo -u "$ARD_USER" prlimit --rtprio --pid=$$ --noheadings --output=SOFT)
    local memlock_limit=$(sudo -u "$ARD_USER" prlimit --memlock --pid=$$ --noheadings --output=SOFT)

    log "Rilevato rtprio_limit: $rtprio_limit"
    log "Rilevato memlock_limit: $memlock_limit"

    if [[ "$rtprio_limit" != "unlimited" ]] && [ "$rtprio_limit" -lt 90 ]; then
        log "ERRORE: rtprio troppo basso ($rtprio_limit)"
        return 1
    fi
    return 0
}

start_ardour_with_fallback() {
    log "=== AVVIO ARDOUR ==="
    
    # Ambiente pulito per l'esecuzione come utente target
    local base_env="DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY_PATH XDG_RUNTIME_DIR=/run/user/$ARD_UID DBUS_SESSION_BUS_ADDRESS=unix:abstract=$DBUS_SOCKET_ABSTRACT JACK_DEFAULT_SERVER=$JACK_SERVER_NAME JACK_SESSION_DIR=$JACK_SESSION_DIR JACK_NO_START_SERVER=1 JACK_PROMISCUOUS_SERVER=1"

    log "Esecuzione comando finale..."
    log "Transizione utente: sudo -u $ARD_USER (UID: $ARD_UID)"
    log "Ambiente impostato: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY_PATH"
    log "Comando: taskset -c $CPU_CORES chrt -f $RT_PRIORITY /usr/bin/ardour8 -Z olms -n $ARD_SESSION_PATH"
    
    # Aggiungi esplicitamente il flag -Z (o --jack-server) ad Ardour
    sudo -u "$ARD_USER" -E env $base_env taskset -c "$CPU_CORES" chrt -f "$RT_PRIORITY" /usr/bin/ardour8 -Z olms -n "$ARD_SESSION_PATH"
}

# --- LIVELLO 1: PULIZIA RADICALE E RESET SHM ---
fix_shm_permissions_radical() {
    log "🧹 PULIZIA E FIX SHM: Analisi segmenti condivisi..."

    # 1. Identifica se c'è un server JACK attivo e di chi è
    local jack_pid=$(pgrep -x "jackd" || echo "")
    
    if [[ -n "$jack_pid" ]]; then
        local jack_user=$(ps -o user= -p "$jack_pid")
        log "ℹ️ JACK Server attivo (PID: $jack_pid, User: $jack_user)"
        
        # Se JACK è root, dobbiamo aprire tutto
        if [[ "$jack_user" == "root" ]]; then
            warn "⚠️ JACK sta girando come ROOT. Applicazione patch permessi aggressiva..."
        fi
    else
        warn "⚠️ Nessun processo JACK trovato. Ardour potrebbe non partire."
    fi

    # 2. Fix permessi directory e file standard in /dev/shm
    # Cerchiamo tutto ciò che assomiglia a JACK
    log "🔧 Applicazione chmod 777 su /dev/shm/jack*..."
    
    # Questo sblocca le directory come /dev/shm/jack_olms_0
    find /dev/shm -name "jack*" -exec chmod 777 {} \; 2>/dev/null || true
    
    # Fix specifico per i semafori (spesso causa di Permission Denied)
    chmod 666 /dev/shm/sem.jack* 2>/dev/null || true
    
    # 3. FIX CRITICO PER POSIX SHM (/dev/shm/jack-*-*)
    # Il kernel Linux mappa shm_open in /dev/shm.
    # Se JACK è root (UID 0), crea /dev/shm/jack-0-*.
    # Ardour (UID 1000) cerca di aprirli.
    
    log "🔧 Ricerca segmenti SHM orfani o bloccati..."
    for seg in /dev/shm/jack-*-*; do
        if [ -e "$seg" ]; then
            # Controlla se è di proprietà di root
            if [ "$(stat -c '%u' "$seg")" -eq 0 ]; then
                log "🔓 Sblocco segmento ROOT: $seg"
                chown "$ARD_USER":audio "$seg" 2>/dev/null || true # Tenta il cambio owner
                chmod 777 "$seg" # Forza lettura/scrittura per tutti
            else
                chmod 777 "$seg"
            fi
        fi
    done

    # 4. Assicuriamoci che la directory del registry esista e sia accessibile
    if [ ! -f "/dev/shm/jack-shm-registry" ]; then
        # A volte JACK crea pipe invece di file, o usa directory diverse
        warn "File registry non trovato standard, controllo directory alternative..."
    else
        chmod 666 "/dev/shm/jack-shm-registry"
    fi

    log "✅ Fix permessi completato."
}

# --- LIVELLO 2: WRAPPER NELLA HOME UTENTE (Fix Permission Denied) ---
create_ardour_wrapper() {
    local wrapper_path="$EFFECTIVE_HOME/.olms_ardour_launcher.sh"
    mkdir -p "$(dirname "$wrapper_path")"
    
    log "🏗️ Creazione wrapper script (NO-START MODE) in $wrapper_path..." >&2
    
    cat << EOF > "$wrapper_path"
#!/bin/bash
# OLMS Ardour Launcher - Forced Connection Mode

# 1. Variabili d'ambiente per forzare le librerie JACK a non avviare un server
export JACK_DEFAULT_SERVER="$JACK_SERVER_NAME"
export JACK_NO_START_SERVER=1
export JACK_PROMISCUOUS_SERVER=1
export JACK_SESSION_DIR="/dev/shm/jack_olms_0"

# 2. Variabili Grafiche
export DISPLAY=:0
export XAUTHORITY=$EFFECTIVE_HOME/.Xauthority

# 3. Verifica esistenza Socket prima di partire
if [ ! -S "/dev/shm/jack_olms_0" ]; then
    echo "ERROR: JACK socket not found. Server '$JACK_SERVER_NAME' is not running."
    exit 1
fi

# 4. Limiti RT
ulimit -r 99
ulimit -l unlimited

# 5. Lancio ATOMICO
exec taskset -c $CPU_CORES chrt -f $RT_PRIORITY /usr/bin/ardour8 \\
    --no-splash \\
    "$ARD_SESSION_PATH"
EOF

    chown "$ARD_USER":"$(id -gn "$ARD_USER")" "$wrapper_path"
    chmod +x "$wrapper_path"
    echo "$wrapper_path"
}

# --- LIVELLO 3: MONITORAGGIO THREAD BREVE ---
monitor_anti_migration_brief() {
    local target_pid=$1
    log "🛰️ Monitoraggio breve thread Ardour sui Core $AUDIO_CORES (PID: $target_pid)"
    
    # Monitoraggio breve per 10 secondi durante l'avvio critico
    (
        for i in {1..10}; do
            # Applica pinning a TUTTI i thread correnti
            if [ -d "/proc/$target_pid/task" ]; then
                ls "/proc/$target_pid/task" 2>/dev/null | xargs -I {} taskset -pc "$AUDIO_CORES" {} >/dev/null 2>&1
            fi
            sleep 1
        done
        log "✅ Monitoraggio breve completato."
    ) &
}

main() {
    log "=== FASE 5: STARTUP ARDOUR (Triple-Lock Mode) ==="
    
    # 1. Preparazione SHM
    fix_shm_permissions_radical

    # 2. Creazione Wrapper (Ora nella Home)
    local WRAPPER_SCRIPT=$(create_ardour_wrapper)

    # Verifica che il wrapper sia stato creato correttamente
    if [ ! -f "$WRAPPER_SCRIPT" ]; then
        error "❌ ERRORE: Wrapper script non creato correttamente: $WRAPPER_SCRIPT"
        exit 1
    fi

    # Aggiungi un piccolo ritardo per assicurare che il file sia completamente scritto
    sleep 0.5

    # Verifica i permessi di esecuzione
    if [ ! -x "$WRAPPER_SCRIPT" ]; then
        warn "⚠️ Wrapper non eseguibile, riparazione permessi..."
        chmod +x "$WRAPPER_SCRIPT"
    fi

    # 3. Lancio ATOMICO
    log "🚀 Lancio atomico tramite wrapper..."
    # Rimuoviamo il -E di sudo per evitare conflitti di variabili, le passiamo nel wrapper
    sudo -u "$ARD_USER" /bin/bash "$WRAPPER_SCRIPT" &
    local ARD_PID=$!

    # Piccolo check per vedere se il wrapper ha almeno avviato bash
    sleep 0.2
    if ! ps -p $ARD_PID > /dev/null; then
        error "❌ Il wrapper bash non è partito correttamente."
        exit 1
    fi
    
    # 4. Monitoraggio immediato (Breve)
    monitor_anti_migration_brief "$ARD_PID"

    # 5. Verifica Kernel
    sleep 3
    local final_mask=$(taskset -p "$ARD_PID" | awk '{print $NF}')
    log "📊 VERIFICA FINALE KERNEL: Mask=$final_mask (Target: 0xc)"

    if [[ "$final_mask" == "f" ]]; then
        error "❌ ERRORE: Il sistema continua a forzare la maschera 'f'. Possibile override di systemd o cgroups."
        exit 1
    fi

    log "✅ ADATTAMENTO E STARTUP COMPLETATI."
}

main "$@"