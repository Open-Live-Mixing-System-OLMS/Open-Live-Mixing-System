# Open Live Mixing System (OLMS) - GPL Core Engine and Logic (v 1.3)

## TARGET FOLDER STRUCTURE
olms-project/
├── PKGBUILD                 # Arch package definition (Dependencies)
├── setup-env.sh             # Bootstrap script (One-time: installation/permissions)
├── scripts/                 # Operational scripts (On every startup/runtime)
│   ├── rt_tuning.sh         # CPU/Kernel optimizations
│   ├── audio_virtual.sh     # ALSA Loopback modules loading
│   └── ardour_launcher.sh   # Ardour Headless launch command
├── engine/                  # Audio Logic (OLMS Core)
│   ├── session-template/    # Ardour .ardour template
│   └── lua/                 # Lua scripts for bank management
└── ui/                      # OSC Layout (Open Stage Control)


## Ardour Headless (GPL) Core


This section details the Ardour Headless (GPL) core, which functions as the stable, functional headless mixer foundation of OLMS.

## 🎙️ OLMS Audio Communications Specification
This specification defines the requirements for the **Media Gateway (MG)** component to handle duplex (monitoring and talkback) audio over an unstable Wi-Fi network using standard browser technologies.
### 1. General Principles
| Principle | Detail | Rationale |
| :--- | :--- | :--- |
| **Protocol** | **WebRTC** (Mandatory) | Provides native support for low-latency streaming, NAT traversal, FEC, and PLC, essential for resilience over Wi-Fi. |
| **Connectivity**| Audio communication is separate from the OSC control layer (WebSockets). | Decouples critical control (low bandwidth, reliable) from critical audio (high bandwidth, loss-tolerant). |

---
### 2. Talkback (Controller → Mixer)
This channel is **Mono**, for the operator to communicate with the stage/band. High quality is not required, but intelligibility and low-to-medium latency are necessary for a smooth conversation.
#### 2.1. Requirements
| Requirement | Value / Detail |
| :--- | :--- |
| **Channel Count** | 1 (Mono) |
| **Target Latency**| **150ms - 300ms** (Acceptable, network dependent) |
| **Bitrate** | Low-to-Medium (Focus on voice clarity) |
| **Browser API** | `MediaDevices.getUserMedia()` and WebRTC `RTCPeerConnection` (Sender) |

#### 2.2. Audio Encoding Specification
| Parameter | Value | Rationale |
| :--- | :--- | :--- |
| **Codec** | **Opus** (Mandatory) | Excellent performance for speech, low computational cost, and built-in noise resilience. |
| **Sampling Rate** | 16 kHz (Narrowband) or 24 kHz (Wideband) | 24 kHz is preferred for clarity, but 16 kHz saves bandwidth without losing intelligibility. |
| **Frame Size** | 20ms | Standard WebRTC setting for low delay. |
| **Bitrate** | **20 kbps - 32 kbps** | Sufficient for high-quality speech without excessive load. |

#### 2.3. Media Gateway (MG) Function
- MG receives the WebRTC stream, acts as the recipient.
- MG decodes the Opus stream and passes the raw audio data to a dedicated, low-priority **JACK client** (`olms-talkback-in`).
- The `olms-talkback-in` client's output ports are statically patched to the **Talkback Bus** in Ardour.

---
### 3. Monitoring (Mixer → Controller)
This channel is **Stereo**, used for **Cue Mix** or **PFL/Solo** monitoring by the operator. **Low latency** is a higher priority than Talkback, and audio quality should be acceptable for musical context.
#### 3.1. Requirements
| Requirement | Value / Detail |
| :--- | :--- |
| **Channel Count** | 2 (Stereo L/R) |
| **Target Latency**| **100ms - 200ms** (Critical, acceptable for closed-back monitoring) |
| **Bitrate** | Low-to-Medium (Focus on voice clarity) |
| **Browser API** | WebRTC `RTCPeerConnection` (Receiver) |

#### 3.2. Audio Encoding Specification
| Parameter | Value | Rationale |
| :--- | :--- | :--- |
| **Codec** | **Opus** (Mandatory) | Opus performs well on music and is necessary for low-latency WebRTC transport. |
| **Sampling Rate** | **48 kHz** | Matches the standard JACK session rate for minimal resampling overhead in the MG. |
| **Frame Size** | 20ms | Low delay setting. |
| **Bitrate** | **64 kbps - 128 kbps** (Variable) | Requires higher bitrate than Talkback to preserve musical fidelity. WebRTC will adapt this based on network conditions. |

