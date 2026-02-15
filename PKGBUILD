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
pkgrel=1
install=olms.install
pkgdesc="Open Live Mixing System core files and scripts"
arch=('any')
url="https://github.com/Open-Live-Mixing-System-OLMS/Open-Live-Mixing-System"
license=('GPLv3' 'AGPLv3')
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
    install -m755 Startup/phase0-audio-cleanup.sh "${pkgdir}/usr/bin/olms-phase0-audio-cleanup"
    install -m755 Startup/phase0-lock-management.sh "${pkgdir}/usr/bin/olms-phase0-lock-management"
    install -m755 Startup/phase1-rt-optimization.sh "${pkgdir}/usr/bin/olms-phase1-rt-optimization"
    install -m755 Startup/phase2-hardware-config.sh "${pkgdir}/usr/bin/olms-phase2-hardware-config"
    install -m755 Startup/phase3-jack-init-fixed.sh "${pkgdir}/usr/bin/olms-phase3-jack-init-fixed"
    install -m755 Startup/phase4-x11-setup.sh "${pkgdir}/usr/bin/olms-phase4-x11-setup"
    install -m755 Startup/phase5-ardour-startup.sh "${pkgdir}/usr/bin/olms-phase5-ardour-startup"
    install -m755 Startup/phase6-final-report.sh "${pkgdir}/usr/bin/olms-phase6-final-report"
    install -m755 Startup/_olms-launcher.sh "${pkgdir}/usr/bin/olms-launcher"
    install -m755 Startup/olms-orchestrator.sh "${pkgdir}/usr/bin/olms-orchestrator"
    install -m755 Startup/olms-unified-startup.sh "${pkgdir}/usr/bin/olms-unified-startup"
    install -m755 Startup/olms-system-monitor.sh "${pkgdir}/usr/bin/olms-system-monitor"
    install -m755 Startup/olms-runtime-permissions.sh "${pkgdir}/usr/bin/olms-runtime-permissions"
    install -m755 Startup/olms-path-utils.sh "${pkgdir}/usr/bin/olms-path-utils"
    install -m755 Startup/fix_jack_links.sh "${pkgdir}/usr/bin/olms-fix-jack-links"
    install -m755 Startup/jack_system_reset.sh "${pkgdir}/usr/bin/olms-jack-system-reset"
    install -m755 Startup/olms-jack-setup.sh "${pkgdir}/usr/bin/olms-jack-setup"
    install -m755 Startup/olms-jack-force-init.sh "${pkgdir}/usr/bin/olms-jack-force-init"
    install -m755 Startup/jack_connectivity_test.sh "${pkgdir}/usr/bin/olms-jack-connectivity-test"
    install -m755 Startup/audio_output_diagnostic.sh "${pkgdir}/usr/bin/olms-audio-output-diagnostic"
    install -m755 Startup/test_jack_detection.sh "${pkgdir}/usr/bin/olms-test-jack-detection"
    install -m755 Startup/test_jack_ardour_fixes.sh "${pkgdir}/usr/bin/olms-test-jack-ardour-fixes"
    install -m755 Startup/test_jack_stability.sh "${pkgdir}/usr/bin/olms-test-jack-stability"
    install -m755 Startup/test_session_adaptation.sh "${pkgdir}/usr/bin/olms-test-session-adaptation"
    install -m755 Startup/test_variables.sh "${pkgdir}/usr/bin/olms-test-variables"
    install -m755 test/olms-latency-test.sh "${pkgdir}/usr/bin/olms-latency-test"

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
    install -m755 Startup/olms-rt-override.sh "${pkgdir}/usr/bin/olms-rt-override"
    
    # Rende script eseguibili
    chmod +x "${pkgdir}/usr/bin/olms-rt-override"

    # Copia struttura progetto (engine) in /usr/lib/${pkgname}
    cp -r engine "${pkgdir}/usr/lib/${pkgname}/"

    # Copia specifiche in documentazione
    install -m644 OLMS_specs.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 x-console_specs.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 README.md "${pkgdir}/usr/share/doc/${pkgname}/"

    # Crea directory per configurazione auth.json
    install -d "${pkgdir}/etc/olms/"
    # Un auth.json iniziale o placeholder andrebbe qui
    # install -m644 /path/to/local/auth.json "${pkgdir}/etc/olms/auth.json"
}

