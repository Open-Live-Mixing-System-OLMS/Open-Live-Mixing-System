# Open Live Mixing System (OLMS)

[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Status](https://img.shields.io/badge/Status-PoC%20Phase%201-green.svg)](./issues/1)
[![Sample Rate](https://img.shields.io/badge/Sample%20Rate-48%20kHz-orange.svg)]()
[![RTL Target](https://img.shields.io/badge/RTL%20Target-%3C%205ms%20(Goal)-brightgreen.svg)]()
[![Stability](https://img.shields.io/badge/Stability-<2%20X--runs/hour-orange.svg)]()

**OLMS:** The Open Live Mixing System. A project aimed at transforming any compatible Mini-PC into a professional, dedicated digital mixing console. Built on a Real-Time Linux core, Ardour Headless, and JACK2/ALSA, it targets a Round-Trip Latency (RTL) of less than $< 5 \text{ ms}$ and **<2 X-runs/hour**. 

**Current Phase:** Engine-only POC with Ardour interface for performance testing. **No web interface yet** - this is pure audio engine development.

**Official Website:** 👉 [https://openlivemixingsystem.org/](https://openlivemixingsystem.org/)
**Telegram Channel:** 👉 [https://web.telegram.org/a/#-1003532216403](https://web.telegram.org/a/#-1003532216403)

---

## 🛣️ Project Roadmap

OLMS follows a structured development roadmap with clear milestones. We are currently in **Phase 1: Engine POC**.

### Phase 1: Engine POC (Current Phase) ⚠️ IN PROGRESS

**⚠️ ATTENTION: WE ARE LOOKING FOR TESTERS AND DEVELOPERS! ⚠️**

**Important:** OLMS scripts were created by **Francesco Nano** with AI assistance. Francesco is neither a developer nor a system administrator, so **your help is essential** to:
- **Review** the code and logic of the scripts
- **Optimize** configurations and processes
- **Test** on different hardware configurations
- **Improve** reliability and performance

**We are looking for competent and skilled people** who want to contribute to the development of an open-source project for live music.

**📍 Official Telegram Channel:** 👉 [https://web.telegram.org/a/#-1003532216403](https://web.telegram.org/a/#-1003532216403)

**Objective:** Create a portable, high-performance audio engine that can be deployed on any compatible PC.

**Status:** ✅ **IN PROGRESS** - Portability testing on multiple PCs
**Focus:** Pure audio engine performance and stability
**Interface:** Ardour GUI only (for testing and debugging)
**Current Implementation:** Sequential script-based startup system optimized for debugging and development
**Startup Approach:** Currently uses sequential scripts that run one after another, providing excellent debugging capabilities but slower startup times. This setup is optimal for development and troubleshooting but needs optimization for production use.
**Key Goals:**
- [ ] Achieve < 5ms RTL on multiple hardware configurations
- [ ] Maintain < 2 X-runs/hour under full load
- [ ] Portability across different PCs and audio interfaces
- [ ] Stable RT kernel configuration
- [ ] Comprehensive performance validation

**What You Get Now:**
- Proof of Concept session with 1 channel for concept testing
- Real-time optimized Linux configuration
- JACK2/ALSA audio server with optimal settings
- Ardour DAW with basic template
- Performance monitoring and latency testing tools
- **No web interface yet** - this is engine-only development
- **Sequential startup scripts** - currently optimized for debugging and development, not for fast production startup

**Testing Instructions:**
```bash
# Launch in test mode to see Ardour interface
./_olms-launcher-test.sh

# Measure performance
./test/olms-latency-test.sh


### Phase 2: OSC Controller & Web Interface
**Objective:** Add OSC communication layer and basic web interface for remote control.

**Prerequisites:** Phase 1 completion and validation
**Focus:** OSC bridge server and responsive web UI
**Interface:** Web browser interface with OSC communication
**Key Goals:**
- [ ] OSC bridge server implementation
- [ ] Basic web interface for fader control
- [ ] OSC communication with Ardour
- [ ] Touch-friendly responsive design
- [ ] Network control via Wi-Fi

### Phase 3: Digital I/O Expansion (AoIP AES67)
**Objective:** Add professional digital audio networking capabilities.

**Prerequisites:** Phase 2 completion
**Focus:** AES67/AoIP integration for professional audio networks
**Interface:** Web interface with network I/O management
**Key Goals:**
- [ ] AES67 protocol implementation
- [ ] Network audio device discovery
- [ ] Multi-device synchronization
- [ ] Professional audio network integration
- [ ] Scalable I/O expansion

### Phase 4: Advanced Features & Optimization
**Objective:** Add professional features and optimize for production use.

**Prerequisites:** Phase 3 completion
**Focus:** Professional features and production optimization
**Interface:** Complete web interface with advanced features
**Key Goals:**
- [ ] Anti-feedback system
- [ ] Live auto-mixer
- [ ] Advanced routing matrix
- [ ] Scene management and automation
- [ ] Production-ready stability and performance

### Phase 5: Systemd Integration & Production Optimization
**Objective:** Replace sequential script-based startup with professional systemd services for faster, more reliable production startup.

**Prerequisites:** Phase 4 completion
**Focus:** Systemd service creation and production optimization
**Interface:** Full-featured web interface
**Key Goals:**
- [ ] Create systemd services for all OLMS components
- [ ] Implement parallel service startup for faster boot times
- [ ] Add proper service dependencies and ordering
- [ ] Implement production-grade logging and monitoring
- [ ] Optimize startup sequence for production environments

### Phase 6: Professional System Deployment & Documentation
**Objective:** Create professional deployment scripts and comprehensive documentation for building a complete mixer system with systemd-based startup.

**Prerequisites:** Phase 5 completion
**Focus:** Professional deployment automation and complete system documentation
**Interface:** Full-featured web interface
**Key Goals:**
- [ ] Create automated deployment scripts that generate systemd services
- [ ] Implement professional-grade system installation and configuration
- [ ] Build complete hardware selection and compatibility guide
- [ ] Develop step-by-step assembly and configuration instructions
- [ ] Create comprehensive troubleshooting and performance optimization documentation
- [ ] Establish production-ready deployment procedures

---

## 🎯 Current Development Status

**Phase 1 Priority:** Engine stability and performance across different hardware
**Current Focus:** Portability testing and performance validation
**Next Milestone:** Stable < 5ms RTL on 3+ different PC configurations
**Community Involvement:** Testing on different hardware configurations is crucial

**Important Note:** This is **engine-only development**. The web interface and OSC control come in Phase 2. Currently, you get a professional audio engine that you can test and validate using Ardour's interface.

---

## 🚀 Architecture Overview and Key Concepts

For detailed technical specifications, refer to the [OLMS Specifications](OLMS_specs.md) document.

OLMS is built on a Simplified 2-Layer Architecture that ensures stability and performance:

1.  **Web UI (Proprietary):** HTML5/JS/CSS-based user interface for controlling faders, mute, solo, pan, plugins, routing matrix, and metering.
2.  **Ardour Headless (GPL):** The main audio engine, configured with 48-channel templates (6 banks of 8 channels), bypassed plugins, and static routing. It integrates Lua Scripts for Session, Bank, Scene Management, and Dynamic I/O Patching.

### Block Track Management
The system supports multi-channel configurations via 8-track "banks." At startup, a script detects available physical ports and activates only the necessary banks (e.g., 16 I/O → Banks 1-2). Inactive banks have their tracks disabled in Ardour and hidden in the UI but can be activated at runtime via OSC. Pre-configured templates are available for 16ch, 24ch, 32ch, and 48ch.

### Real-Time Configuration and CPU Pinning
The system includes an advanced Real-Time (RT) kernel configuration. It focuses on simplifying IRQ pinning to a dedicated core for the audio card and using high RT priority for JACK/Ardour/Carla processes, rather than complex CPU core allocation. This also includes disabling features like Hyper-Threading and deep C-states to maximize stability and reduce latency.

---

## 🚀 Quick Start

### 0. Install OLMS (Arch Linux)

**Using PKGBUILD (Recommended for Arch Linux users):**

```bash
# Build and install the package
makepkg -si

# Or install from AUR (when available)
yay -S olms-core

# The installer will guide you through post-installation setup
# Follow the instructions displayed after installation
```

**Post-Installation Setup:**

After installation, the installer will automatically configure:
- Audio services optimization
- Realtime privileges setup
- JACK audio server configuration
- X11 authentication support

For detailed configuration options, see [OLMS Specifications](OLMS_specs.md).

**Bootstrap Method:**

```bash
# Run the bootstrap script for complete system configuration
sudo ./setup-env.sh

# Restart your user session (log out/in or reboot)
```

### 1. Launch OLMS

**For OLMS POC (Proof of Concept):**

```bash
# After setting up the environment with setup-env.sh, use the test launcher
# This will show Ardour GUI for visual monitoring and debugging
./_olms-launcher-test.sh

# Standard production startup (headless)
./_olms-launcher.sh

# Custom configuration (skip detection phases for faster startup)
OLMS_AUDIO_DEVICE="hw:1" OLMS_BUFFER_CONFIG="32:2" OLMS_BIT_DEPTH="24" ./_olms-launcher.sh
```

**Important for POC Testing:**
- Use `./_olms-launcher-test.sh` to see Ardour GUI
- This allows visual monitoring of the audio engine during testing
- Essential for debugging and latency measurement

**Fast Startup with Custom Configuration:**

For faster startup when you know your optimal audio settings, you can bypass the automatic detection phases by setting environment variables:

```bash
# Set your known audio configuration
OLMS_AUDIO_DEVICE="hw:1"        # Your audio device (find with: aplay -l)
OLMS_BUFFER_CONFIG="64:3"       # Buffer size:periods (e.g., 64:3, 32:2, 128:2)
OLMS_BIT_DEPTH="32"            # Bit depth (e.g., 32, 24, 16)

# Launch with custom configuration
./_olms-launcher.sh
```

**Configuration Variables Explained:**

- **OLMS_AUDIO_DEVICE**: Your audio interface device identifier (e.g., "hw:1", "hw:0")
  - Find your device with: `aplay -l` or `arecord -l`
  - Leave empty for automatic detection (default)

- **OLMS_BUFFER_CONFIG**: JACK buffer configuration in format "buffer_size:periods"
  - **buffer_size**: Number of samples per buffer (lower = lower latency, higher = more stable)
  - **periods**: Number of buffer periods (more periods = more stable but higher latency)
  - Common configurations:
    - `32:2` - Lowest latency (32 samples, 2 periods = 64 total frames)
    - `32:3` - Low latency with better stability (32 samples, 3 periods = 96 total frames)
    - `64:2` - Balanced performance (64 samples, 2 periods = 128 total frames)
    - `64:3` - Default stable configuration (64 samples, 3 periods = 192 total frames)
    - `128:2` - Higher stability (128 samples, 2 periods = 256 total frames)
    - `128:3` - Very stable (128 samples, 3 periods = 384 total frames)

- **OLMS_BIT_DEPTH**: Audio bit depth for JACK
  - `32` - 32-bit (recommended for CPU efficiency)
  - `24` - 24-bit (for Ardour compatibility)
  - `16` - 16-bit (fallback for older hardware)

**Benefits of Custom Configuration:**
- **Faster Startup**: Skip 30-60 seconds of hardware detection phases
- **Stability**: Use known good configurations that work with your hardware
- **Consistency**: Always use the same optimal settings

**When to Use Custom Configuration:**
- **IMPORTANT: Do NOT use initially** - Always run automatic detection first to find optimal settings for your hardware
- You have tested and found stable settings for your hardware through automatic detection
- You want faster startup times for regular use after determining optimal settings
- You're using the same audio interface consistently with known working configuration

**⚠️ Recommendation:**
- **First-time users**: Always use automatic detection (default behavior) to discover your hardware's optimal settings
- **After testing**: Once you've identified stable settings that work with your specific audio interface, then use custom configuration for faster startup
- **Hardware changes**: If you change audio interfaces or system configuration, revert to automatic detection first

**Default Values (if not specified):**
- `OLMS_BUFFER_CONFIG="64:3"` (64 samples, 3 periods)
- `OLMS_BIT_DEPTH="32"` (32-bit)
- `OLMS_AUDIO_DEVICE=""` (auto-detect)

**Phase 3 Detection Process:**

When using automatic detection (default), Phase 3 performs two detection phases:

1. **Phase 1: Bit-Depth Detection** - Tests 32-bit → 24-bit → 16-bit to find the optimal bit depth
2. **Phase 2: Buffer Detection** - Tests various buffer configurations from lowest latency to highest stability

The custom configuration bypasses both phases when all three variables are set, providing immediate startup with your specified settings.

### 2. Measure Latency

After launching OLMS POC, measure the system latency:

```bash
# Run the latency test to measure Round-Trip Latency (RTL)
./test/olms-latency-test.sh

# This will show the actual latency in milliseconds
# Target: < 5ms for professional audio performance
```

### 3. Access the Web Interface

Once OLMS is running, access the web interface at:
```
http://localhost:8080
```

### 4. System Verification

Verify the complete system setup:
```bash
# Run comprehensive system test
./config/scripts/test_complete_system.sh

# Check realtime privileges
ulimit -r  # Should return 99
ulimit -l  # Should return unlimited

# Verify user groups
groups $USER  # Should include audio and realtime
```

**For detailed installation instructions, see:**
- **[OLMS Specifications](OLMS_specs.md)** - Complete installation methods and system requirements
- **[Startup Process Specification](OLMS_STARTUP_SPECIFICATION.md)** - Detailed startup procedures

---

## 🤝 Join the OLMS Community

We invite developers and audio enthusiasts to join the Open Live Mixing System project. If you're passionate about real-time audio and open-source technology, we'd love for you to contribute!

**Community Channels:**

*   **Official Website:** 👉 [https://openlivemixingsystem.org/](https://openlivemixingsystem.org/)
*   **Telegram Channel:** 👉 [https://web.telegram.org/a/#-1003532216403](https://web.telegram.org/a/#-1003532216403)

---

## 📋 Documentation

### Technical Specifications
- **[OLMS Specifications](OLMS_specs.md)** - Complete technical specifications, architecture details, and installation methods
- **[Startup Process Specification](OLMS_STARTUP_SPECIFICATION.md)** - Detailed startup process and system initialization
- **[Configuration Management](config/)** - System configuration files and management utilities

### Development
- **[Scripts Implementation Summary](SCRIPTS_IMPLEMENTATION_SUMMARY.md)** - Detailed script implementation and architecture
- **[Contributor Setup Guide](OLMS_specs.md#-contributor-setup--testing-guide)** - Instructions for contributors and developers

---

## THE OPEN LIVE MIXING SYSTEM (OLMS) MANIFESTO

### Vision: Redefining Digital Mixing with Open Source

> "Our central idea is to transform a common, inexpensive computer—ideally a **fanless Mini-PC with compatible USB audio interfaces**—into a dedicated, reliable rack-mount digital mixer, entirely controllable via Wi-Fi network."

OLMS offers an open-source alternative, aiming to replicate the **"power-on-and-mix" reliability** of professional systems, operating at a **fixed Sample Rate of 48 kHz**.

### The Technical Challenge: Real-Time Audio

We are committed to providing stable multi-channel live audio with **RTL below 5ms** and **less than 2 audible audio glitches** (X-runs) **per hour**.

Our technology stack is built on solid open-source foundations:
*   **Base Platform:** A Linux system with a **Real-Time (RT) kernel** for minimal latency.
*   **Audio Core:** **Ardour** (DAW/Mixer) running in **headless mode** (without GUI), used as a stable LV2 host.
*   **Audio Server:** **JACK2 (Primary) / ALSA Backend (Fallback)**, configured for maximum Real-Time (RT) priority.
*   **Control:** A complete, responsive, and touch-friendly **Web Browser** user interface (HTML5/JS) communicating with Ardour via an **OSC Bridge Server**.
*   **Core Logic:** **Lua Scripts (integrated within Ardour)** manage advanced features like Session, Bank, Scene Management, and Dynamic I/O Patching.

### The Open Core Pledge and Commercial Sustainability

The entire critical part of the mixing system—the RT Kernel, JACK/ALSA configuration, Ardour Headless, Lua Scripts, the Web GUI, and the OSC Bridge Server—is **100% Open Source** and released under the **GPLv3 License**.

Our path to sustainability is a **Hybrid Open Core Model**. The commercial strategy focuses on advanced, high-value features (e.g., Anti-Feedback System, Live Auto-Mixer) and the sale of **Service Level Agreements (SLA)** and **Officially Certified Hardware** (Mini-PCs guaranteed to meet RTL/X-run targets under full load). This model ensures stability and continuous development for the free core.

### The Final Validation: X-run Stability

OLMS's credibility rests on meeting rigorous RT metrics in its current PoC phase:
1.  **Latency:** Total Round-Trip Latency (RTL) must consistently be $< 5 \text{ ms}$ at 48 kHz.
2.  **Stability:** The system MUST achieve less than 2 X-runs per hour during one hour of stress testing under full load conditions.