#### 3.3. Media Gateway (MG) Function
- A dedicated JACK client (`olms-monitor-out`) takes the stereo output from Ardour's **Monitor/Solo Bus**.
- MG acts as the source/sender for the WebRTC stream.
- The raw audio data from JACK (48 kHz) is encoded by the MG using Opus and transmitted via the WebRTC connection.
- The WebRTC configuration must be optimized for **low-delay** (by reducing the playout delay buffer size where possible).

---
### 4. Implementation Notes & Workflow
1. **Session Startup:** Ardour launches and automatically patches the **Talkback Bus Input** to the `olms-talkback-in` client and the **Monitor Bus Output** to the `olms-monitor-out` client.
2. **Web UI Connection:**
    - The Web UI establishes an **OSC/WebSocket** connection for control (faders, mute, solo).
    - The Web UI initiates two separate **WebRTC Peer Connections** with the MG: one for Talkback (sending audio) and one for Monitoring (receiving audio).

## 📝 Feature Specification: PDC Management for FX Returns
### 1. Architectural Requirement (Scripting/Lua Core)
**Goal:** Ensure the lowest possible perceived latency for time-based effects (Reverb, Delay) by selectively controlling Plugin Delay Compensation (PDC).

**Action Required (Template Scripting / Lua):**
1. **Default PDC State:** All pre-configured **FX Return Buses** (e.g., `FX_Reverb_Bus_1`, `FX_Delay_Bus_1`, etc.) within the base Ardour template (`OLMS_48ch_6banks.template`) **MUST** have their individual Plugin Delay Compensation (PDC) function disabled by default.
    - _Rationale: The intrinsic delay of the effect is generally preferred over the compounded system delay needed for full PDC alignment on wet signals._
2. **Exposed OSC Command (Lua Implementation):** Implement a Lua function exposed via OSC to allow the Web UI to toggle the PDC status of any designated Bus.
    - **Proposed OSC Path:** `/olms/fx/pdc_toggle`
    - **Arguments:** `[string bus_name]` , `[int state]` (where `1 = enable PDC`, `0 = disable PDC`)
    - _Example: `/olms/fx/pdc_toggle "FX_Reverb_Bus_1" 1`_

**Goal:** Provide the operator with runtime control over PDC on FX Returns.

**Action Required (Web UI):**
1. **Control Element:** Add a dedicated **PDC Toggle** button/switch within the **Bus Control Panel** section of the Web UI, specifically for all **FX Return Buses**.
2. **Default Display:** The switch should visually indicate the **PDC is OFF** (default state) when the application starts.
3. **Functionality:** This UI element must send the corresponding `/olms/fx/pdc_toggle` OSC message to the Ardour Engine upon interaction.

## 📝 Technical Specification Update: Access Control and Workflow v1.3
This document summarizes the changes regarding User Management, Access Control, and Client-Side Workflow, focusing on maintaining the **GPL Core** and leveraging **Open Stage Control** for the Proprietary UI layer.
## 1. Access Control Architecture
The system implements functional access control based on the principle that **network security is handled externally (Wi-Fi/LAN control)**, making the internal system's goal functional segmentation rather than cryptographic security.
### Key Architectural Choices:
- **Engine & Protocol:** **Ardour Headless** remains the audio core, controlled exclusively via **OSC**.
- **UI/Middleware:** **Open Stage Control** acts as the integrated Web Server and the WebSocket ↔ OSC Bridge. **No custom proprietary middleware is required.**
- **Authentication Logic:** Authentication, Authorization, and UI rendering logic are handled entirely by **Client-Side JavaScript (JS)** within the Open Stage Control interface.
## 2. User & Role Management
User data is stored in plain text/JSON within the OLMS configuration directory, accessible by the UI's JS engine.
### Initial User Data Structure
The system will initialize with a capacity for 20 unique users, defined by their role and assigned Aux Bus control permissions.
**File:** `/etc/olms/auth.json` (Part of the GPL Core Configuration)
```json
{
  "users": {
    "admin": {
      "password": "master_password",
      "role": "master",
      "token": "a4d3f2c1"
    },
    "user_1": {
      "password": "p_u1",
      "role": "musician",
      "aux_sends": [6],
      "token": "u1b9e8g7"
    },
    "user_2": {
      "password": "p_u2",
      "role": "musician",
      "aux_sends": [3, 7],
      "token": "u2c7a6b5"
    },
    // ... up to 20 users
    "user_20": {
      "password": "p_u20",
      "role": "musician",
      "aux_sends": [1],
      "token": "u20f0e9d"
    }
  },
  "roles": {
    "master": ["full_ui_access", "all_aux_sends", "routing_control"],
    "musician": ["monitor_mix_only"]
  }
}
```
### Role Definitions
| Role ID | Description | Permissions |
| :--- | :--- | :--- |
| `master` | Full control (FOH engineer/Technician). | Can view/control all Fader Banks, all Aux Sends (1-8), Routing Matrix, and System Settings. |
| `musician` | Restricted monitor control. | Can only view/control the Aux Send busses explicitly listed in their `aux_sends` array. |

