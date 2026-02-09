# OLMS Startup2 - Sistema Universale

## Panoramica

Il processo startup2 è stato reso **universale** per funzionare con qualsiasi utente Linux, eliminando tutti i riferimenti hardcoded all'utente "francesco_ssh".

## Cosa è stato modificato

### 1. Variabili Universali

Sostituite tutte le occorrenze hardcoded con variabili dinamiche:

- `francesco_ssh` → `$(whoami)`
- `/home/francesco_ssh` → `$HOME`
- `1000` → `$(id -u)`

### 2. Gestione Intelligente dell'Esecuzione con Sudo

Implementata logica avanzata per gestire correttamente l'esecuzione con `sudo`:

```bash
# Rilevamento utente effettivo
if [[ "$EUID" -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" ]]; then
        ACTUAL_USER="$SUDO_USER"
        ACTUAL_HOME=$(eval echo ~$SUDO_USER)
    elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
        ACTUAL_USER="$USER"
        ACTUAL_HOME=$(eval echo ~$USER)
    else
        ACTUAL_USER="root"
        ACTUAL_HOME="/root"
    fi
else
    ACTUAL_USER="$(whoami)"
    ACTUAL_HOME="$HOME"
fi
```

### 3. Gestione Intelligente del File di Log

Sistemato il problema del logging quando lo script viene eseguito con sudo:

- Log file ora puntano sempre alla home directory corretta
- Gestione automatica dei permessi di scrittura
- Fallback a percorsi temporanei se necessario

### 4. Variabili d'Ambiente Universali

Aggiornate tutte le variabili d'ambiente per usare `ACTUAL_USER` e `ACTUAL_HOME`:

```bash
export TARGET_USER="$ACTUAL_USER"
export TARGET_UID=$(id -u "$ACTUAL_USER")
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"
export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
export XAUTHORITY="$ACTUAL_HOME/.Xauthority"
```

## Nuovi Script: OLMS Bootstrap

### `olms-bootstrap.sh`

Script di configurazione universale che genera automaticamente:

1. **Regole Udev USB** (`/etc/udev/rules.d/99-olms-usb-permissions.rules`)
   - Permessi per dispositivi audio USB
   - Configurazione specifica per l'utente corrente

2. **Regole Udev JACK** (`/etc/udev/rules.d/99-olms-jack-sockets.rules`)
   - Permessi per socket JACK
   - Accesso ai file socket senza sudo

3. **Limiti Realtime** (`/etc/security/limits.d/99-olms-realtime.conf`)
   - Priorità realtime (rtprio 99)
   - Memory locking illimitato
   - Configurazione per gruppi audio e realtime

4. **Configurazione Kernel RT** (`/etc/sysctl.d/99-olms-rt.conf`)
   - Parametri kernel per audio real-time
   - Configurazione IRQ e scheduling

5. **Configurazione Gruppi Utente**
   - Aggiunta utente ai gruppi necessari (audio, realtime, plugdev)

## Come Usare il Sistema Universale

### 1. Configurazione Iniziale (Primo Utilizzo)

```bash
# Esegui come root per configurare il sistema
sudo ./olms-bootstrap.sh

# Segui le istruzioni a schermo
# Riavvia la sessione utente dopo la configurazione
```

### 2. Avvio del Sistema

```bash
# Modalità test (con interfaccia grafica)
sudo ./olms-orchestrator.sh --test

# Modalità headless (senza interfaccia grafica)
sudo ./olms-orchestrator.sh
```

### 3. Per Utenti Diversi

Il sistema ora funziona automaticamente per qualsiasi utente:

```bash
# Utente alice
sudo -u alice ./olms-bootstrap.sh
sudo -u alice ./olms-orchestrator.sh --test

# Utente bob
sudo -u bob ./olms-bootstrap.sh
sudo -u bob ./olms-orchestrator.sh --test
```

## File Modificati

### Script Principali
- `olms-orchestrator.sh` - Script principale con gestione intelligente sudo
- `phase0-audio-cleanup.sh` - Cleanup audio con gestione intelligente sudo

### Script Secondari (aggiornati con sed)
- Tutti gli script nella cartella Startup2 hanno variabili universali

### Nuovi File
- `olms-bootstrap.sh` - Script di configurazione universale
- `UNIVERSAL_SYSTEM_GUIDE.md` - Questa guida

## Vantaggi del Sistema Universale

✅ **Multi-utente**: Funziona con qualsiasi utente Linux  
✅ **Sudo Compatibility**: Gestisce correttamente l'esecuzione con sudo  
✅ **Auto-configurazione**: Bootstrap script configura automaticamente il sistema  
✅ **Documentazione**: Guida completa per l'uso e la configurazione  
✅ **Manutenzione**: Facile da aggiornare e mantenere  

## Prossimi Passi Consigliati

1. **Test su diversi utenti** per verificare la compatibilità
2. **Documentazione aggiuntiva** per casi d'uso specifici
3. **Integrazione con PKGBUILD** per la distribuzione
4. **Test su diverse distribuzioni Linux**

## Risoluzione Problemi Comuni

### Problema: "Impossibile creare file di log"
**Causa**: Permessi insufficienti quando eseguito con sudo  
**Soluzione**: Il sistema ora gestisce automaticamente questo caso

### Problema: "Utente non nel gruppo audio"
**Causa**: Configurazione mancante  
**Soluzione**: Eseguire `./olms-bootstrap.sh` come root

### Problema: "Permessi USB negati"
**Causa**: Regole udev non configurate  
**Soluzione**: Eseguire `./olms-bootstrap.sh` come root

## Contatto e Supporto

Per problemi o domande:
- Controllare prima questo documento
- Verificare che `./olms-bootstrap.sh` sia stato eseguito
- Controllare i log in `~/.olms/olms-orchestrator.log`