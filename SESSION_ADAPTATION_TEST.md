# Session Adaptation Test - OLMS

## Overview
Documentazione e procedure di test per verificare il corretto funzionamento del Session Adaptation in OLMS.

## Problema Identificato
Il Session Adaptation ha mostrato un **falso positivo**: ha riportato "Sessione adattata correttamente" ma non ha effettivamente modificato il file XML della sessione perché le porte erano già corrette.

## Cosa Fa il Session Adaptation

### 1. Rilevamento Porte JACK
- Esegue `jack_lsp` per trovare porte disponibili
- Estrae porte capture e playback
- Conta le porte disponibili

### 2. Backup Sessione
- Crea backup della sessione originale
- Salva come `OLMS-POC.ardour.backup`

### 3. Adattamento Sessione
- Sostituisce i nomi delle porte nel file XML
- Pattern di sostituzione:
  - `system:capture_1` → porta capture rilevata
  - `system:playback_1` → porta playback 1 rilevata
  - `system:playback_2` → porta playback 2 rilevata

### 4. Ricarica Ardour
- Termina Ardour
- Sostituisce il file sessione
- Riavvia Ardour con sessione aggiornata

## Test da Eseguire

### Test 1: Verifica Base
```bash
# 1. Controlla porte JACK attuali
sudo -u francesco_ssh env PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1 jack_lsp 2>/dev/null | grep "^system:"

# 2. Esegui Session Adaptation
bash /home/francesco_ssh/Progetti/OLMS-Core/Startup2/phase5-ardour-startup.sh

# 3. Verifica modifiche al file
diff /home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour.backup /home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour

# 4. Controlla connessioni finali
grep -E "other=\"system:" /home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour
```

### Test 2: Con Scheda Audio Diversa
**Condizione necessaria**: Avere due schede audio diverse (es. Behringer UMC22 e Focusrite Scarlett Solo)

1. **Configurazione Iniziale**:
   - Collegare Scheda A (es. Behringer UMC22)
   - Avviare OLMS
   - Verificare che il Session Adaptation crei una sessione per la Scheda A

2. **Test di Cambio Scheda**:
   - Scollegare Scheda A
   - Collegare Scheda B (es. Focusrite Scarlett Solo)
   - Riavviare OLMS
   - Verificare che il Session Adaptation:
     - Rilevi le nuove porte della Scheda B
     - Modifichi effettivamente il file XML
     - Aggiorni le connessioni alle nuove porte

3. **Verifica Finale**:
   - Controllare che le connessioni nel file XML puntino alle porte della Scheda B
   - Verificare che Ardour funzioni correttamente con la nuova scheda

### Test 3: Log Dettagliati
```bash
# Abilita logging dettagliato
export OLMS_DEBUG=1

# Esegui Session Adaptation con logging
bash /home/francesco_ssh/Progetti/OLMS-Core/Startup2/phase5-ardour-startup.sh 2>&1 | tee /tmp/session_adaptation_debug.log

# Analizza il log
grep -E "(Rilevamento|Backup|Adattamento|Sostituzioni|Reload)" /tmp/session_adaptation_debug.log
```

## Casi di Test Specifici

### Caso 1: Porte Identiche (Falso Positivo)
**Scenario**: La sessione è già configurata per le porte attualmente disponibili
**Aspettativa**: Nessuna modifica al file XML, ma messaggio "Sessione adattata correttamente"
**Problema**: Non è chiaro se la sessione sia effettivamente adatta alla scheda corrente

### Caso 2: Porte Diverse (Adattamento Reale)
**Scenario**: La sessione è configurata per una scheda diversa da quella attualmente collegata
**Aspettativa**: Modifica effettiva del file XML con nuove connessioni
**Verifica**: Differenze nel file XML e connessioni aggiornate

### Caso 3: Scheda Non Rilevata
**Scenario**: Nessuna scheda audio rilevata
**Aspettativa**: Messaggio di errore e fallback alla sessione originale
**Verifica**: Nessuna modifica al file XML e sessione originale ripristinata

## Miglioramenti Proposti

### 1. Logging Migliorato
Aggiungere messaggi più chiari per distinguere:
- Sessione già corretta (nessuna modifica necessaria)
- Sessione effettivamente adattata (modifiche apportate)
- Errore di rilevamento (fallback)

### 2. Identificazione Scheda
Implementare un sistema per identificare univocamente la scheda audio collegata:
- ID hardware della scheda
- Nome del dispositivo ALSA
- Timestamp di rilevamento

### 3. Test Automatico
Creare uno script di test automatico che:
- Rilevi la scheda attualmente collegata
- Verifichi se la sessione è configurata per quella scheda
- Esegua il Session Adaptation solo se necessario
- Generi un report dettagliato

## File da Monitorare

### File Sessione
- `/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour`
- `/home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour.backup`

### Log
- `/tmp/olms-ardour-startup.log`
- Output dello script phase5-ardour-startup.sh

### Connessioni JACK
- Output di `jack_lsp -c`
- File `/dev/shm/jack_olms_0`

## Comandi Utili

### Verifica Porte JACK
```bash
# Porte disponibili
sudo -u francesco_ssh env PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1 jack_lsp 2>/dev/null | grep "^system:"

# Connessioni attive
sudo -u francesco_ssh env PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin JACK_DEFAULT_SERVER=olms JACK_PROMISCUOUS_SERVER=1 JACK_NO_START_SERVER=1 jack_lsp -c 2>/dev/null | grep -E "(capture|playback)"
```

### Verifica Sessione
```bash
# Connessioni nella sessione
grep -E "other=\"system:" /home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour

# Differenze con backup
diff /home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour.backup /home/francesco_ssh/Progetti/OLMS-Core/engine/session-template/OLMS-POC/OLMS-POC.ardour
```

### Identificazione Scheda
```bash
# Schede audio disponibili
aplay -l

# Dispositivi ALSA
cat /proc/asound/cards

# Dettagli hardware USB
lsusb | grep -i audio
```

## Conclusioni
Il Session Adaptation è funzionante ma necessita di:
1. **Test con schede diverse** per verificare l'adattamento reale
2. **Miglioramento del logging** per distinguere i casi
3. **Sistema di identificazione scheda** per evitare falsi positivi
4. **Test automatico** per verifiche rapide

**Prossimi passi**: Attendere la disponibilità della Focusrite Scarlett Solo per eseguire il test completo con schede diverse.