## 3. Client Workflow and Navigation
The workflow is designed to be fast, avoiding unnecessary redirects to maintain a "live" feel, with a single initial login step.
### 3.1 Initial Login Screen
1. **Entry Point:** Upon accessing the OLMS IP/Port (e.g., `192.168.1.150:8080`), the client is presented with a **dedicated Login Screen**.
2. **Authentication:** Client-Side JavaScript reads the `auth.json` file (via Open Stage Control data binding) and verifies the submitted `username`/`password` combination in plain text.
3. **Token Generation:** On success, a unique `token` and the associated `aux_sends` array are stored in the browser's `localStorage` for session persistence.
4. **Redirection Rule:** The client is **immediately redirected** to the main mixer view.
### 3.2 Access Rule on Dashboard Load
The Dashboard logic is driven by the user's assigned `aux_sends` list:
| Role | Landing Page & Access | Visibility Rule |
| :--- | :--- | :--- |
| **Musician** | Redirected to the specific Aux Send screen with the **lowest ID** in their assigned list. _(e.g., User 2, with `[3, 7]`, lands on the Aux 3 screen.)_ | **Hides** all UI elements corresponding to unassigned Aux Sends (e.g., the Aux 8 panel). **Disables** the sending of any OSC commands not targeting the assigned Aux busses. |
| **Master** | Redirected to the **Main Fader Bank** screen. | **All UI elements are visible and active.** |

### 3.3 Dynamic Panel Rendering (Core Logic)
1. Each Aux Send control panel (e.g., the set of faders controlling the Aux 7 mix) must have a unique identifier in the UI (e.g., `aux-7-panel`).
2. Upon dashboard load, the JS iterates through the user's `aux_sends` array (`[3, 7]`).
3. Any panel ID that does **not** match an authorized Aux Send ID in the array is set to `display: none;` via CSS.
4. Crucially, the **OSC sending function** within the custom JavaScript must intercept all outgoing messages and check the target Aux Bus ID against the user's stored permissions, blocking any unauthorized commands before they reach Ardour.

## 📋 OLMS Architecture: Full Template Specification
This specification details the complete, high-capacity, and redundant template structure residing within the **Ardour Headless** engine. All resources are **pre-configured** and either **Active** or **Disabled**, ensuring zero runtime creation for maximum **Real-Time (RT) stability**.
### I. Input Channel Structure (Banks & Utility Tracks)
The core architecture manages 56 input channels, structured into standard banks and a dedicated utility block. All tracks are loaded into the Ardour session template at startup.
| Channel Range | Description | Channel Type | Initial State | Management |
| :--- | :--- | :--- | :--- | :--- |
| **1-48** (Banks 1-6) | **Main Input Channels** (6 × 8-channel banks) | Mono (Fixed) | Disabled | Lua Scripts/OSC (Bank Activation) |
| **49-56** (Utility) | **Aux/Utility Channels** (e.g., dedicated playback, BGM, Smaart I/O) | Mono (Fixed) | **Disabled** (Manually Activated) | Lua Scripts/OSC (Individual/Group Activation) |
| **57-64** (Reserved) | **Future Expansion** (Pre-built, but not currently used) | Mono (Fixed) | Disabled | **Hidden** from UI and Disabled in Ardour |

> **Key Rule:** Channels 49-56 are always loaded and visible in the UI (e.g., in a dedicated "Utility" bank), but their corresponding **Route** in Ardour is set to `Route.State.INACTIVE` and must be manually enabled via a specific OSC command.
### II. Routing Elements (Routes, Buses, I/O)
| Element | Count | Channel Type | Initial State (CPU Optimization) | Management Protocol |
| :--- | :--- | :--- | :--- | :--- |
| **Input Channels** | **56** | Mono (Fixed) | Disabled (Activation based on I/O detection/Banks) | Lua Scripts/OSC |
| **FX Send Bus** | 12 | Stereo (Fixed) | Disabled (User-activated via UI) | Lua Scripts/OSC Custom |
| **Group Bus** | 12 | Stereo (Fixed) | Disabled (User-activated via UI) | Lua Scripts/OSC Custom |
| **Aux Send Bus** | 12 | Mono (Fixed) | Disabled (User-activated via UI) | Lua Scripts/OSC Custom |
| **Matrix Bus** | 12 | Stereo (New) | Disabled (User-activated via UI) | Lua Scripts/OSC Custom |
| **Master Bus** | 1 | Stereo (Fixed) | Active | Ardour OSC Standard |
| **TalkBack Input** | 1 | Mono (Fixed) | Active (Routed Pre-fader to all Auxes/Matrices) | Lua Scripts/OSC Toggle |

