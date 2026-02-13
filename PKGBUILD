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

# Maintainer: Francesco Nano <francesco.nano@openlivemixingsystem.org>
pkgname=olms-core
pkgver=0.1.0
pkgrel=1
install=olms.install
pkgdesc="Open Live Mixing System core files and scripts"
arch=('any')
url="https://github.com/Open-Live-Mixing-System-OLMS/Open-Live-Mixing-System"
license=('GPLv3')
groups=()
depends=(
    'alsa-utils'        # aplay, arecord, amixer
    'ardour'           # DAW principale
    'jack2'            # Server audio JACK
    'jack2-dbus'       # JACK con D-Bus
    'jack-example-tools' # jack_lsp, jack_wait
    'qjackctl'         # Controllo JACK
    'xorg-server-xvfb' # Virtual framebuffer per headless
    'xorg-xauth'       # Autorizzazioni X11
    'xorg-xhost'       # Controllo accesso X11
    'systemd'          # Gestione servizi
    'pipewire'         # Per disabilitare PipeWire
    'pulseaudio'       # Per disabilitare PulseAudio
    'git'              # Per clonare repository
    'lsusb'            # Per rilevamento dispositivi USB
    'lspci'            # Per rilevamento hardware
    'util-linux'       # Per ipcs/ipcrm gestione shared memory
)
optdepends=(
    'qjackctl: GUI controllo JACK'
    'pipewire-jack: Bridge PipeWire-JACK (opzionale)'
)
makedepends=()
checkdepends=(
    'jack_delay: Test di latenza JACK'
)
source=()
# OLMS è una collezione di script e configurazioni
# I file vengono gestiti tramite il progetto git
sha256sums=('SKIP')

prepare() {
    # Nessuna sorgente da estrarre
}

package() {
    # Creazione directory di destinazione
    install -d "${pkgdir}/usr/bin"
    install -d "${pkgdir}/usr/lib/${pkgname}"
    install -d "${pkgdir}/usr/share/${pkgname}"
    install -d "${pkgdir}/etc/${pkgname}"
    install -d "${pkgdir}/usr/share/doc/${pkgname}"

    # Copia script essenziali in /usr/bin
    install -m755 scripts/rt_tuning.sh "${pkgdir}/usr/bin/"
    install -m755 scripts/audio_virtual.sh "${pkgdir}/usr/bin/"
    install -m755 scripts/audio_engine.sh "${pkgdir}/usr/bin/ardour_launcher"
    install -m755 scripts/olms-startup.sh "${pkgdir}/usr/bin/olms-startup"
    install -m755 scripts/olms-test-launcher.sh "${pkgdir}/usr/bin/olms-test-launcher"
    install -m755 scripts/olms-prod-launcher.sh "${pkgdir}/usr/bin/olms-prod-launcher"
    install -m755 scripts/prepare_machine.sh "${pkgdir}/usr/bin/prepare_machine"
    install -m755 scripts/disk_guard.sh "${pkgdir}/usr/bin/"
    install -m755 scripts/olms-apply-affinity.sh "${pkgdir}/usr/bin/olms-apply-affinity"
    install -m755 scripts/irq_pinning.sh "${pkgdir}/usr/bin/irq_pinning"
    install -m755 scripts/cpu_shielding.sh "${pkgdir}/usr/bin/cpu_shielding"
    install -m755 scripts/setup_realtime_privileges.sh "${pkgdir}/usr/bin/setup_realtime_privileges"
    install -m755 scripts/usb_audio_session_adapter.sh "${pkgdir}/usr/bin/usb_audio_session_adapter"
    
    # Copia script di test latenza
    install -m755 scripts/olms-latency-test.sh "${pkgdir}/usr/bin/olms-latency-test"
    install -m755 scripts/olms-alsa-latency-test.sh "${pkgdir}/usr/bin/olms-alsa-latency-test"
    
    # Copia script JACK socket permissions
    install -m755 Startup2/phase3-jack-init.sh "${pkgdir}/usr/bin/olms-jack-init"
    install -m755 Startup2/phase5-ardour-startup.sh "${pkgdir}/usr/bin/olms-ardour-startup"
    install -m755 Startup2/test_jack_stability.sh "${pkgdir}/usr/bin/olms-test-jack-stability"
    
    # Copia script ottimizzazione JACK
    install -m755 Startup2/phase3-jack-init-fixed.sh "${pkgdir}/usr/bin/olms-jack-init-fixed"
    install -m755 Startup2/fix_jack_links.sh "${pkgdir}/usr/bin/olms-fix-jack-links"
    install -m755 Startup2/jack_system_reset.sh "${pkgdir}/usr/bin/olms-jack-system-reset"
    install -m755 Startup2/olms-jack-setup.sh "${pkgdir}/usr/bin/olms-jack-setup"

    # Copia file configurazione
    install -d "${pkgdir}/etc/security/limits.d/"
    install -m644 config/realtime/99-realtime.conf "${pkgdir}/etc/security/limits.d/99-realtime.conf"
    
    # Copia file servizi systemd
    install -d "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-rt-tuning.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-irq-pinning.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/ardour.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-affinity.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-disk-guard.service "${pkgdir}/etc/systemd/system/"
    
    # Copia configurazione systemd user per privilegi realtime
    install -d "${pkgdir}/etc/systemd/user.conf.d/"
    install -m644 config/systemd/user.conf.d/10-olms-realtime.conf "${pkgdir}/etc/systemd/user.conf.d/10-olms-realtime.conf"
    
    # Copia script override realtime
    install -m755 scripts/olms-rt-override.sh "${pkgdir}/usr/bin/olms-rt-override"
    
    # Rende script eseguibili
    chmod +x "${pkgdir}/usr/bin/olms-rt-override"

    # Copia struttura progetto (engine, ui) in /usr/lib/${pkgname}
    cp -r engine "${pkgdir}/usr/lib/${pkgname}/"
    cp -r ui "${pkgdir}/usr/lib/${pkgname}/"

    # Copia specifiche in documentazione
    install -m644 OLMS_specs.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 x-console_specs.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 README.md "${pkgdir}/usr/share/doc/${pkgname}/"

    # Crea directory per configurazione auth.json
    install -d "${pkgdir}/etc/olms/"
    # Un auth.json iniziale o placeholder andrebbe qui
    # install -m644 /path/to/local/auth.json "${pkgdir}/etc/olms/auth.json"
}

