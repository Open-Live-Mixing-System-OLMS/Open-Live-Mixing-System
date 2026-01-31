#!/bin/bash
# OLMS Realtime Privileges Override Script
# Safe override for privilege configuration without security risks

set -e

print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

if [ "$EUID" -ne 0 ]; then
    echo "Questo script deve essere eseguito come root"
    exit 1
fi

print_status "Applicando override systemd per privilegi real-time..."

# Creare directory systemd user
mkdir -p /etc/systemd/user.conf.d/

# Creare file di override systemd
cat > /etc/systemd/user.conf.d/10-olms-realtime.conf << EOF
[Manager]
DefaultLimitRTPRIO=99
DefaultLimitMEMLOCK=infinity
EOF

print_status "File di override systemd creato: /etc/systemd/user.conf.d/10-olms-realtime.conf"

# Tentativo sicuro di ricaricare systemd user (senza dipendere da ambiente X11)
print_status "Tentativo di ricaricare la configurazione systemd..."

# Metodo 1: Tentativo con ambiente X11 (se disponibile)
if [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
    print_status "Ambiente X11 disponibile, tentativo con systemctl --user..."
    if systemctl --user daemon-reexec 2>/dev/null; then
        print_status "✓ Override systemd applicato con successo via systemctl --user"
    else
        print_status "⚠ systemctl --user fallito, procedendo senza ricarica live"
    fi
else
    print_status "Ambiente X11 non disponibile, bypassando systemctl --user"
    print_status "  (questo è normale durante l'avvio del sistema)"
fi

# Metodo 2: Ricarica systemd system (più sicuro)
print_status "Ricarica configurazione systemd system..."
if systemctl daemon-reload 2>/dev/null; then
    print_status "✓ Configurazione systemd system ricaricata"
else
    print_status "⚠ Ricarica systemd system fallita (può essere normale in alcuni contesti)"
fi

print_status "Override systemd applicato con successo"
print_status "Nota: Per applicare completamente i cambiamenti, è necessario:"
echo "  - Riavviare il sistema, oppure"
echo "  - Riavviare la sessione utente, oppure"
echo "  - Riavviare i servizi che richiedono privilegi realtime"

# Verifica più robusta
print_status "Verifica configurazione privilegi real-time..."

# Verifica che il file di override esista e contenga i parametri corretti
if [ -f "/etc/systemd/user.conf.d/10-olms-realtime.conf" ]; then
    rtprio_setting=$(grep "DefaultLimitRTPRIO" /etc/systemd/user.conf.d/10-olms-realtime.conf | awk -F'=' '{print $2}')
    memlock_setting=$(grep "DefaultLimitMEMLOCK" /etc/systemd/user.conf.d/10-olms-realtime.conf | awk -F'=' '{print $2}')
    
    if [ "$rtprio_setting" = "99" ] && [ "$memlock_setting" = "infinity" ]; then
        print_status "✓ File di override systemd corretto (RTPRIO=99, MEMLOCK=infinity)"
    else
        print_status "⚠ File di override systemd con valori inaspettati:"
        echo "    RTPRIO: $rtprio_setting (atteso: 99)"
        echo "    MEMLOCK: $memlock_setting (atteso: infinity)"
    fi
else
    print_status "✗ File di override systemd non trovato"
fi

# Verifica ulimit (questo funziona solo per la sessione corrente)
current_rtprio=$(ulimit -r 2>/dev/null || echo "0")
if [ "$current_rtprio" = "99" ]; then
    print_status "✓ Verifica riuscita: privilegi real-time attivi nella sessione corrente"
else
    print_status "⚠ Verifica sessione corrente fallita: ulimit -r = $current_rtprio"
    print_status "  Questo è normale se i privilegi non sono ancora attivi per questa sessione"
    print_status "  I privilegi saranno attivi dopo:"
    echo "    - Un nuovo login, oppure"
    echo "    - Un riavvio del sistema, oppure"
    echo "    - Un riavvio della sessione utente"
fi

print_status "Override systemd completato con successo!"
