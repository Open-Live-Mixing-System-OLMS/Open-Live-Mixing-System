# Maintainer: Your Name <you@example.com>
pkgname=olms-core
pkgver=0.1.0 # Define or extract dynamically if possible
pkgrel=1
pkgdesc="Open Live Mixing System core files and scripts"
arch=('any') # or 'x86_64' if there are specific binaries
url="https://github.com/Open-Live-Mixing-System-OLMS/Open-Live-Mixing-System" # Project URL
license=('GPLv3') # GPLv3 License as per specifications
groups=()
depends=(
    'alsa-utils'
    'ardour'
    'jack-example-tools'
    'pulseaudio-jack'
    'qjackctl'
    'nodejs'
    'npm'
    'git'
    'openssh'
    'libxcrypt-compat'
    'icu'
    'tar'
    'wget'
    'dkms'
    'r8168-dkms'
    'r8168'
    'libffado'
    'xorg-server-xvfb'  # Required for headless Ardour in production mode
)
optdepends=(
    # Specifications mention Open Stage Control as web interface
    # Example: 'open-stage-control: for the web interface'
)
makedepends=(
    # makedepends if there are sources to compile
)
checkdepends=(
    # dependencies for tests, e.g. jack_iodelay, jack_latency_test
)
source=(
    # OLMS is a collection of scripts and configurations, not a single tarball for now.
    # The user should manage cloning or copying project files.
    # For a real PKGBUILD, one should specify how to obtain these files.
    # Example for local scripts:
    # 'scripts/rt_tuning.sh'
    # 'scripts/audio_virtual.sh'
    # 'scripts/ardour_launcher.sh'
    # 'scripts/disk_guard.sh'
    # Other project contents if necessary
)
sha256sums=('SKIP') # Use with caution; for production, generate real hashes.

prepare() {
    # No sources to extract here if the files are already on the FS.
}

build() {
    # No sources to compile at this time.
}

package() {
    # Create destination directories
    install -d "${pkgdir}/usr/bin"
    install -d "${pkgdir}/usr/lib/${pkgname}"
    install -d "${pkgdir}/usr/share/${pkgname}"
    install -d "${pkgdir}/etc/${pkgname}"
    install -d "${pkgdir}/usr/share/doc/${pkgname}"

    # Copy essential scripts to /usr/bin as per x-console_specs.md
    install -m755 scripts/rt_tuning.sh "${pkgdir}/usr/bin/"
    install -m755 scripts/audio_virtual.sh "${pkgdir}/usr/bin/"
    install -m755 scripts/ardour_launcher.sh "${pkgdir}/usr/bin/"
    install -m755 scripts/disk_guard.sh "${pkgdir}/usr/bin/"
    install -m755 scripts/olms-apply-affinity.sh "${pkgdir}/usr/bin/olms-apply-affinity"
    install -m755 scripts/cpu_shielding.sh "${pkgdir}/usr/bin/cpu_shielding"
    install -m755 scripts/setup_realtime_privileges.sh "${pkgdir}/usr/bin/setup_realtime_privileges"

    # Copy configuration files
    install -d "${pkgdir}/etc/security/limits.d/"
    install -m644 config/realtime/99-realtime.conf "${pkgdir}/etc/security/limits.d/99-realtime.conf"
    
    # Copy systemd service files
    install -d "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-rt-tuning.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-irq-pinning.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/ardour.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-affinity.service "${pkgdir}/etc/systemd/system/"
    install -m644 systemd/olms-disk-guard.service "${pkgdir}/etc/systemd/system/"

    # Copy project structure (engine, ui) to /usr/lib/${pkgname}
    cp -r engine "${pkgdir}/usr/lib/${pkgname}/"
    cp -r ui "${pkgdir}/usr/lib/${pkgname}/"

    # Copy specifications to documentation
    install -m644 OLMS_specs.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 x-console_specs.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 README.md "${pkgdir}/usr/share/doc/${pkgname}/"

    # Create directory for auth.json configuration as per OLMS_specs.md
    install -d "${pkgdir}/etc/olms/"
    # An initial auth.json or placeholder would go here
    # install -m644 /path/to/local/auth.json "${pkgdir}/etc/olms/auth.json"
}

# Post-installation script
post_install() {
    echo "OLMS Core installation completed!"
    echo ""
    echo "IMPORTANT: Realtime Privileges Configuration"
    echo "============================================="
    echo ""
    echo "OLMS requires proper realtime privileges for optimal audio performance."
    echo "The following configuration has been installed:"
    echo ""
    echo "1. Realtime privileges configuration file:"
    echo "   /etc/security/limits.d/99-realtime.conf"
    echo ""
    echo "2. To complete the setup, run:"
    echo "   sudo setup_realtime_privileges"
    echo ""
    echo "This will:"
    echo "  - Create the 'audio' and 'realtime' groups if they don't exist"
    echo "  - Add the current user to both groups"
    echo "  - Verify the configuration is working correctly"
    echo ""
    echo "3. After running the setup script, you MUST log out and log back in"
    echo "   for the group changes to take effect."
    echo ""
    echo "4. Verify the configuration:"
    echo "   ulimit -r    # Should show 99"
    echo "   ulimit -l    # Should show unlimited"
    echo "   groups       # Should include 'audio' and 'realtime'"
    echo ""
    echo "5. Enable and start OLMS services:"
    echo "   sudo systemctl enable olms-rt-tuning.service"
    echo "   sudo systemctl enable olms-irq-pinning.service"
    echo "   sudo systemctl enable ardour.service"
    echo "   sudo systemctl enable olms-affinity.service"
    echo "   sudo systemctl enable olms-disk-guard.service"
    echo ""
    echo "For more information, see:"
    echo "  - OLMS_specs.md for detailed documentation"
    echo "  - setup-env.sh for manual setup instructions"
    echo ""
}

# Post-upgrade script
post_upgrade() {
    post_install
}

# Post-removal script
post_remove() {
    echo "OLMS Core has been removed."
    echo ""
    echo "Note: User groups and realtime configuration files have been preserved."
    echo "If you no longer need them, you can remove them manually:"
    echo "  sudo groupdel audio"
    echo "  sudo groupdel realtime"
    echo "  sudo rm /etc/security/limits.d/99-realtime.conf"
    echo ""
}
