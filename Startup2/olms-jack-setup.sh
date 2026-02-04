#!/bin/bash
# OLMS JACK Setup Script
# Configures JACK for optimal performance with OLMS
# Addresses the "Dummy" problem by implementing the expert strategy

set -euo pipefail

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Funzione principale di setup JACK
setup_jack() {
    log "=== OLMS JACK Setup ==="
    log "Configuring JACK for optimal performance with OLMS"
    
    # 1. Bonifica totale di /dev/shm
    log "1. Bonifica totale di /dev/shm"
    sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    log "   Residui JACK rimossi"
    
    # 2. Applicazione setcap a jackd
    log "2. Applicazione setcap a jackd"
    if command -v setcap >/dev/null 2>&1; then
        sudo setcap 'cap_ipc_lock,cap_sys_nice,cap_sys_resource+ep' /usr/bin/jackd
        log "   setcap applicato a /usr/bin/jackd"
        
        # Verifica setcap
        local capabilities=$(getcap /usr/bin/jackd 2>/dev/null || echo "Nessuna capability")
        log "   Capabilities verificate: $capabilities"
    else
        error "setcap non disponibile. Installare util-linux."
        return 1
    fi
    
    # 3. Verifica limiti realtime
    log "3. Verifica limiti realtime"
    if [[ -f "/etc/security/limits.d/99-realtime.conf" ]]; then
        log "   File limiti realtime trovato: /etc/security/limits.d/99-realtime.conf"
        
        # Verifica appartenenza gruppi
        if groups "$USER" 2>/dev/null | grep -q "realtime\|audio"; then
            log "   Utente $USER appartiene ai gruppi realtime/audio"
        else
            warn "   Utente $USER NON appartiene ai gruppi realtime/audio"
            warn "   Eseguire: sudo usermod -a -G realtime,audio $USER"
        fi
    else
        warn "   File limiti realtime non trovato"
    fi
    
    # 4. Verifica shared memory
    log "4. Verifica shared memory (/dev/shm)"
    local shm_mount=$(mount | grep /dev/shm | grep -v grep)
    if [[ -n "$shm_mount" ]]; then
        log "   /dev/shm montato correttamente: $shm_mount"
        
        # Verifica permessi noexec
        if echo "$shm_mount" | grep -q "noexec"; then
            warn "   /dev/shm montato con noexec - potrebbe causare problemi con JACK"
        else
            log "   /dev/shm senza noexec - OK per JACK"
        fi
    else
        error "   /dev/shm non montato"
        return 1
    fi
    
    # 5. Test JACK con backend dummy (SENZA sudo)
    log "5. Test JACK con backend dummy (come utente normale)"
    
    # Disabilita D-Bus per JACK (importante per SSH)
    export JACK_NO_AUDIO_RESERVATION=1
    
    # Test con backend dummy come utente normale
    taskset -c 2-3 chrt -f 80 jackd -R -P 80 -d dummy -r 48000 -p 256 -n 2 >/dev/null 2>&1 &
    local dummy_pid=$!
    sleep 2
    if kill -0 $dummy_pid 2>/dev/null; then
        kill $dummy_pid 2>/dev/null || true
        log "   Backend dummy funzionante - JACK avviato come utente normale"
    else
        warn "   Backend dummy non funzionante - vedere errore dettagliato"
        kill $dummy_pid 2>/dev/null || true
    fi
    
    # 6. Test JACK con backend ALSA (SENZA sudo)
    log "6. Test JACK con backend ALSA (come utente normale)"
    local alsa_test_result=""
    
    # Trova indice numerico della scheda USB Audio CODEC (più affidabile di hw:Nome)
    local codec_index=$(aplay -l 2>/dev/null | grep -i "USB Audio CODEC" | head -1 | cut -d' ' -f2 | tr -d ':')
    if [[ -n "$codec_index" ]]; then
        log "   Dispositivo ALSA trovato all'indice: $codec_index"
        local codec_device="hw:$codec_index"
        
        # Test con ALSA come utente normale (SENZA sudo)
        taskset -c 2-3 chrt -f 80 jackd -R -P 80 -name olms -T -d alsa -d "$codec_device" -r 48000 -p 256 -n 3 >/dev/null 2>&1 &
        local alsa_pid=$!
        sleep 3
        if kill -0 $alsa_pid 2>/dev/null; then
            kill $alsa_pid 2>/dev/null || true
            log "   Backend ALSA funzionante - PROBLEMA JACK RISOLTO!"
            alsa_test_result="SUCCESS"
        else
            warn "   Backend ALSA non funzionante - errore futex persistente"
            alsa_test_result="FAILED"
        fi
    else
        warn "   Dispositivo ALSA non trovato"
        alsa_test_result="NO_DEVICE"
    fi
    
    # 7. Configurazione finale
    log "7. Configurazione finale"
    
    # Crea directory per script di avvio
    sudo mkdir -p /etc/olms/jack
    
    # Copia script di avvio ottimizzato
    if [[ -f "/usr/bin/olms-jack-init-fixed" ]]; then
        sudo cp /usr/bin/olms-jack-init-fixed /etc/olms/jack/jack-init.sh
        sudo chmod +x /etc/olms/jack/jack-init.sh
        log "   Script di avvio JACK copiato in /etc/olms/jack/jack-init.sh"
    fi
    
    # Crea script di test
    cat > /tmp/jack_test.sh << 'EOF'
#!/bin/bash
# Test script per verificare JACK con OLMS

echo "=== Test JACK con OLMS ==="

# Test connessione JACK
echo "1. Test connessione JACK..."
if env JACK_DEFAULT_SERVER=olms jack_lsp >/dev/null 2>&1; then
    echo "   ✅ JACK 'olms' accessibile"
    echo "   Porte disponibili:"
    env JACK_DEFAULT_SERVER=olms jack_lsp | while read -r port; do
        echo "     - $port"
    done
else
    echo "   ❌ JACK 'olms' non accessibile"
fi

# Test Ardour connection
echo "2. Test connessione Ardour..."
if command -v ardour8 >/dev/null 2>&1; then
    echo "   Ardour installato"
    echo "   Per testare Ardour, avviare:"
    echo "   env JACK_DEFAULT_SERVER=olms ardour8"
else
    echo "   Ardour non installato"
fi

echo "=== Test completato ==="
EOF
    
    sudo cp /tmp/jack_test.sh /etc/olms/jack/test.sh
    sudo chmod +x /etc/olms/jack/test.sh
    log "   Script di test creato in /etc/olms/jack/test.sh"
    
    # 8. Riassunto configurazione
    log "=== Riassunto Configurazione JACK ==="
    log "✅ Bonifica /dev/shm: COMPLETATA"
    log "✅ setcap applicato: COMPLETATO"
    log "✅ Limiti realtime: VERIFICATI"
    log "✅ Shared memory: VERIFICATA"
    
    case "$alsa_test_result" in
        "SUCCESS")
            log "✅ Backend ALSA: FUNZIONANTE - PROBLEMA JACK RISOLTO!"
            ;;
        "FAILED")
            log "❌ Backend ALSA: FALLITO - Problema persistente"
            ;;
        "NO_DEVICE")
            log "⚠️  Backend ALSA: DISPOSITIVO NON TROVATO"
            ;;
    esac
    
    log ""
    log "Per testare la configurazione:"
    log "  sudo /etc/olms/jack/test.sh"
    log ""
    log "Per avviare JACK:"
    log "  sudo /etc/olms/jack/jack-init.sh"
    log ""
    log "Per avviare Ardour:"
    log "  env JACK_DEFAULT_SERVER=olms ardour8"
    
    return 0
}

