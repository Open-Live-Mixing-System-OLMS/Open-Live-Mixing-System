# OLMS Core - Manual Installation Guide (Arch Linux)

This guide covers the installation of system dependencies, the graphical environment (XFCE4), and the deployment of the OLMS Core engine.

## 1. Prerequisites

Before proceeding, ensure you are running a **Real-Time Kernel**.
*Check your kernel version:*

```bash
uname -r
# Output should contain "rt" (e.g., 6.14.0-rt3-arch1-6-rt)

```

*If not installed, install it via AUR or unofficial repositories (like `archlinux-proaudio`), or compile it.*

## 2. System & Environment Installation

We will install the packages in logical groups. This setup ensures you have the audio core, a lightweight graphical environment for manual maintenance, and the necessary headless tools for OLMS.

### 2.1 Update System & Base Tools

Basic utilities for hardware detection, version control, and system management.

```bash
sudo pacman -Syu --needed --noconfirm \
    git \
    wget \
    usbutils \
    pciutils \
    util-linux \
    systemd

```

### 2.2 Audio Core Stack (JACK & Ardour)

The core audio engine, mixing console, and bridges.
*Note: We prioritize PulseAudio-JACK bridging as per the specific setup requirements.*

```bash
sudo pacman -S --needed --noconfirm \
    alsa-utils \
    alsa-plugins \
    jack2 \
    jack2-dbus \
    jack-example-tools \
    qjackctl \
    ardour \
    pulseaudio \
    pulseaudio-alsa \
    pulseaudio-jack \
    libpipewire \
    pipewire

```

### 2.3 Graphical Environment (XFCE4 & X11)

This provides a lightweight desktop for manual interaction (`_olms-launcher-test.sh`) and the X11 server required for both GUI and Headless operations (`xvfb`).

```bash
sudo pacman -S --needed --noconfirm \
    xorg-server \
    xorg-server-common \
    xorg-server-xvfb \
    xorg-xinit \
    xorg-xauth \
    xorg-xhost \
    xorg-xset \
    xfce4-session \
    xfce4-panel \
    xfce4-settings \
    xfce4-terminal \
    xfce4-appfinder \
    xfce4-power-manager \
    xfce4-notifyd \
    libxfce4ui \
    polkit-gnome \
    gnome-themes-extra \
    qt5-base \
    qt5-svg

```

## 3. OLMS Core Deployment

Clone the repository into your preferred projects directory.

```bash
# Create directory (universal path)
mkdir -p "$HOME/Projects"

# Clone Repository
cd "$HOME/Projects"
git clone https://github.com/Open-Live-Mixing-System-OLMS/Open-Live-Mixing-System OLMS-Core

# Enter the directory
cd OLMS-Core

```

## 4. Environment Configuration (Bootstrap)

Run the bootstrap script. This handles the complex configuration:

* Real-time limits (`ulimit`, `rtprio`)
* Group creation (`audio`, `realtime`)
* Udev rules (USB permissions, CPU governor tuning)
* Shared memory permissions for JACK

```bash
# Make scripts executable
chmod +x Startup/*.sh

# Run the bootstrap (requires sudo)
sudo ./Startup/setup-env.sh

```

## 5. Final Verification

**Important:** You must **Reboot** or **Log out/Log in** for group permissions and limits to take effect.

After rebooting, run these commands to verify the system is ready:

```bash
# 1. Check Groups (Must include 'audio' and 'realtime')
groups

# 2. Check Real-Time Priority (Should be 95 or 99)
ulimit -r

# 3. Check Memory Lock (Should be unlimited)
ulimit -l

```

---

## 6. Launching OLMS

There are two distinct launch modes depending on your needs.

### Mode A: Testing & GUI (Use First)

Use this launcher to verify that Ardour starts correctly, plugins load, and audio routing works visually. This requires the graphical environment (XFCE/X11) to be running.

**Option A1: Command Line**
```bash
# If you are in a TTY, start the GUI first:
# startxfce4

# Then run:
"$HOME/Projects/OLMS-Core/Startup/_olms-launcher-test.sh"

```

**Option A2: Desktop File (Double-Click)**
- Double-click `_olms-launcher-test.desktop` for GUI monitoring
- This opens a terminal window and runs the test launcher automatically

### Mode B: Production & Headless

Use this launcher for the actual live mixing system. It uses `Xvfb` (Virtual Framebuffer) to run Ardour without a physical monitor, optimized for performance.

**Option B1: Command Line**
```bash
"$HOME/Projects/OLMS-Core/Startup/_olms-launcher.sh"

```

**Option B2: Desktop File (Double-Click)**
- Double-click `_olms-launcher.desktop` for headless operation
- This opens a terminal window and runs the production launcher automatically

### Mode C: Latency Testing

**Option C1: Command Line**
```bash
"$HOME/Projects/OLMS-Core/test/olms-latency-test.sh"

```

**Option C2: Desktop File (Double-Click)**
- Double-click `_olms-latency-test.desktop` to measure system performance
- This opens a terminal window and runs the latency test automatically
