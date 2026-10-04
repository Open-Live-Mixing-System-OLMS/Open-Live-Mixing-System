# X-Console - Premium Commercial Distribution (DST) Specification (v 1.3)


## 📑 OLMS Deployment & Installation Architecture

This document summarizes the technical decisions made for the creation of the final installable distribution (ISO/Live USB), focusing on disk management and user experience (UX).

### I. Distribution Architecture

| Component | Technical Choice | Rationale |
|---|---|---|
| **Base ISO** | Arch Linux + Archiso | Provides maximum flexibility to build a minimal Live USB containing the **PREEMPT_RT** Kernel and essential OLMS packages. |
| **Graphical Installer** | Calamares | Provides a robust GUI for system partitioning and configuration, crucial for non-expert users. |
| **Development Environment** | Dual PC: Mint (Dev) $\leftrightarrow$ Arch RT (Testing) | Allows for *vibe coding* via SSH and ensures low-latency (xrun) tests occur on native hardware. |
| **Service User** | Dedicated **`olms`** user (`/bin/false` shell) | **Essential** for security and stability. All critical audio processes (Ardour/JACK) run as `olms` to avoid using `root` privileges for RT operations. |
| **Code History** | Git | Used on the Mini-PC (PC 2) as a Deployment Folder and Safety Net for sync and rollback during development, but **removed** from the final ISO image. |

---

### II. Disk Partitioning Scheme

The Calamares installer must offer options to create or resize the disk to support the following streamlined structure, utilizing a **single partition for the OS and Recordings** to maximize I/O stability.

| Partition | Mount Point | Minimum Size | Purpose in OLMS Architecture |
|---|---|---|---|
| **P1** | `/boot/efi` | 512 MB | UEFI boot partition (FAT32). |
| **P2** | **`/` (Root)** | **256 GB** | **OLMS Core, Configuration, and Recordings.** Includes: RT Kernel, Ardour, JACK, all services and scripts. Must provide sufficient space for up to 10 hours of 48-channel recording (approx. 180 GB). Configuration data is stored in `/var/olms/data/`. |

---

### III. Installer Automation (UX/Reversibility)

The primary goal is to eliminate the risk of manual operations by the user, especially for uninstallation.

#### A. Installer Options

The Calamares graphical installer must provide at least the following installation options:

*   **Erase Disk and Install OLMS:** Clean installation across the entire disk using the P1 + P2 scheme.
*   **Install Alongside (Dual Boot):** Resizes the existing operating system (Windows/Mint) and creates **P2 only**.

#### B. Bootloader and Recovery Management (Crucial)

To ensure the best possible user safety, a simplified, though limited, recovery mechanism is required.