---
### III. Control Elements (Control Groups)
| Element | Count | Functionality | Management Protocol |
| :--- | :--- | :--- | :--- |
| **VCA Faders (DCA)** | 12 | Remote control over multiple Channel Faders/Sends. | Ardour OSC Standard / Lua |
| **Mute Groups (MG)** | 12 | Single-button mute control over assigned channels. | Lua Scripts/OSC Custom |
| **Channel Linking** | N/A | Mono → Stereo pairing of adjacent Input Channels (e.g., Ch 1 & 2). | Lua Script logic for parameter synchronization. |
| **Views / Spill Groups** | 12 | UI filtering to display channels belonging to a selected Group/VCA/MG. | Web UI Logic (triggered by `/olms/view/select 3` OSC command) |

---
### IV. Key Architectural Logic
#### **RT Stability and Template Management**
- **Pre-built Philosophy:** All routes, buses, and control groups are **pre-built** within the template. Runtime operations are **strictly limited** to enabling and disabling elements, never creation or deletion, which safeguards against RT hiccups.
- **Activation Command:** The core mechanism for CPU optimization is using Ardour's **Route State**.
    - **Activation:** `Route:set_state(Route.State.ACTIVE)`
    - **Deactivation:** `Route:set_state(Route.State.INACTIVE)`
    - This stops the processing of the entire Route (fader, plugins, metering, etc.) while keeping the object present for quick, RT-safe activation.
- **Mono/Stereo Rule:** Input/Aux → **Mono**. Groups/FX/Matrix/Master → **Stereo**.
#### **OSC Implementation**
- **Ardour Standard OSC:** Used for basic, latency-critical controls (e.g., `/strip/gain`, `/strip/mute`, `/strip/pan`).
- **Custom OLMS OSC Commands:** Used for high-level management intercepted by embedded Lua scripts:
    - `/olms/bank/enable [bank_id]` (Activates Ch 1-8, 9-16, etc.)
    - `/olms/route/enable [route_name]` (Enables a specific FX/Group Bus)
    - `/olms/utility/enable [49-56_track_id]` (Manually enables a utility track)
    - `/olms/mg/toggle [group_id]` (Toggles a Mute Group)

```
┌─────────────────────────────────────┐
│   ARDOUR HEADLESS (GPL)             │
│   - Lua Scripts: Session, I/O Patch.|
│   - 48ch Template (6 banks × 8ch)   │
│   - Plugins in bypass               │
│   - Static routing                  │
│   - Tracks can be disabled per bank │
└─────────────────────────────────────┘

## 🚀 Contributor Setup & Testing Guide

This section provides instructions for contributors who want to test and develop OLMS without the complete X-Console distribution.

### 1. Prerequisites for Contributors

To set up a testing environment, you need:

| Component | Version/Requirement | Purpose |
| :--- | :--- | :--- |
| **Operating System** | Arch Linux (recommended) | RT kernel support and package management |
| **Audio System** | JACK2 + ALSA | Audio routing and hardware interface |
| **DAW Engine** | Ardour 8 Headless | Audio processing and OSC control |
| **Web Interface** | Open Stage Control | OSC/WebSocket bridge for testing |
| **Scripts** | OLMS Core scripts | System configuration and startup |

### 2. Manual Testing Environment Setup

For contributors, OLMS provides a manual startup script that emulates the systemd service startup sequence without requiring the full distribution.

#### 2.1 Using the Manual Startup Script

The `scripts/olms-startup.sh` script provides a complete testing environment:

```bash
# Navigate to the OLMS-Core directory
cd /path/to/OLMS-Core

