# OLMS Startup System v2.0

Sistema di startup audio real-time completo per OLMS (Open Live Mixing System).

## Panoramica

Questo sistema trasforma un computer Linux standard in una workstation audio professionale con latenza minima, isolamento dei processi audio, e ottimizzazioni real-time complete.

## Architettura

Il sistema è organizzato in 8 fasi principali:

### Fase 0: Pre-Startup e Gestione Processi
- **Lock File Management**: Gestione file di lock e terminazione processi esistenti
- **Audio Environment Cleanup**: Pulizia nucleare dell'ambiente audio

### Fase 1: Ottimizzazione Sistema Real-Time
- Configurazione kernel parameters RT
- CPU governor e frequency scaling
- Power management e C-states
- Memory locking e realtime privileges

### Fase 2: Configurazione Hardware & IRQ Pinning
- Rilevamento hardware audio
- Configurazione IRQ affinity
- Verifica e validazione IRQ

### Fase 3: JACK Server Initialization
- Rilevamento dispositivo audio USB
- Avvio JACK con strategia adattiva
- Verifica stabilità JACK

### Fase 4: X11 Environment & Display Management
- Rilevamento display avanzato
- Configurazione XAUTHORITY
- Setup Xvfb per modalità headless

### Fase 5: Ardour DAW Startup
- Preparazione ambiente JACK
- Gestione privilegi e utenti
- Avvio Ardour con configurazione appropriata

### Fase 6: CPU Affinity & Resource Allocation
- Discovery processi audio
- Applicazione CPU affinity
- Verifica realtime priorities

### Fase 7: System Verification & Monitoring
- Verifica multi-metodo dello stato audio
- Monitoraggio risorse sistema
- Report finale verifica

### Fase 8: Final System State & Operational Readiness
- Verifica architettura sistema
- Performance optimization status
- Operational readiness checklist

## File del Sistema

### Script Principali
- `olms-orchestrator.sh` - Script principale che coordina tutte le fasi
- `phase0-lock-management.sh` - Gestione lock file e processi
- `phase0-audio-cleanup.sh` - Pulizia ambiente audio
- `phase1-rt-optimization.sh` - Ottimizzazione sistema RT
- `phase2-hardware-config.sh` - Configurazione hardware e IRQ
- `phase3-jack-init.sh` - Inizializzazione JACK
- `phase4-x11-setup.sh` - Configurazione X11
- `phase5-ardour-startup.sh` - Avvio Ardour
- `phase6-cpu-affinity.sh` - CPU affinity e allocazione risorse
- `phase7-verification.sh` - Verifica sistema
- `phase8-final-state.sh` - Stato finale e readiness

## Modalità di Esecuzione

### Modalità Standard
```bash
./Startup2/olms-orchestrator.sh
```

### Modalità Test
```bash
OLMS_MODE=test ./Startup2/olms-orchestrator.sh
```

### Modalità Produzione
```bash
OLMS_MODE=prod ./Startup2/olms-orchestrator.sh
```

### Modalità Virtuale
```bash
OLMS_MODE=virtual ./Startup2/olms-orchestrator.sh
```

## Configurazione RT

### Modalità RT
- **prod**: 95% CPU per RT (default)
- **test**: 80% CPU per RT (lascia 20% per GUI/debug)
- **light**: 60% CPU per RT (per ambienti debug pesanti)

Impostare con:
```bash
export OLMS_RT_MODE=prod
```

## Requisiti di Sistema

### Hardware Minimi
- CPU multi-core (minimo 4 core)
- 8GB RAM
- Interfaccia audio USB o scheda audio dedicata
- Spazio disco sufficiente

### Software Richiesto
- JACK Audio Connection Kit
- Ardour DAW
- ALSA utilities
- Real-time kernel (consigliato)
- X11 o Wayland

### Privilegi Necessari
- Accesso root per alcune operazioni di sistema
- Appartenenza ai gruppi `realtime` e `audio`
- Realtime privileges configurati

## Log e Monitoraggio

### File di Log Principali
- `/tmp/olms-orchestrator.log` - Log principale dell'orchestratore
- `/tmp/jack_startup.log` - Log avvio JACK
- `/tmp/olms-verification.log` - Log verifica sistema
- `/tmp/olms-final-state.log` - Log stato finale

### Monitoraggio in Tempo Reale
```bash
# Monitorare log in tempo reale
tail -f /tmp/olms-orchestrator.log

# Verificare stato processi audio
pgrep -f "jackd|ardour"

# Controllare CPU affinity
taskset -p <PID>

# Verificare priorità realtime
chrt -p <PID>
```

## Risoluzione Problemi

### Problemi Comuni

#### JACK non si avvia
- Verificare che non ci siano altri processi audio in esecuzione
- Controllare i permessi realtime
- Verificare la disponibilità del dispositivo audio

#### Ardour non si connette a JACK
- Verificare che JACK sia in esecuzione
- Controllare le impostazioni audio in Ardour
- Verificare i permessi utente

#### Performance scadenti
- Verificare CPU governor in performance mode
- Controllare IRQ pinning
- Verificare isolamento processi

#### Problemi X11
- Verificare DISPLAY environment variable
- Controllare XAUTHORITY file
- Verificare permessi X11

### Debug

#### Modalità Debug
```bash
# Eseguire una singola fase per debug
bash Startup2/phase1-rt-optimization.sh

# Verificare singoli componenti
bash Startup2/phase7-verification.sh
```

#### Log Dettagliati
```bash
# Abilitare log verbosi
export OLMS_DEBUG=1
./Startup2/olms-orchestrator.sh
```

## Sicurezza

### Considerazioni Sicurezza
- Alcune operazioni richiedono privilegi root
- Realtime privileges aumentano i permessi utente
- Memory locking illimitato può essere rischioso
- IRQ pinning modifica configurazioni di sistema

### Best Practice
- Eseguire solo su sistemi dedicati audio
- Monitorare l'uso della CPU
- Verificare regolarmente i log
- Aggiornare regolarmente il sistema

## Integrazione con OLMS

### Configurazione OLMS
Questo sistema è progettato per integrarsi con:
- OLMS Engine
- OLMS Session Templates
- OLMS Launchers
- OLMS Systemd Services

### Personalizzazione
- Modificare i parametri in base al proprio hardware
- Aggiornare i percorsi delle sessioni Ardour
- Personalizzare le strategie di fallback
- Adattare le verifiche in base alle esigenze

## Supporto

Per supporto e assistenza:
- Controllare i log di sistema
- Verificare la documentazione OLMS
- Contattare il team di sviluppo OLMS
- Consultare la community audio Linux

## Licenza

Questo software è parte del progetto OLMS e segue la sua licenza.