| Phase | Technical Detail Saved/Executed | Mechanism |
|---|---|---|
| **Pre-Install (Backup)** | Active UEFI boot entries and boot map (`efibootmgr -v`). | Automatic saving of the backup file (`original_efivars.txt`) within the ESP (Boot Partition) in a dedicated subfolder. |
| **Partition Cleanup** | UUID of the OLMS Root partition (P2). | Saved in a configuration file (`/etc/olms/disk_layout.conf`) read by the uninstallation script. |
| **Uninstallation** | Deletes OLMS and attempts to restore the previous system. | "Restore Boot" button on the Live USB launches a custom Bash script (`olms-purge.sh`). This script executes the deletion of the OLMS partition (P2 via UUID) and attempts to restore the UEFI bootloader (via the backup file) in the background. **UX Note:** User is warned that manual intervention (using the other OS\\\'s recovery tools) may be required if UEFI restoration fails. |

#### C. Final System State (ISO)

Before generating the final ISO, the `archiso` process must include:

*   **Cleanup:** Removal of the Git repository (`.git`) and all development tools/packages from the Root partition.
*   **Inclusion:** System services and scripts (e.g., `ardour_launcher.sh`, `irq_pinning.sh`, **`disk_guard.sh`**) must be copied to system directories (e.g., `/usr/local/bin/`).

---

### IV. Backup Strategy (Security Levels)

The backup strategy must reflect the need for security both during development and distribution.

*   **Code Backup (Git):** History of script changes (on external cloud/repo).
*   **Development Backup (Image):** Periodic cloning of the entire Root partition (P2) of the Mini-PC for fast recovery after an RT tuning failure.
*   **Distribution Backup (ISO): permitan Saving the clean, installation-ready "**Golden Image**."

---

## V. Engine Network Configuration

# 📝 Technical Specification Update: Networking Architecture (Installer Mandate)

This update formalizes the network configuration strategy for the **OLMS Core Engine (Arch RT Mini-PC)** to ensure maximum stability and predictability in a live environment, overriding potential hardware-dependent DHCP assignments.

### I. Engine Network Configuration Mandate

The **OLMS Engine** must operate on a **static IP address** on its wired (Ethernet) interface. This configuration must be set by the distribution installer, ensuring the Web UI clients always know the Engine's location.

| Parameter | Value | Rationale |
| :--- | :--- | :--- |
| **Engine Static IP** | `192.168.1.10` | Fixed address for all OSC/WebSocket communication from clients. |
| **Subnet Mask** | `255.255.255.0` (`/24`) | Standard subnet for local network isolation. |
| **Assumed Gateway** | `192.168.1.1` | The target IP address for the user-supplied Router/AP. |
| **Interface Match** | Generic `Name=en*` pattern | Ensures hardware independence for common Ethernet interfaces (`enp*`, `eno*`). |

### II. Installer Automation Requirements (Calamares)

The Calamares installer must automate the creation of this static configuration.

1.  **Static Configuration File:** The installer must drop a configuration file (e.g., for `systemd-networkd` or NetworkManager) into the root partition (`P2`) that applies the static IP (`192.168.1.10/24`) to any detected wired interface matching the generic pattern (`en*`).
2.  **User Notice:** The installer (or the accompanying documentation) **must inform the user** that their dedicated **External Router/Access Point** must be configured to:
    * Use the `192.168.1.1` address as its Gateway.
    * Limit its DHCP range to prevent conflicts with the Engine's fixed IP (`192.168.1.10`).

> **Constraint:** The system must prioritize the stability of the Engine. Client devices (Musician/Master) accessing the Web UI may continue to use standard DHCP/WiFi provided by the External Router, as their location is dynamic but the Engine's location is critical and static.


## Simplified 2-Layer Architecture
```
┌─────────────────────────────────────┐
│   WEB UI (Proprietary)              │
│   - Fader, mute, solo, pan          │
│   - Plugin controls                 │
│   - Routing matrix                  │
│   - Metering                        │
│   - Bank selector (8ch blocks)      │
└──────────────┬──────────────────────┘
               │ OSC/WebSocket
┌──────────────▼──────────────────────┐
│   ARDOUR HEADLESS (GPL)             │
│   - Lua Scripts: Session, I/O Patch.|
│   - 48ch Template (6 banks × 8ch)   │
│   - Plugins in bypass               │
│   - Static routing                  │
│   - Tracks can be disabled per bank │
└──────────────┬──────────────────────┘
               │ JACK API
┌──────────────▼──────────────────────┐
│   JACK2 / ALSA Backend (GPL)        │
│   - Hardware I/O management         │
│   - Automatic audio connections     │
└─────────────────────────────────────┘
```

<h2>Expected Performance</h2>
<ul>
<li><strong>CPU usage</strong>:
<ul>
<li>2 active banks: 3-8%</li>
<li>4 active banks: 8-15%</li>
<li>6 active banks: 12-25%</li>
</ul>
</li>
<li><strong>RTT Latency</strong>: 5-10ms @ 128 samples</li>
<li><strong>Xruns</strong>: <2/hour with correct tuning</li>
<li><strong>RAM overhead per inactive bank</strong>: ~50-100MB</li>
</ul>

## 📝 Open Live Mixing System (OLMS) - Strategic and Technical Update (v1.4)

This document summarizes the strategic and technical decisions made, detailing the project split and the implementation plan for high-value features, particularly plugin control.

### 1. Project Naming and Distribution Model

The architecture is formally split into two distinct, harmonized projects following an **Open Core/Distro Model**:

| Project Name | Role | Core License | Key Features / Deliverables |
| :--- | :--- | :--- | :--- |
| **OLMS** (Open Live Mixing System) | The **GPL Core Engine and Logic.** Establishes the stable, functional headless mixer foundation. | **GPL** | Ardour Headless, Lua Scripts (Bank/I/O Management), JACK Config, **Base OSC Layout (JSON/YAML)**, Base Graphic Assets (CC-BY). |
| **X-Console** (by x-radios) | The **Premium Commercial Distribution (DST).** Provides enhanced aesthetics and advanced control features. | **Proprietary Add-ons** | Premium Graphic Assets, Proprietary JavaScript Extensions, **Advanced Plugin Control UI**, Premium LV2/VST Plugin Marketplace. |

**Tagline:** X-Console: Don't buy a mixer: build one instead.

### 2. Core UI/Middleware Architecture

The decision has been finalized to use **Open Stage Control (OSC)** as the permanent, real-time control interface for both the Core and the Distro, replacing the initially planned custom Web UI development.

| Layer | Component | Protocol | Functionality Summary |
| :--- | :--- | :--- | :--- |
| **Control Interface** | Open Stage Control (Web Server) | WebSocket / HTTP | Serves the web UI. Handles user input and displays metering/status. |
| **Logic/Engine** | Ardour Headless | OSC Protocol | Manages the audio session, internal routing, tracks, and plugin parameters via OSC messages. |

### 3. Plugin Control Implementation Strategy (X-Console Value-Add)

Plugin control is a key differentiator for the X-Console distribution. Ardour's native OSC support for plugin parameters will be utilized:

* **OLMS Core (GPL Functionality):**
    * The base session template will include essential, open-source LV2 plugins (e.g., EQ, Compression) inserted into track slots but will be **Bypassed by default** and **NOT controllable** via the base OLMS OSC layout. Only core strip parameters (Gain, Mute, Solo, Pan) are exposed.

* **X-Console DST (Proprietary Functionality):**
    * **Advanced Control UI:** The X-Console distribution will include the necessary OSC Layout and/or Proprietary JavaScript code to generate control panels (knobs, sliders) for **full parameter manipulation** of the plugins loaded in Ardour (e.g., editing EQ bands, compressor settings).
    * **Proprietary Add-on Integration:** The proprietary code will handle the **OSC mapping** required to integrate and expose the parameters of any commercial (Proprietary) LV2/VST plugins sold in the X-Console marketplace.

### 4. Licensing and Proprietary Asset Management

The architecture is designed to maintain GPL compliance while protecting commercial value:

*   **GPL Core Protection:** The functional **OSC Layout (JSON/YAML)** for the mixer's fundamental operations (faders, banks, routing matrix structure) **MUST REMAIN GPL** as part of the OLMS project.
*   **Proprietary Extensions Mechanism:** Commercial value is injected without modifying the GPL layout file structure:
    1.  **Premium Graphics:** **Figma** will be used exclusively to design and export the **Proprietary Premium Graphic Assets** (All Rights Reserved theme, high-resolution knobs/faders) that define the "X-Console look."
    2.  **Proprietary Logic:** Advanced features and plugin UIs are contained within **external, proprietary JavaScript files** that are loaded by the X-Console setup.
    3.  **Critical Fallback:** The **GPL OSC Layout MUST ensure silent, non-breaking fallback** (no web console errors) if calls to proprietary JavaScript functions (e.g., related to a premium plugin editor) are made while running the base OLMS Core without the X-Console add-ons.





<ul>
<li>X-Console offers a Premium Commercial Distribution (DST) built upon the OLMS GPL Core.</li>
<li>Its primary offerings focus on: <strong>Premium LV2/VST audio plugins</strong>, <strong>Expert consulting/Setup assistance</strong>, <strong>Custom script development</strong> (for specific client needs), and <strong>Training courses</strong>.</li>
<li>The OLMS GPL Core serves as the foundation, ensuring stability and a robust functional base.</li>
</ul>
<h2>Development (X-Console Focus)</h2>
<ul>
<li><strong>Phase 1 - PoC</strong>: Validation with Open Stage Control + Ardour headless. Latency/xruns/stability test on 2 banks (16ch). Runtime enable/disable banks validation. Environment: VirtualBox + ALSA loopback + Ardour GUI. <strong>Deliverable</strong>: Functional 16ch template with stable OSC control.</li>
<li><strong>Phase 2 - Template</strong>: 48ch session with 6 pre-configured banks. Dynamic routing and bank activation scripts. IRQ pinning and CPU tuning scripts.</li>
</ul>
X-Console si concentra sulle seguenti fasi:
<ul>
<li><strong>Phase 3 - UI Custom</strong>: Proprietary web UI development using advanced frameworks and design. This phase focuses on the custom aesthetic and functionality of the X-Console interface, including faders, metering, advanced plugin controls, routing matrix, and bank selectors, along with custom graphical assets.</li>
<li><strong>Phase 4 - Marketplace & Licensing</strong>: Development of the X-Console add-on system, robust licensing mechanisms (hardware fingerprinting and online validation), comprehensive user documentation, and the infrastructure for the premium plugin marketplace.</li>
</ul>
<h2>Immediate PoC Roadmap (Migrated from OLMS_specs.md)</h2>
<h3>1. Base Setup (Day 1)</h3>
<ul>
<li>✓ Arch Linux installed</li>
<li>✓ XFCE4 + LightDM for temporary GUI</li>
<li>Install Ardour 8 with GUI</li>
<li>Activate ALSA loopback: <code>sudo modprobe snd-aloop</code></li>
</ul>
<h3>2. Template in GUI (Days 2-3)</h3>
<ul>
<li>Create 16 audio track session (2 banks)</li>
<li>Routing: Assign loopback inputs to tracks 1-16</li>
<li>Master bus + 2-3 base LV2 plugins in bypass</li>
<li>Save template: "OLMS_16ch_2banks"</li>
</ul>
<h3>3. OSC Test (Days 4-6)</h3>
<ul>
<li>Enable OSC in Ardour preferences</li>
<li>Install Open Stage Control</li>
<li>Create test fader for <code>/strip/gain</code>, <code>/strip/mute</code>, <code>/strip/solo</code></li>
<li>Verify real-time control without xruns</li>
</ul>
<h3>4. Stability Test (Days 7-9)</h3>
<ul>
<li>Play audio on all 16 tracks</li>
<li>OSC stress test under load</li>
<li>Monitor xruns with <code>jack_iodelay</code> / <code>jack_latency_test</code></li>
<li>Target: <2 xruns/hour</li>
</ul>
<h3>5. Headless Validation (Day 10)</h3>
<ul>
<li>Test: <code>ardour8 --no-splash --template=OLMS_16ch_2banks.template</code></li>
<li>Confirm OSC functions without GUI</li>
</ul>

<h2><emoji>🛑</emoji> Disk Guardrail & Stability</h2>
<p><strong>Objective:</strong> Prevent catastrophic loss of recorded audio due to disk space exhaustion by proactively stopping the recording transport before the OS reports an I/O error.</p>
<p>The "Disk Guardrail & Stability" mechanism is implemented in the OLMS core and includes critical thresholds and trigger actions to ensure system stability.</p>

<h2>Essential Scripts to Develop</h2>
<p>This section lists the essential scripts for X-Console, focusing on machine management and tuning. The Ardour/Lua core scripts (<code>bank_manager.lua</code>, <code>olms_core.lua</code>) are included in the GPL core.</p>
<ul>
<li><code>irq_pinning.sh</code> - Configures IRQ affinity automatically</li>
<li><code>hardware_detect.sh</code> - Detects I/O and suggests templates</li>
<li><code>rt_tuning.sh</code> - Applies kernel/CPU optimizations</li>
<li><code>ardour_launcher.sh</code> - Launches Ardour with correct RT parameters</li>
<li><code>disk_guard.sh</code> - Proactive safety script that monitors disk space and halts Ardour's transport via OSC when the critical threshold (10 GB) is reached.</li>
</ul>
<h2>Key Architectural Choices</h2>
<p>Key architectural choices are detailed in the OLMS core specifications and support the X-Console implementation.</p>
<hr>
<h2><emoji>🎙️</emoji> OLMS Audio Communications Specification </h2>
<p>Details on the OLMS audio communications specification are an integral part of the GPL core.</p>
<h2><emoji>📋</emoji> OLMS Architecture: Full Template Specification</h2>
<p>The complete specification of the OLMS architecture template is fundamental for the system's operation.</p>
<h2><emoji>📝</emoji> Feature Specification: PDC Management for FX Returns</h2>
<p>Details on PDC (Plugin Delay Compensation) management for FX Returns are implemented in the OLMS core.</p>
<h1><emoji>📝</emoji> Technical Specification Update: Access Control and Workflow v1.3</h1>
<p>This section describes how X-Console handles access control and user workflow, based on the OLMS GPL Core. Implementation details and data structure are part of the core specification.</p>
## 📝 X-Console: Aggiornamento Strategico e Tecnico (v1.4) - Sfruttamento del Core OLMS

<p>This update illustrates how X-Console, as a Premium Commercial Distribution, strategically leverages the OLMS GPL Core. It outlines the dual-project distribution model, focusing on the integration of X-Console's proprietary add-ons and advanced features to deliver a superior commercial product.</p>

### 1. Project Naming and Distribution Model

The architecture is formally split into two distinct, harmonized projects following an **Open Core/Distro Model**:

| Project Name | Role | Core License | Key Features / Deliverables |
| :--- | :--- | :--- | :--- |
| **OLMS** (Open Live Mixing System) | The **GPL Core Engine and Logic.** Establishes the stable, functional headless mixer foundation. | **GPL** | Ardour Headless, Lua Scripts (Bank/I/O Management), JACK Config, **Base OSC Layout (JSON/YAML)**, Base Graphic Assets (CC-BY). |
| **X-Console** (by x-radios) | The **Premium Commercial Distribution (DST).** Provides enhanced aesthetics and advanced control features. | **Proprietary Add-ons** | Premium Graphic Assets, Proprietary JavaScript Extensions, **Advanced Plugin Control UI**, Premium LV2/VST Plugin Marketplace. |

**Tagline:** X-Console: Don't buy a mixer: build one instead.

### 4. Licensing and Proprietary Asset Management

The architecture is designed to maintain GPL compliance while protecting commercial value:

*   **GPL Core Protection:** The functional **OSC Layout (JSON/YAML)** for the mixer's fundamental operations (faders, banks, routing matrix structure) **MUST REMAIN GPL** as part of the OLMS project.
*   **Proprietary Extensions Mechanism:** Commercial value is injected without modifying the GPL layout file structure:
    1.  **Premium Graphics:** **Figma** will be used exclusively to design and export the **Proprietary Premium Graphic Assets** (All Rights Reserved theme, high-resolution knobs/faders) that define the "X-Console look."
    2.  **Proprietary Logic:** Advanced features and plugin UIs are contained within **external, proprietary JavaScript files** that are loaded by the X-Console setup.
    3.  **Critical Fallback:** The **GPL OSC Layout MUST ensure silent, non-breaking fallback** (no web console errors) if calls to proprietary JavaScript functions (e.g., related to a premium plugin editor) are made while running the base OLMS Core without the X-Console add-ons.

<hr>

## Technical Stack and Development Environment (Migrated from OLMS_specs.md)

## Technical Stack
*   **OS**: Linux RT (Arch) with PREEMPT_RT kernel
*   **Audio Core**: JACK2 (Primary) / ALSA Backend (Fallback)
*   **Engine**: Ardour 8 Headless
*   **Middleware Logic**: Lua Scripts (integrated within Ardour)
*   **Protocol**: OSC / WebSocket (Native)
*   **Interface**: Custom Web UI (HTML5/JS/CSS)

## Current Development Stack (PoC - Proof of Concept)
*   **Environment**: VirtualBox on Arch Linux
*   **Virtual Audio (UPDATED)**: ALSA Loopback with 16 virtual Mono channels for precise routing, or advanced ALSA/JACK configuration.
*   **Temporary GUI**: XFCE4 + LightDM (to be removed post-template)
*   **OSC Testing**: Open Stage Control (standalone app)
*   **Vibe Coding**: Cline + Gemini for UI and automation scripts

<h2>RT Configuration and CPU Pinning (Migrated from OLMS_specs.md)</h2>
<h3>Kernel Boot Parameters</h3>
<p><code>threadirqs intel_pstate=disable processor.max_cstate=1</code></p>
<h3>CPU Core Assignment (Implementation Details)</h3>
<ul>
<li><strong>IRQ Pinning</strong>: Pin the audio card's IRQ to a dedicated core (via <code>smp_affinity</code>). <strong>Priority: IRQ scheduling is more significant than process pinning.</strong></li>
<li><strong>Process Pinning</strong>: Remove explicit core pinning for JACK/Ardour/Carla. Use high RT priority (<code>chrt -f 80</code>/<code>75</code>) instead.</li>
</ul>
<h3>Critical Disabling</h3>
<ul>
<li>Hyper-Threading (Intel)</li>
<li>CPU frequency scaling → performance governor</li>
<li>Deep C-states (>C1)</li>
<li>Swap during runtime (vm.swappiness = 10)</li>
</ul>
<h3>Hardware and BIOS Tuning</h3>
<ul>
<li><strong>Hardware Selection</strong>: Hardware must allow <strong>dedicated hardware IRQ</strong> for the soundcard.</li>
<li><strong>BIOS Configuration</strong>: <strong>Mandatory:</strong> Possibility to disable power-saving states like <strong>C1E</strong> and <strong>NMI</strong> (Non-Maskable Interrupts) in the BIOS.</li>
<li><strong>CPU Selection</strong>: <strong>Recommendation:</strong> Avoid modern CPUs with P/E cores, or ensure E-cores are disabled along with Hyper-Threading.</li>
</ul>
<h3>Implementation Workflow for Dynamic Allocation</h3>
<ol>
<li><code>/usr/local/bin/olms-detect-cpu</code>: Reads CPU topology and generates JSON output.</li>
<li><code>/etc/olms/cpu-allocation.conf</code>: Generated by detect script, mapping IRQ/JACK/Ardour/Carla to specific cores based on the table above.</li>
<li><code>/usr/local/bin/olms-apply-affinity</code>: Executes <code>taskset</code>, <code>chrt</code>, and writes to <code>/proc/irq/*/smp_affinity</code>.</li>
<li><code>/etc/default/grub modifier script</code>: Adds <code>isolcpus=</code> dynamically based on the detected topology (Requires reboot after first run).</li>
<li><code>systemd service</code>: <code>olms-affinity.service</code>: Executes <code>olms-apply-affinity</code> on boot (Before: <code>pipewire.service</code>, <code>ardour.service</code>).</li>
</ol>

## 🎛️ SystemD Service Architecture

The Open Live Mixing System (OLMS) adopts a **Dual-Layer Orchestration Model** where `systemd` manages dependencies and ordering for OS-level processes (Bash/RT tuning), while **dynamic communication** between the OS layer and Audio Engine layer is handled almost exclusively via **OSC (Open Sound Control)**, meaning the central orchestrator for runtime logic is Ardour itself, not a Bash script.

The interaction is divided into two key phases: **Startup Phase (Static/Systemd)** and **Runtime Phase (Dynamic/OSC)**.

### I. Startup and Configuration Phase (Managed by `systemd`)

This phase stabilizes the RT environment before the audio engine (Ardour/JACK) is started. The orchestrator is **`systemd`**, which guarantees ordering and correct execution of each configuration script.

| Layer | Component (Script) | Language | Purpose and Interaction |
| :--- | :--- | :--- | :--- |
| **1. RT Optimization** | `rt_tuning.sh` | Bash | **Does NOT interact with Lua/Ardour.** Configures system variables (e.g., `vm.swappiness=10`, CPU governor, `processor.max_cstate=1`, `isolcpus`). |
| **2. Hardware Pinning** | `irq_pinning.sh` | Bash | **Does NOT interact with Lua/Ardour.** Reads the audio card's IRQ and sets its affinity to a dedicated core (writes to `/proc/irq/*/smp_affinity`). |
| **3. Audio Core Startup** | `ardour_launcher.sh` | Bash | **Launches central processes.** Executes `chrt -f 80 ardour8 --headless...` and `chrt -f 75 jackd -d alsa...`. **Interaction is indirect:** Starting Ardour triggers execution of the master Lua script (`olms_core.lua`). |
| **4. Proactive Protection** | `disk_guard.sh` | Bash | **Runtime interaction (Only exception).** Executed periodically by `olms-disk-guard.service` (systemd timer). Sends an OSC command to Ardour (`/ardour/transport_stop i 1`) if disk space drops below 10 GB. |

**systemd Startup Flow (Ordering):**

1.  `olms-rt-tuning.service` (Executes `rt_tuning.sh`)
2.  `olms-irq-pinning.service` (Executes `irq_pinning.sh`)
3.  `jack.service` (Starts JACK, as dependency of Ardour)
4.  `ardour.service` (Executes `ardour_launcher.sh` → Starts Ardour Headless)
5.  `olms-affinity.service` (Executes `olms-apply-affinity`, which sets CPU affinity for Ardour/JACK after they have been started).

For runtime logic and dynamic management (bank, routing, VCA, Mute Groups) managed by Ardour/Lua/OSC, refer to [OLMS_specs.md](./OLMS_specs.md#orchestration-layers).

### II. Service Files Structure

The following systemd service files are included in the OLMS distribution:

| Service File | Description | Dependencies |
| :--- | :--- | :--- |
| `olms-rt-tuning.service` | Executes RT optimization script | `multi-user.target` |
| `olms-irq-pinning.service` | Configures hardware IRQ pinning | `olms-rt-tuning.service` |
| `ardour.service` | Launches JACK and Ardour Headless | `olms-irq-pinning.service`, `jack.service` |
| `olms-affinity.service` | Sets CPU affinity for audio processes | `ardour.service` |
| `olms-disk-guard.service` | Monitors disk space and protects recordings | `ardour.service` |

### III. Testing vs Production Architecture

#### Testing Environment (Manual Startup)
For development and testing, a manual startup script `olms-startup.sh` is provided that executes all services sequentially in the correct order, allowing developers to:
- See each step and stop if something goes wrong
- Debug issues easily
- Test without interfering with systemd services

#### Production Environment (Automatic Startup)
In the production environment, systemd services are used for:
- **Automatic startup** on system boot
- **Managed dependencies** ensuring correct ordering
- **Centralized logging** via journald
- **Automatic restart** capabilities for critical services
- **Integration with system monitoring**

### IV. Installation and Packaging

The systemd services are integrated into the OLMS distribution through:

1. **PKGBUILD Integration**: Service files are copied to `/etc/systemd/system/` during package installation
2. **setup-env.sh**: Services are enabled during initial system setup
3. **Calamares Installer**: Services are automatically enabled during the installation process

This architecture ensures that the OLMS system can be easily deployed in both development/testing environments (using manual scripts) and production environments (using systemd services) while maintaining consistency and reliability.

### Testing vs Production Differences for X-Console

#### Audio Configuration
- **Testing Mode** (default): Ardour launches with GUI for visual monitoring and debugging
- **Production Mode** (`--prod`): Ardour runs headless for automated operation
- **Virtual Mode** (`--virtual`): Uses JACK dummy backend when no audio hardware is available

#### Hardware Requirements
- **Testing**: Can work with or without audio hardware (falls back to virtual audio)
- **Production**: Requires proper audio hardware configuration
- **Virtual**: No audio hardware required, uses software-only audio processing

#### Monitoring and Debugging
- **Testing**: Full visual feedback, detailed logging, interactive debugging
- **Production**: Minimal logging, automated monitoring, no user interface
- **Virtual**: Software-only monitoring, useful for development without hardware

#### Performance Characteristics
- **Testing**: May have slightly higher latency due to GUI overhead
- **Production**: Optimized for lowest possible latency and CPU usage
- **Virtual**: Performance depends on system resources, no hardware constraints

#### Use Cases
- **Testing**: Development, debugging, feature validation, performance analysis
- **Production**: Live performances, automated recording, headless operation
- **Virtual**: Development without hardware, CI/CD pipelines, documentation

#### Command Line Options

The startup script supports the following options for different environments:

```bash
# Testing mode with GUI (default)
./scripts/olms-startup.sh

# Production mode (headless)
./scripts/olms-startup.sh --prod

# Virtual mode (no hardware required)
./scripts/olms-startup.sh --virtual

# Testing mode with virtual audio
./scripts/olms-startup.sh --test --virtual
```

#### System Behavior Differences

| Component | Testing Mode | Production Mode | Virtual Mode |
| :--- | :--- | :--- | :--- |
| **Ardour Interface** | Visible GUI window | No GUI, headless | No GUI, headless |
| **JACK Backend** | ALSA/PulseAudio (if available) | ALSA/PulseAudio | Dummy (virtual) |
| **Error Handling** | Interactive prompts | Silent operation | Silent operation |
| **Logging Level** | Verbose with status messages | Minimal logging | Minimal logging |
| **Startup Time** | Slower (GUI initialization) | Faster | Fastest |
| **Resource Usage** | Higher (GUI overhead) | Lower | Lowest |

#### X-Console Specific Considerations

- **Premium Features**: Testing mode allows full access to premium plugin controls and UI elements
- **Licensing**: Production mode enforces license validation for proprietary components
- **Marketplace Integration**: Virtual mode simulates marketplace functionality for development
- **Consulting Tools**: Testing mode includes diagnostic tools for setup assistance

## X-Console Integration Architecture

This section details the architectural relationship between X-Console and the core OLMS audio engine, specifically regarding `ardour_launcher.sh`.

### Core Audio vs X-Console Layers

The system follows a strict separation of concerns between the GPL core audio engine and the proprietary X-Console layer. The core audio provides the fundamental audio processing capabilities, while X-Console adds premium user interface and commercial features on top.

### Relationship with ardour_launcher.sh

The `ardour_launcher.sh` script serves exclusively as an audio engine launcher and does not handle any X-Console specific operations. It is responsible for:

- JACK server startup and configuration
- Ardour headless process initialization
- Real-time system optimizations
- Hardware detection and configuration

X-Console operations such as web interface management, proprietary JavaScript loading, license verification, and marketplace functionality are handled separately from the core audio engine.

### Integration Approaches

Three architectural patterns are available for integrating X-Console with the core audio system:

#### 1. Wrapper Script Approach (Recommended for Development)

This approach uses a coordination script that manages X-Console services before launching the audio engine. The wrapper handles all X-Console specific initialization and then calls `ardour_launcher.sh` to start the audio system.

**Advantages:**
- Clear separation between GPL and proprietary components
- Easy testing and debugging of individual components
- Flexible development workflow
- Core audio engine remains unchanged

#### 2. Direct Modification Approach

This approach involves modifying `ardour_launcher.sh` to include X-Console operations directly within the audio startup process.

**Disadvantages:**
- Blurs separation between GPL and proprietary code
- Complicates core audio testing
- Increases maintenance complexity
- Violates clean architectural boundaries

#### 3. systemd Coordination Approach (Recommended for Production)

This approach uses systemd service dependencies to coordinate the startup sequence of X-Console services and the audio engine. Each component runs as a separate systemd service with defined dependencies.

**Advantages:**
- Professional production deployment
- Automatic service management and monitoring
- Clear dependency management
- System-level integration

### Recommended Architecture

For development environments, the Wrapper Script Approach is recommended to maintain flexibility and ease of testing. For production environments, the systemd Coordination Approach provides the most robust and maintainable solution.

This hybrid approach allows developers to test the core audio engine independently while providing a clean production deployment with automatic startup coordination.

## Testing vs Production: Implementation Strategy

This section provides guidance for implementing the testing and production workflows specific to X-Console.

### Testing Environment Workflow

The testing environment allows manual preparation of the system before launching the audio engine. This approach provides maximum control and visibility during development and debugging.

#### Manual Preparation Benefits

Manual testing offers several advantages for development:

- **Complete visibility**: Each step can be observed and controlled
- **Easy debugging**: Issues can be isolated to specific operations
- **Flexible experimentation**: Individual components can be tested independently
- **No system restarts**: Changes can be tested without rebooting
- **Immediate feedback**: Real-time output from each operation

#### Testing Workflow Structure

The testing workflow follows a sequential approach where each component is prepared manually before proceeding to the next step. This allows developers to verify each stage before continuing with the audio engine startup.

### Production Environment Workflow

The production environment uses automated startup via systemd services to ensure reliable and consistent operation without manual intervention.

#### systemd Service Dependencies

The production deployment uses a dependency chain where each service starts only after its dependencies are ready. This ensures proper initialization order and system stability.

The typical startup sequence is:
1. Real-time tuning services
2. Hardware configuration services
3. X-Console interface services
4. Audio engine services

#### Production vs Testing Selection

The choice between testing and production approaches depends on the specific use case:

- **Development and debugging**: Use manual testing approach
- **Feature validation**: Use manual testing approach
- **Performance analysis**: Use manual testing approach
- **Live performances**: Use production systemd approach
- **Automated recording**: Use production systemd approach
- **Headless operation**: Use production systemd approach

## Transforming Test Scripts to systemd Services

This section explains the conceptual approach for converting manual test scripts into production systemd services.

### Script Analysis Phase

The first step involves analyzing the test script to identify individual operations that can be separated into distinct services. Each operation should be self-contained and have clear dependencies on other operations.

### Service Creation Strategy

Each identified operation becomes a separate systemd service with appropriate configuration:

- **Service type**: Determine whether the service should be oneshot (completes and exits) or forking (continues running)
- **Dependencies**: Define which services must be active before this service starts
- **Execution order**: Establish the correct sequence for service startup
- **Error handling**: Configure restart policies and failure responses

### Service Installation Process

The conversion process involves:

1. **Service file creation**: Create systemd service files for each operation
2. **Dependency configuration**: Define service relationships and startup order
3. **System integration**: Install services into the systemd directory structure
4. **Activation**: Enable services for automatic startup on boot

### Production Deployment

Once converted to systemd services, the system can be deployed in production environments with automatic startup and professional service management capabilities.

This approach provides a clear migration path from development testing to production deployment while maintaining system reliability and maintainability.

<hr>

<h2>🗃️ Logging Strategy and Error Management</h2>

### I. Operating System Level Logging (Bash & RT Tuning)

All Bash scripts (and the `systemd` services that execute them) utilize the native Linux logging mechanism for centralization.

#### 1. Mechanism and Centralization (Journald)
*   **Target:** `rt_tuning.sh`, `irq_pinning.sh`, `ardour_launcher.sh`, `disk_guard.sh`.
*   **Mechanism:** Each Bash script writes status, success, or failure messages to **Standard Output (stdout)** and **Standard Error (stderr)**.
*   **Integration:** All `systemd` services executing these scripts (e.g., `olms-affinity.service`) are configured to automatically capture `stdout`/`stderr` and forward it to **`journald`**.
*   **Advantage:** The RT system logging is **centralized** and can be viewed via the command `journalctl -u <service_name>` (e.g., `journalctl -u olms-disk-guard.service`). This ensures there are no scattered or unmonitored log files.

#### 2. Error Handling in Bash Scripts
Bash scripts must implement basic but effective error handling:

| Level | Action in Script | Example (`disk_guard.sh`) |
| :--- | :--- | :--- |
| **Debug/Info** | Use of `echo "INFO: ..."` | `echo "INFO: Ardour transport stopped due to low disk space."` |
| **Critical Errors**| Use of `echo "CRITICAL: ... " >&2` (on stderr) with non-zero exit code. | `if [ $free_space -lt 10 ]; then echo "CRITICAL: Disk full." >&2; exit 1; fi` |
| **Reaction Action** | The `systemd` service can be configured with directives like `OnFailure=` to execute an action if the script exits with an error code. |

For details on application-level logging (Ardour/Lua), including error handling and real-time notifications, refer to [OLMS_specs.md](./OLMS_specs.md#logging-and-error-handling).

### II. Production Monitoring and Notifications

For system health monitoring in a rack, a two-level approach is adopted:

#### 1. Local Monitoring (Console)
*   **RT Status:** The technician can access the Mini-PC (via SSH/Terminal) and run real-time diagnostic commands:
    *   **Verify Xruns (Latencies):** `jack_iodelay` or `jack_latency_test` to monitor audio buffer stability.
    *   **Verify Centralized Logs:** `journalctl -f -u ardour.service` for continuous real-time *tailing* of all messages (OS, Bash, Ardour/Lua).

#### 2. Visual Notifications (Web UI - Open Stage Control)
This is the primary alarm method for the FOH operator:
*   **Proactive Alarms:** The **X-Console** Web UI (which manages the interface) implements a **proprietary JavaScript** module that listens for custom OSC messages `/olms/status/*` sent by Bash (`disk_guard.sh`) or Lua.
*   **Action:** When a `/olms/status/disk_critical` message is received, the JavaScript renders a **prominent red/orange overlay** on the operator dashboard, ensuring immediate action.

**In summary:**

*   **Centralization:** **`journald`** manages *all* logs (system and application).
*   **RT Responsiveness:** Critical logic management (Bank/Routing) is internal to the Ardour process (Lua) for stability.
*   **Operator Notification:** **OSC** is the *proactive* and *asynchronous* notification channel for errors requiring immediate attention, displayed on the Web UI.

<hr>

## 🔒 Additional Security Measures (Hardening, Permissions, DoS)

The architecture must integrate fundamental security measures beyond the application code.

### 1. Base Operating System Hardening

The operating system (OS) must undergo rigorous hardening to reduce the attack surface:

*   **Least Privilege (PoLP):** Ensure that services, including those handling OSC and WebSockets, run with the minimum necessary user and permissions, never as root/Administrator.
*   **Essential Services:** Disable or remove all default OS services, software, and features that are not strictly necessary.
*   **Patch Management:** Implement a consistent update policy for the OS and critical libraries.
*   **Tight Firewall:** Configure the firewall to block all unrequested ports, opening only those necessary for specific communication.

### 2. File Permission Management

Protecting sensitive data and configurations is crucial:

*   **Limited Access:** Set restrictive permissions on configuration files, private keys, and sensitive directories. They must be readable/writable only by the operating system user who needs them.
*   **Logical Separation:** Separate directories for executables, logs, and configurations, preventing writing in areas containing binary code.

For specific details on protection measures against DoS (Denial of Service) attacks related to OSC/WebSocket, refer to [OLMS_specs.md](./OLMS_specs.md#security-measures).

These points must be documented in a standard architectural Security Checklist.

### 3. Conditional Graphic Startup (Smart Headless vs. Local GUI)
* **Efficiency Principle**: The installed X-Console appliance starts by default without a graphic server (pure headless) to minimize CPU/GPU consumption and xrun risk.
* **Local Peripheral Detection at Boot**:
  * A probe script at bootstrap (Phase 4 / systemd target) verifies the presence of local I/O hardware:
    * Active display (via `/sys/class/drm/` or KMS).
    * Input devices (mouse and/or keyboard via `/dev/input/by-id/`).
  * **Automatic Decision**:
    * **If Monitor + Input detected**: The system automatically starts the local X11/XWayland graphical environment and displays the console interface on-board.
    * **If absent (Rack Machine / Remote Box)**: The graphic server is not started. The system exposes control and the Splash Page exclusively via network interface (Web / WebSocket / OSC).

### 4. Walled Garden, Network Sandbox & Update Policy
* **Walled Garden Firewall (`nftables` / `iptables`)**:
  * Total block of outbound web traffic from the host PC to the Internet to ensure the appliance operates isolated and protected from interruptions during live events.
  * **Exclusive Whitelist**: Outbound traffic is allowed exclusively to the official X-Console Marketplace domain and endpoints (for hardware license validation, add-on downloads, and sponsor logo synchronization).
  * Internet browsing for clients (tablets/smartphones connected to the local Wi-Fi router) remains completely unaffected.
* **Immutable System & Package Pinning**:
  * Upstream freeze (`/etc/pacman.conf` via `IgnorePkg`) of fundamental audio packages: RT kernel (`linux-rt`), `jack2`, `ardour`, `alsa-lib`, and driver modules.
  * Targeted maintenance limited solely to security patches for the minimum indispensable network services (`openssl`, `avahi-daemon`).
* **Sponsor Synchronization**:
  * The list of logos and sponsor cards shown in the startup Splash Page (included in the OLMS Core) is updated in the background through the same official X-Console Marketplace endpoint, allowing the addition of new sponsors without requiring operating system reinstallations.

## Business Model
### GPL Core (Free):
*   OS + Configured Ardour headless
*   **Include: All Lua Scripts** (Session, bank management, scene management, and I/O logic).
*   Startup scripts, basic routing, bank management
*   Minimal web UI (fader/mute/solo/bank selector)
*   Open source plugins (a-*, LSP, x42, Calf)
### Proprietary Add-on Marketplace:
*   Focus proprietary offerings on: **Premium LV2/VST audio plugins**, **Expert consulting/Setup assistance**, **Custom script development** (for specific client needs), and **Training courses** delivered via the platform.
### Constraint Legal Structure:
*   The entire **Core System (Engine + Logic) must be GPL**.

## Target Hardware
*   **Entry**: N100, 8GB RAM → 2 banks (16ch)
*   **Mid**: i5-12450H, 16GB RAM → 4 banks (32ch)
*   **Pro**: i7/Ryzen7+, 32GB RAM → 6 banks (48ch)