# Run the manual startup script
./scripts/olms-startup.sh
```

**What the script does:**
1. **Phase 1**: Executes RT optimization (`rt_tuning.sh`)
2. **Phase 2**: Configures hardware IRQ pinning (`irq_pinning.sh`)
3. **Phase 3**: Starts JACK and Ardour Headless (`ardour_launcher.sh`)
4. **Phase 4**: Sets CPU affinity (`olms-apply-affinity`)
5. **Phase 5**: Starts disk protection (`disk_guard.sh`)

#### 2.2 Script Features

- **Error Handling**: Each phase checks for success before proceeding
- **Status Messages**: Real-time feedback on each operation
- **Fallback Support**: Graceful handling when individual scripts are missing
- **Monitoring Tools**: Built-in commands for system monitoring
- **Clean Shutdown**: Instructions for proper system shutdown

#### 2.3 Testing Workflow

1. **Environment Preparation**:
   ```bash
   # Ensure all required packages are installed
   sudo pacman -S alsa-utils ardour jack-example-tools pulseaudio-jack
   
   # Create necessary directories
   sudo mkdir -p /var/olms
   ```

2. **Script Execution**:
   ```bash
   # Copy scripts to system locations (if needed)
   sudo cp scripts/rt_tuning.sh /usr/bin/
   sudo cp scripts/irq_pinning.sh /usr/bin/
   sudo cp scripts/ardour_launcher.sh /usr/bin/
   sudo cp scripts/disk_guard.sh /usr/bin/
   
   # Make scripts executable
   sudo chmod +x /usr/bin/rt_tuning.sh
   sudo chmod +x /usr/bin/irq_pinning.sh
   sudo chmod +x /usr/bin/ardour_launcher.sh
   sudo chmod +x /usr/bin/disk_guard.sh
   
   # Run the startup script
   ./scripts/olms-startup.sh
   ```

3. **System Verification**:
   ```bash
   # Check JACK status
   jack_control status
   
   # Monitor system logs
   journalctl -f -u ardour.service
   
   # Verify disk space
   df -h
   ```

### 3. Development and Debugging

#### 3.1 Individual Component Testing

Test each component separately for debugging:

```bash
# Test RT tuning only
sudo /usr/bin/rt_tuning.sh

# Test IRQ pinning only
sudo /usr/bin/irq_pinning.sh

# Test audio core only
sudo /usr/bin/ardour_launcher.sh
```

#### 3.2 Performance Monitoring

Monitor system performance during testing:

```bash
# Check CPU usage
top -p $(pgrep -d',' ardour jackd)

# Monitor audio latency
jack_iodelay

# Check for xruns
jack_latency_test
```

#### 3.3 Troubleshooting Common Issues

| Issue | Diagnosis | Solution |
| :--- | :--- | :--- |
| **JACK fails to start** | Check audio device permissions | `sudo usermod -aG audio $USER` |
| **High latency** | Verify RT kernel and IRQ pinning | Check `rt_tuning.sh` output |
| **xruns occur** | Increase buffer size or reduce load | Modify JACK parameters |
| **Scripts not found** | Verify script installation paths | Check `/usr/bin/` directory |

### 4. Integration with Development Workflow

#### 4.1 Script Synchronization

**IMPORTANT**: Any changes made to the manual startup script must be reflected in the corresponding systemd service files for production use:

- `scripts/olms-startup.sh` ↔ `systemd/olms-*.service` files
- Ensure parameter consistency between testing and production environments
- Update documentation when making architectural changes

#### 4.2 Template Development

Contributors can modify the Ardour template for testing:

```bash
# Edit the template in GUI mode first
ardour8 --template=engine/session-template/OLMS_48ch_6banks.template

# Test changes with headless mode
ardour8 --headless --template=engine/session-template/OLMS_48ch_6banks.template
```

#### 4.3 OSC Testing

Test OSC communication with Open Stage Control:

```bash
# Start Open Stage Control
open-stage-control --osc-port 3819

# Test OSC commands
oscsend osc.udp://localhost:3819 /strip/gain si "1" 0.8
```

### 5. Contributing Guidelines

#### 5.1 Code Changes

When contributing changes:

1. **Test with Manual Script**: Always test changes using `scripts/olms-startup.sh`
2. **Update Documentation**: Update this section when adding new components
3. **Maintain Compatibility**: Ensure changes work with both testing and production environments
4. **Add Error Handling**: Include proper error checking and user feedback

#### 5.2 Script Maintenance

Keep the manual startup script synchronized:

- **File Paths**: Ensure script paths match installed locations
- **Dependencies**: Document any new script dependencies
- **Error Messages**: Provide clear error messages for troubleshooting
- **Version Compatibility**: Test with different versions of dependencies

#### 5.3 Testing Requirements

Before submitting contributions:

1. **Full Startup Test**: Verify complete system startup
2. **Individual Component Test**: Test each script independently
3. **Performance Test**: Ensure RT performance requirements are met
4. **Documentation Test**: Verify all documentation is accurate and complete

This manual testing approach allows contributors to work with OLMS without requiring the complete X-Console distribution, while maintaining compatibility with the production systemd-based architecture.

### 6. Testing vs Production Differences

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