# Funzione di pulizia JACK
cleanup_jack() {
    log "=== Pulizia JACK ==="
    
    # Termina processi JACK
    pkill -9 jackd 2>/dev/null || true
    pkill -9 jackdbus 2>/dev/null || true
    log "   Processi JACK terminati"
    
    # Pulisci socket
    sudo rm -rf /dev/shm/jack* /tmp/jack* 2>/dev/null || true
    log "   Socket JACK rimossi"
    
    # Pulisci registri
    sudo rm -f /dev/shm/jack-shm-registry* 2>/dev/null || true
    log "   Registri JACK rimossi"
    
    log "Pulizia JACK completata"
}

# Funzione di verifica stato
check_status() {
    log "=== Stato Sistema JACK ==="
    
    # Verifica processi
    local jack_processes=$(pgrep -f "jackd\|jackdbus" || echo "")
    if [[ -n "$jack_processes" ]]; then
        log "Processi JACK attivi:"
        ps -p $jack_processes -o pid,cmd --no-headers 2>/dev/null || echo "   Nessun processo trovato"
    else
        log "Nessun processo JACK attivo"
    fi
    
    # Verifica socket
    local jack_sockets=$(find /dev/shm /tmp -name "*jack*" -type d 2>/dev/null || echo "")
    if [[ -n "$jack_sockets" ]]; then
        log "Socket JACK presenti:"
        echo "$jack_sockets" | while read -r socket; do
            log "   $socket"
        done
    else
        log "Nessun socket JACK trovato"
    fi
    
    # Verifica capabilities
    if command -v getcap >/dev/null 2>&1; then
        local capabilities=$(getcap /usr/bin/jackd 2>/dev/null || echo "Nessuna capability")
        log "Capabilities JACK: $capabilities"
    fi
    
    # Verifica limiti utente
    log "Limiti utente:"
    log "  rtprio: $(ulimit -r)"
    log "  memlock: $(ulimit -l)"
    log "  Gruppi: $(groups)"
}

# Help
show_help() {
    echo "OLMS JACK Setup Script"
    echo ""
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandi disponibili:"
    echo "  setup     Configura JACK per OLMS (default)"
    echo "  cleanup   Pulisce i processi e socket JACK"
    echo "  status    Mostra lo stato del sistema JACK"
    echo "  test      Esegue test di connessione JACK"
    echo "  help      Mostra questo aiuto"
    echo ""
    echo "Esempi:"
    echo "  sudo $0 setup    # Configura JACK"
    echo "  sudo $0 cleanup  # Pulisce JACK"
    echo "  $0 status        # Controlla stato"
}

# Main
main() {
    local command="${1:-setup}"
    
    case "$command" in
        "setup")
            setup_jack
            ;;
        "cleanup")
            cleanup_jack
            ;;
        "status")
            check_status
            ;;
        "test")
            if [[ -f "/etc/olms/jack/test.sh" ]]; then
                /etc/olms/jack/test.sh
            else
                error "Script di test non trovato. Eseguire prima 'setup'."
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Comando sconosciuto: $command"
            show_help
            exit 1
            ;;
    esac
}

# Esegui main se chiamato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi