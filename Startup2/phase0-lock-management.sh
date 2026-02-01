#!/bin/bash

# Fase 0.1: Lock File Management & Process Cleanup
# Versione: 2.0

set -euo pipefail

# Configurazione
LOCK_FILE="/tmp/olms-startup.lock"
PID_FILE="/tmp/olms-startup.pid"
LOG_FILE="/tmp/olms-orchestrator.log"
STALE_TIMEOUT=10  # secondi

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Verifica staleness del lock file
check_lock_staleness() {
    if [[ ! -f "$LOCK_FILE" ]]; then
        log "Nessun lock file esistente"
        return 0
    fi
    
    local lock_mtime=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local age=$((current_time - lock_mtime))
    
    log "Lock file esistente, età: ${age}s (timeout: ${STALE_TIMEOUT}s)"
    
    if [[ $age -gt $STALE_TIMEOUT ]]; then
        warn "Lock file considerato stale (> ${STALE_TIMEOUT}s)"
        # Rimuovi il lock file stale
        rm -f "$LOCK_FILE"
        return 0  # Procedi con cleanup
    fi
    
    # Verifica se il PID è ancora attivo
    local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        error "Processo di startup già in esecuzione (PID: $lock_pid)"
        exit 1
    fi
    
    # Se il PID non è attivo, rimuovi il lock file "morto"
    if [[ -n "$lock_pid" ]]; then
        warn "Lock file con PID $lock_pid non più attivo, rimozione lock file"
        rm -f "$LOCK_FILE"
    fi
    
    return 0
}

# Terminazione processi startup script
terminate_startup_processes() {
    log "Terminazione processi startup script esistenti..."
    
    # Trova tutti i processi bash che contengono "olms-startup"
    local startup_pids=$(pgrep -f "olms-startup" 2>/dev/null || true)
    
    if [[ -z "$startup_pids" ]]; then
        log "Nessun processo startup trovato"
        return 0
    fi
    
    log "Processi startup trovati: $startup_pids"
    
    # Fase 1: SIGTERM (grazioso)
    log "Invio SIGTERM ai processi startup..."
    for pid in $startup_pids; do
        if kill -TERM "$pid" 2>/dev/null; then
            log "SIGTERM inviato a PID $pid"
        else
            warn "Impossibile inviare SIGTERM a PID $pid"
        fi
    done
    
    sleep 2
    
    # Fase 2: SIGKILL (forzato)
    log "Invio SIGKILL ai processi rimanenti..."
    local remaining_pids=$(pgrep -f "olms-startup" 2>/dev/null || true)
    for pid in $remaining_pids; do
        if kill -KILL "$pid" 2>/dev/null; then
            log "SIGKILL inviato a PID $pid"
        else
            warn "Impossibile inviare SIGKILL a PID $pid"
        fi
    done
    
    sleep 1
    
    # Verifica finale
    local final_pids=$(pgrep -f "olms-startup" 2>/dev/null || true)
    if [[ -n "$final_pids" ]]; then
        warn "Alcuni processi startup non sono stati terminati: $final_pids"
    else
        log "Tutti i processi startup sono stati terminati"
    fi
}

# Cleanup Ardour sessions
cleanup_ardour_sessions() {
    log "Cleanup sessioni Ardour esistenti..."
    
    # Usa pgrep -x per evitare falsi positivi (es. editor di testo che apre file con "ardour" nel nome)
    local ardour_pids=$(pgrep -x "ardour" 2>/dev/null || true)
    
    if [[ -z "$ardour_pids" ]]; then
        log "Nessuna sessione Ardour in esecuzione"
        return 0
    fi
    
    log "Sessioni Ardour trovate: $ardour_pids"
    
    # Tentativo di salvataggio delle sessioni (se possibile)
    log "Tentativo di salvataggio sessioni Ardour..."
    for pid in $ardour_pids; do
        # Verifica che il PID esista prima di inviare il segnale
        if kill -0 "$pid" 2>/dev/null; then
            # Invia SIGUSR1 per salvataggio (se supportato)
            if kill -USR1 "$pid" 2>/dev/null; then
                log "Richiesta salvataggio inviata a Ardour PID $pid"
            else
                warn "Impossibile inviare segnale di salvataggio a Ardour PID $pid"
            fi
        else
            log "Ardour PID $pid non più attivo (terminato tra il rilevamento e il salvataggio)"
        fi
    done
    
    sleep 3
    
    # Terminazione forzata con verifica dello stato
    log "Terminazione forzata sessioni Ardour..."
    for pid in $ardour_pids; do
        # Verifica che il PID esista prima di tentare la terminazione
        if kill -0 "$pid" 2>/dev/null; then
            if kill -9 "$pid" 2>/dev/null; then
                log "Ardour PID $pid terminato"
            else
                warn "Errore durante il kill di Ardour PID $pid"
            fi
        else
            log "Ardour PID $pid già terminato (nessuna azione necessaria)"
        fi
    done
    
    sleep 2
    
    # Verifica finale con timeout
    local max_attempts=5
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local remaining_ardour=$(pgrep -x "ardour" 2>/dev/null || true)
        if [[ -z "$remaining_ardour" ]]; then
            log "Tutte le sessioni Ardour sono state terminate"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            warn "Timeout: alcune sessioni Ardour non sono state terminate dopo $max_attempts tentativi: $remaining_ardour"
            warn "Procedura di startup continuerà ma potrebbero esserci conflitti"
            return 1
        fi
        
        log "Tentativo $attempt/$max_attempts: sessioni Ardour rimanenti: $remaining_ardour"
        sleep 1
        ((attempt++))
    done
}

# Pulizia file temporanei
cleanup_temp_files() {
    log "Pulizia file temporanei..."
    
    # Rimuovi file lock esistenti
    rm -f "$LOCK_FILE" "$PID_FILE"
    
    # Rimuovi file temporanei specifici
    rm -f /tmp/olms-*.tmp
    rm -f /tmp/jack-*.tmp
    
    log "File temporanei puliti"
}

# Funzione principale
main() {
    log "=== FASE 0.1: LOCK FILE MANAGEMENT & PROCESS CLEANUP ==="
    
    # Verifica staleness
    check_lock_staleness
    
    # Terminazione processi
    terminate_startup_processes
    
    # Cleanup Ardour
    cleanup_ardour_sessions
    
    # Pulizia file
    cleanup_temp_files
    
    # Crea il lock file per questa esecuzione (dopo il cleanup)
    echo $$ > "$LOCK_FILE"
    
    log "Lock file management completato"
}

# Esegui se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi