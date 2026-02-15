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

## 🖥️ Hardware Testing Platform

This project is currently being prototyped and tested on the following hardware configuration:

### Primary Test System
**Lenovo V520-15IKL Desktop**
- **CPU:** Intel Core i5-7500 @ 3.40GHz (4 cores, 4 threads)
- **RAM:** 16GB DDR4
- **BIOS:** M16KT40A (10/05/2017)
- **Audio:** Intel 200 Series PCH HD Audio (Integrated)
- **USB Audio Interfaces:** 
  - Focusrite Scarlett Solo (3rd Gen.) - ID 1235:8211
  - Behringer UMC202HD - ID 03f0:3341

### Audio Interface Specifications

#### Focusrite Scarlett Solo (3rd Gen.)
- **Type:** USB 2.0 Audio Interface
- **Channels:** 1x Input, 2x Output
- **Sample Rates:** 44.1kHz, 48kHz, 88.2kHz, 96kHz
- **Bit Depth:** 24-bit
- **Connectivity:** USB-C, XLR/TRS Combo Input, 1/4" Output
- **Driver Support:** ALSA, JACK2 compatible

#### Behringer UMC202HD
- **Type:** USB 2.0 Audio Interface  
- **Channels:** 2x Input, 2x Output
- **Sample Rates:** 44.1kHz, 48kHz, 88.2kHz, 96kHz
- **Bit Depth:** 24-bit
- **Connectivity:** USB-B, XLR/TRS Inputs, 1/4" Outputs
- **Driver Support:** ALSA, JACK2 compatible

### Testing Configuration
This hardware setup provides a realistic testing environment for:
- **Real-time audio performance** validation
- **Latency measurement** and optimization
- **Multi-interface compatibility** testing
- **USB audio stability** under Linux RT kernel
- **Professional audio workflow** simulation

The Lenovo V520-15IKL serves as the primary development and testing platform, while the two USB audio interfaces (Focusrite Scarlett Solo and Behringer UMC202HD) provide comparative performance data for different hardware configurations and driver implementations.

# Open Live Mixing System (OLMS) - GPL Core Engine and Logic (v 1.3)

## TARGET FOLDER STRUCTURE
OLMS-Core/
├── PKGBUILD                 # Arch package definition (Dependencies)
├── setup-env.sh             # Bootstrap script (One-time: installation/permissions)
├── olms.install             # Package installation script
├── README.md                # Project documentation
├── LICENSE                  # GNU GPL v3.0 license
├── copyright_template.txt   # Copyright template for new files
├── OLMS_specs.md            # Main specifications document
├── OLMS_STARTUP_SPECIFICATION.md # Startup process specification
├── config/                  # System configuration files (Centralized Management)
│   ├── realtime/            # Realtime privileges configuration
│   │   └── 99-realtime.conf # Optimized realtime privileges for OLMS
│   ├── scripts/             # Configuration management utilities
│   │   ├── install-symlinks.sh      # Install system symlinks
│   │   ├── remove-symlinks.sh       # Remove system symlinks
│   │   └── test_complete_system.sh  # Complete system testing
│   └── systemd/             # Systemd service configurations
│       ├── user.conf.d/     # User-specific systemd overrides
│       │   └── 10-olms-realtime.conf # Realtime user limits
│       └── cpu_shielding.sh # CPU shielding implementation
├── engine/                  # Audio Logic (OLMS Core)
│   └── session-template/    # Ardour .ardour template
│       └── OLMS-POC/        # Proof of Concept template
│           ├── OLMS-POC.ardour.temp # Ardour session template
│           ├── OLMS-POC.history      # Session history
│           ├── OLMS-POC.history.bak  # Session history backup
│           ├── analysis/    # Session analysis data
│           ├── dead/        # Unused session data
│           ├── export/      # Export configurations
│           ├── externals/   # External plugins
│           ├── interchange/ # Session interchange data
│           │   └── OLMS-POC/
│           │       ├── audiofiles/    # Audio files
│           │       └── midifiles/     # MIDI files
│           ├── peaks/       # Audio peak data
│           └── plugins/     # Plugin configurations
├── systemd/                 # Systemd service files
│   ├── ardour.service       # Ardour headless service
│   ├── olms-affinity.service # CPU affinity service
│   ├── olms-disk-guard.service # Disk monitoring service
│   ├── olms-irq-pinning.service # Hardware IRQ pinning service
│   └── olms-rt-tuning.service   # Real-time tuning service
├── Startup/                 # Operational scripts (On every startup/runtime)
│   ├── _olms-launcher.sh    # Main launcher script
│   ├── _olms-launcher-test.sh # Test launcher script
│   ├── olms-orchestrator.sh # System orchestrator
│   ├── olms-path-utils.sh   # Path utilities
│   ├── phase0-audio-cleanup.sh # Audio environment cleanup
│   ├── phase0-lock-management.sh # Lock file management
│   ├── phase1-rt-optimization.sh # Real-time system optimization
│   ├── phase2-hardware-config.sh # Hardware configuration
│   ├── phase3-jack-init-fixed.sh # JACK server initialization
│   ├── phase4-x11-setup.sh  # X11 environment setup
│   ├── phase5-ardour-startup.sh # Ardour DAW startup
│   ├── phase6-final-report.sh # Final system report
│   ├── 99-jack-sockets.rules # JACK socket permissions
│   ├── 99-realtime.conf     # Realtime privileges (duplicate for startup)
│   ├── 99-usb-permissions.rules # USB device permissions
│   ├── audio_output_diagnostic.sh # Audio output diagnostics
│   ├── fix_jack_links.sh    # JACK link fixes
│   ├── jack_connectivity_test.sh # JACK connectivity testing
│   ├── jack_system_reset.sh # JACK system reset
│   ├── olms-jack-force-init.sh # Force JACK initialization
│   ├── olms-jack-setup.sh   # JACK setup script
│   ├── olms-runtime-permissions.sh # Runtime permission management
│   ├── olms-system-monitor.sh # System monitoring
│   ├── olms-unified-startup.sh # Unified startup script
│   ├── test_jack_detection.sh # JACK detection testing
│   └── UNIVERSAL_SYSTEM_GUIDE.md # Universal system guide
├── test/                    # Testing scripts
│   ├── olms-latency-test.sh # Latency testing
│   ├── test_jack_ardour_fixes.sh # JACK/Ardour fixes testing
│   ├── test_jack_stability.sh # JACK stability testing
│   ├── test_session_adaptation.sh # Session adaptation testing
│   └── test_variables.sh    # Variable testing
└── .gitignore               # Git ignore file

**Note:** The `setup-env.sh` script is the bootstrap script that provides automated system configuration for OLMS. It is the recommended method for initial system setup and configuration.

For detailed script implementation, architecture, and usage examples, see: [SCRIPTS_IMPLEMENTATION_SUMMARY.md](./SCRIPTS_IMPLEMENTATION_SUMMARY.md)

## 🔧 Configuration Management Architecture (NEW)

OLMS implements a centralized configuration management system using symbolic links (symlinks) to maintain version-controlled system configurations while enabling seamless system integration.

### 📁 Configuration Structure Overview

The `config/` directory serves as the central repository for all system-critical configuration files, organized into logical subdirectories:

```
config/
├── realtime/           # Realtime privileges and audio system configuration
│   ├── 99-realtime.conf    # Optimized realtime privileges for JACK/Ardour
│   └── README.md           # Realtime configuration documentation
├── systemd/            # Systemd service configurations
│   ├── olms-affinity.service      # CPU affinity management service
│   ├── olms-irq-pinning.service   # Hardware IRQ pinning service
│   └── olms-rt-tuning.service     # Realtime system tuning service
└── scripts/            # Configuration management utilities
    ├── install-symlinks.sh        # System symlink installation
    ├── remove-symlinks.sh         # System symlink removal
    └── test_complete_system.sh    # Comprehensive system testing
```

### 🔄 Symlink Management System

#### **Installation Process**
The `config/scripts/install-symlinks.sh` script creates system-wide symlinks that point to the version-controlled configuration files:

```bash
# Example symlink creation
sudo ln -sf /path/to/OLMS-Core/config/realtime/99-realtime.conf \
           /etc/security/limits.d/99-realtime.conf
```

#### **Key Benefits**
- **Version Control**: All configuration files are tracked in Git
- **Easy Deployment**: Single command installation across systems
- **Rollback Capability**: Simple symlink removal for system restoration
- **Consistency**: Ensures identical configurations across development and production
- **Documentation**: Each configuration includes inline documentation

#### **Installation Commands**
```bash
# Install all symlinks
./config/scripts/install-symlinks.sh

# Install for specific user
./config/scripts/install-symlinks.sh --user john

# Verify installation
./config/scripts/install-symlinks.sh --verify

# Remove symlinks
./config/scripts/install-symlinks.sh --remove
```

### ⚡ Optimized Realtime Privileges

The `config/realtime/99-realtime.conf` file provides maximum realtime privileges specifically optimized for professional audio production:

#### **Privilege Levels**
- **Realtime Priority**: 99 (maximum)
- **Memory Lock**: Unlimited
- **Nice Value**: -20 (highest priority)
- **File Descriptors**: 524,288
- **Process Limits**: 131,072

#### **Target Applications**
- JACK Audio Connection Kit
- Ardour DAW
- USB Audio Interfaces
- Audio Plugins and VSTs
- System audio services

#### **Group-Based Configuration**
```bash
# Primary configuration uses audio group
@audio - rtprio 99
@audio - memlock unlimited
@audio - nice -20

# Fallback for individual users
* - rtprio 99
* - memlock unlimited
```

### 🧪 System Testing and Verification

The `config/scripts/test_complete_system.sh` script provides comprehensive testing of the entire OLMS system:

#### **Test Coverage**
1. **Realtime Privileges**: Verifies privilege configuration and user group membership
2. **CPU Shielding**: Validates cgroup allocation and process isolation
3. **Audio Processes**: Checks JACK/Ardour process management and RT priority
4. **IRQ Pinning**: Validates hardware interrupt configuration
5. **System Integration**: End-to-end system functionality

#### **Test Execution**
```bash
# Run complete system test
./config/scripts/test_complete_system.sh

# Run quick test (skip some checks)
./config/scripts/test_complete_system.sh --quick

# Test from any directory
cd /any/path && /path/to/OLMS-Core/config/scripts/test_complete_system.sh
```

#### **Test Output Example**
```
=== OLMS Complete System Test ===

✓ Realtime privileges: PASSED
✓ CPU shielding: PASSED
✓ Audio processes: PASSED
✓ IRQ pinning: PASSED

✓ ALL TESTS PASSED - OLMS system is properly configured
Your OLMS system is ready for professional audio production!
```

### 🚀 Integration with System Startup

The symlink-based configuration integrates seamlessly with the existing startup architecture:

#### **Startup Sequence Integration**
```
olms-startup.sh
├── Phase 1: rt_tuning.sh (uses optimized realtime.conf)
├── Phase 2: irq_pinning.sh
├── Phase 3: prepare_machine.sh
├── Phase 4: audio_engine.sh
└── Phase 5: olms-apply-affinity.sh (CPU shielding with cgroups)
```

#### **Systemd Service Integration**
The systemd service files in `config/systemd/` can be symlinked to `/etc/systemd/system/` for automated system management:

```bash
# Enable CPU affinity service
sudo systemctl enable olms-affinity.service

# Enable IRQ pinning service
sudo systemctl enable olms-irq-pinning.service

# Enable RT tuning service
sudo systemctl enable olms-rt-tuning.service
```

### 📋 Configuration Management Workflow

#### **Development Workflow**
1. **Modify Configuration**: Edit files in `config/` directory
2. **Test Changes**: Use `install-symlinks.sh` to test locally
3. **Run Tests**: Execute `test_complete_system.sh` for validation
4. **Commit Changes**: Version control tracks all modifications
5. **Deploy**: Use installation script for production deployment

#### **Deployment Workflow**
1. **Clone Repository**: Get latest OLMS-Core version
2. **Install Symlinks**: Run `install-symlinks.sh` on target system
3. **Verify Installation**: Use `--verify` flag for confirmation
4. **Test System**: Run comprehensive system test
5. **Enable Services**: Activate systemd services as needed

#### **Maintenance Workflow**
1. **Update Configuration**: Modify files in `config/` directory
2. **Test Locally**: Verify changes in development environment
3. **Deploy Updates**: Re-run installation script on target systems
4. **Validate**: Confirm system functionality with tests

### 🎯 Key Advantages

#### **For Developers**
- **Centralized Management**: All configurations in one location
- **Version Control**: Complete history and change tracking
- **Easy Testing**: Rapid deployment and rollback capabilities
- **Documentation**: Inline comments and README files

#### **For System Administrators**
- **Consistent Deployment**: Identical configurations across systems
- **Automated Installation**: Single command setup
- **Easy Maintenance**: Simple update and rollback procedures
- **System Integration**: Seamless integration with existing infrastructure

#### **For Production Systems**
- **Stability**: Tested and validated configurations
- **Performance**: Optimized settings for audio production
- **Reliability**: Proven configuration patterns
- **Monitoring**: Comprehensive testing and verification tools

This centralized configuration management system ensures that OLMS maintains high-quality, consistent, and reliable system configurations across all deployment scenarios while providing maximum flexibility for development and maintenance.

## Script Architecture Documentation

For detailed information about the script implementation, architecture, and usage examples, see: [SCRIPTS_IMPLEMENTATION_SUMMARY.md](./SCRIPTS_IMPLEMENTATION_SUMMARY.md)

### Key Architectural Changes

**Hierarchical Script Design:**
- `olms-startup.sh` acts as the main coordinator for complete system startup
- `prepare_machine.sh` acts as a specialized orchestrator for machine preparation
- `audio_engine.sh` handles audio engine startup independently
- Individual scripts handle specific phases of system preparation
- Scripts can be used independently for testing and debugging
- Synchronized with systemd services for production deployment

**Startup Sequence:**
```
olms-startup.sh (Main Coordinator)
├── Phase 1: rt_tuning.sh
├── Phase 2: irq_pinning.sh  
├── Phase 3: prepare_machine.sh [args]
│   ├── Phase 1: rt_tuning.sh
│   └── Phase 2: irq_pinning.sh
├── Phase 4: audio_engine.sh [args]
└── Phase 5: olms-apply-affinity.sh (applied AFTER audio processes are running)
```

**Independent Usage:**
- **Complete System**: `./scripts/olms-startup.sh [mode]`
- **Machine Prep Only**: `./scripts/prepare_machine.sh [mode]`
- **Audio Engine Only**: `./scripts/audio_engine.sh [mode]`


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
- **UI/Middleware:** **Open Stage Control** acts as the integrated Web Server and the WebSocket ↔ OSC Bridge. **No proprietary middleware is required.**
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

## 🚀 OLMS Startup Process Overview

The OLMS system implements a comprehensive multi-phase startup process designed for professional real-time audio processing. The startup sequence ensures optimal system configuration, hardware detection, and audio engine initialization.

### Startup Architecture

The startup process follows a 6-phase approach with intelligent bypass capabilities:

1. **Phase 0: Pre-Startup and Process Management**
   - Audio environment cleanup and process termination
   - Lock file management and Ardour session handling
   - USB audio device detection and hardware reset

2. **Phase 1: Real-Time System Optimization**
   - Kernel parameter configuration (RT runtime allocation)
   - CPU governor enforcement and power management
   - Real-time privilege configuration and user group verification

3. **Phase 2: Hardware Configuration**
   - CPU affinity management and core isolation
   - Hardware detection and IRQ pinning
   - System topology optimization

4. **Phase 3: JACK Server Initialization (Smart Detection)**
   - **Fast Mode**: Bypass detection when optimal settings are known (via launcher variables)
   - **Standard Mode**: Two-phase hardware detection (bit-depth and buffer optimization)
   - Anti-zombie mode with extended stability monitoring
   - Socket permission management and connection validation

5. **Phase 4: X11 Environment & Display Management**
   - Multi-method display detection and XAUTHORITY configuration
   - Runtime directory management and D-Bus session setup
   - Graphics environment isolation and headless mode support

6. **Phase 5: Ardour DAW Startup**
   - Session adaptation and JACK port mapping
   - User environment transition and process management
   - Headless operation support with Xvfb

7. **Phase 6: Final System Report**
   - Comprehensive system verification and technical data extraction
   - Process status monitoring and performance metrics
   - Operational readiness assessment

### Key Startup Features

- **Modular Design**: Each phase can be tested and debugged independently
- **Smart Bypass Capabilities**: Phase 3 includes intelligent bypass when optimal audio settings are known
- **Hardware Agnostic**: Universal compatibility across Linux distributions
- **Robust Error Handling**: Graceful degradation with fallback mechanisms
- **Real-Time Optimization**: Comprehensive system tuning for low-latency audio
- **User-Centric**: Smart user detection for both direct execution and sudo scenarios

### Bypass Mechanism (Phase 3 Optimization)

OLMS includes an intelligent bypass mechanism in Phase 3 that allows users to skip time-consuming hardware detection when optimal audio settings are known:

**Configuration Variables** (set in launcher scripts):
- `OLMS_BUFFER_CONFIG`: Buffer configuration (e.g., "64:3", "32:2")
- `OLMS_BIT_DEPTH`: Bit depth (e.g., "32", "24", "16")
- `OLMS_AUDIO_DEVICE`: Audio device (e.g., "hw:1", "hw:0") - optional

**Bypass Logic**:
- If `OLMS_BUFFER_CONFIG` AND `OLMS_BIT_DEPTH` are set → Fast Mode (skip detection)
- If `OLMS_AUDIO_DEVICE` is not set → Auto-detect device then use fast mode
- If variables missing → Standard detection mode (2 phases)

**Benefits**:
- **Time Savings**: Skip 30-60 seconds of detection phases
- **Stability**: Use known good configurations
- **Flexibility**: Users can specify only what they know

**Default Values** (in launchers):
- `OLMS_BUFFER_CONFIG="64:3"` (64 samples, 3 periods)
- `OLMS_BIT_DEPTH="32"` (32-bit for optimal performance)
- `OLMS_AUDIO_DEVICE=""` (auto-detect)

For detailed startup process specifications, see: [OLMS_STARTUP_SPECIFICATION.md](./OLMS_STARTUP_SPECIFICATION.md)

## 🚀 Quick Start: Bootstrap Method (Recommended)

The fastest and most reliable way to get OLMS running is using the **Bootstrap Script**. This single command configures your entire system for professional audio production.

### Bootstrap Script Overview

The `setup-env.sh` script is a comprehensive configuration tool that automates all the complex system setup required for real-time audio processing:

```bash
# One command to configure your entire system
sudo ./setup-env.sh
```

**What the Bootstrap Script Does:**
- ✅ **System Permissions**: Configures Udev rules for USB audio, JACK sockets, CPU governors, and IRQ management
- ✅ **Realtime Privileges**: Sets up PAM limits for maximum audio priority (rtprio 99, unlimited memory lock)
- ✅ **Kernel Optimization**: Applies real-time kernel parameters for low-latency audio
- ✅ **User Groups**: Adds your user to required groups (audio, realtime, plugdev)
- ✅ **X11 Configuration**: Sets up display permissions for GUI mode operation
- ✅ **Runtime Manager**: Installs and configures the Runtime Permission Manager
- ✅ **Autostart Setup**: Configures automatic startup via systemd or rc.local

**After Bootstrap:**
1. **Restart your user session** (log out/in or reboot)
2. **Start OLMS** with the startup scripts:
   ```bash
   # Complete system startup
   ./scripts/olms-startup.sh
   
   # Or manual startup for testing
   ./scripts/prepare_machine.sh
   ./scripts/audio_engine.sh
   ```

**Why Use Bootstrap:**
- **Simplified Setup**: No need to manually configure individual components
- **Error Prevention**: Automated checks and proper configuration
- **Consistency**: Same setup across all systems
- **Time Saving**: Complete configuration in under 2 minutes
- **Reliability**: Tested configuration patterns

### Manual Configuration (Advanced Users)

For users who prefer manual control or need custom configurations, see the detailed installation methods below.

## 📦 Installation Methods

OLMS can be installed using multiple methods to accommodate different deployment scenarios and user preferences.

### 1. Bootstrap Method (Recommended for Most Users)

**For users who want the fastest, most reliable setup:**

```bash
# Navigate to OLMS-Core directory
cd /path/to/OLMS-Core

# Run the bootstrap script (requires root)
sudo ./setup-env.sh

# Restart your session
# Then start OLMS
./scripts/olms-startup.sh
```

**Benefits:**
- Complete automated configuration
- No manual dependency management
- Optimized for professional audio use
- Includes all necessary permissions and limits

### 2. Arch Linux Package (Recommended for Arch Users)

The preferred installation method for Arch Linux users is through the PKGBUILD package, which provides automated dependency management, system integration, and post-installation configuration.

#### Package Contents
The `olms-core` package includes:
- **Scripts**: All operational scripts in `/usr/bin/`
- **Configuration**: System configuration files in `/etc/olms/`
- **Templates**: Ardour session templates in `/usr/lib/olms-core/`
- **Services**: Systemd service files for automated operation
- **Documentation**: Complete documentation in `/usr/share/doc/olms-core/`

#### Installation Commands
```bash
# Build and install the package
makepkg -si

# Or install from AUR (when available)
yay -S olms-core
```

#### Post-Installation Setup
The package automatically configures:
- Realtime privileges via `/etc/security/limits.d/99-realtime.conf`
- Systemd user limits via `/etc/systemd/user.conf.d/10-olms-realtime.conf`
- X11 authentication support
- JACK capabilities and socket permissions
- Audio hardware detection and optimization

#### Manual Post-Installation Steps
After package installation, run:
```bash
# Configure realtime privileges (automated by package)
# Note: The package automatically configures realtime privileges via /etc/security/limits.d/99-realtime.conf

# Configure JACK for optimal performance
sudo olms-jack-setup setup

# Apply systemd realtime configuration
sudo olms-rt-override

# Enable and start OLMS services
sudo systemctl enable olms-rt-tuning.service
sudo systemctl enable olms-irq-pinning.service
sudo systemctl.enable ardour.service
sudo systemctl.enable olms-affinity.service
sudo systemctl.enable olms-disk-guard.service
```

**Note:** The Arch package automatically configures most system components. For complete automated setup, users can also run the bootstrap script:
```bash
sudo ./setup-env.sh
```

**Alternative Setup Method:** Users can choose between the Arch package or the bootstrap script for system configuration. The bootstrap script provides a more comprehensive setup that works across different distributions.

### 3. Manual Installation (Advanced Users)

**For users who prefer complete manual control or need custom configurations:**

This method is intended for advanced users who need specific customizations or are working on unsupported distributions. For most users, the **Bootstrap Method** is recommended.

#### Prerequisites
Install required dependencies:
```bash
# Ubuntu/Debian
sudo apt install alsa-utils ardour jackd2 qjackctl xorg-xauth xorg-xhost

# Fedora/RHEL
sudo dnf install alsa-utils ardour jack-audio-connection-kit qjackctl xorg-x11-xauth xorg-x11-xhost

# Arch Linux
sudo pacman -S alsa-utils ardour jack2 qjackctl xorg-xauth xorg-xhost
```

#### Installation Steps
```bash
# Clone the repository
git clone https://github.com/Open-Live-Mixing-System-OLMS/Open-Live-Mixing-System.git
cd Open-Live-Mixing-System

# Copy scripts to system locations
sudo cp scripts/* /usr/bin/
sudo cp systemd/* /etc/systemd/system/
sudo cp config/realtime/* /etc/security/limits.d/
sudo cp config/systemd/* /etc/systemd/system/

# Make scripts executable
sudo chmod +x /usr/bin/olms-*

# Manual configuration (replaces bootstrap script)
# Configure realtime privileges manually
sudo ./scripts/setup_realtime_privileges

# Configure JACK manually
sudo ./scripts/olms-jack-setup setup

# Apply systemd realtime configuration
sudo ./scripts/olms-rt-override
```

**Note:** This method requires manual configuration of all system components. The bootstrap script automates these steps and is recommended for most users.

**Alternative:** For a faster setup, users can run the bootstrap script after cloning:
```bash
# Use bootstrap for complete automated setup
sudo ./setup-env.sh
```

### 3. Docker Installation (Development)

For development and testing purposes, OLMS provides Docker support.

#### Building the Docker Image
```bash
# Build the development image
docker build -t olms-dev .

# Run the container
docker run -it --rm \
  --device=/dev/snd \
  --device=/dev/shm \
  --cap-add=SYS_NICE \
  --cap-add=IPC_LOCK \
  olms-dev
```

#### Docker Compose
```bash
# Start the complete OLMS stack
docker-compose up -d

# View logs
docker-compose logs -f
```

### 4. Cloud Deployment

OLMS supports deployment to cloud platforms for remote access and collaboration.

#### AWS Deployment
```bash
# Launch EC2 instance with RT kernel
aws ec2 run-instances --image-id ami-rt-kernel --instance-type c5.large

# Install OLMS on the instance
ssh ec2-user@instance-ip
git clone https://github.com/Open-Live-Mixing-System-OLMS/Open-Live-Mixing-System.git
cd Open-Live-Mixing-System

# Use bootstrap for complete automated setup
sudo ./Startup/olms-bootstrap.sh
```

#### Kubernetes Deployment
```bash
# Apply the OLMS deployment manifest
kubectl apply -f k8s/olms-deployment.yaml

# Expose the service
kubectl expose deployment olms --type=LoadBalancer --port=8080
```

## 🚀 Contributor Setup & Testing Guide

This section provides instructions for contributors who want to test and develop OLMS. The **Bootstrap Method** is recommended for the fastest and most reliable setup.

### 1. Prerequisites for Contributors

To set up a testing environment, you need:

| Component | Version/Requirement | Purpose |
| :--- | :--- | :--- |
| **Operating System** | Arch Linux (recommended) | RT kernel support and package management |
| **Audio System** | JACK2 + ALSA | Audio routing and hardware interface |
| **DAW Engine** | Ardour 8 Headless | Audio processing and OSC control |
| **Web Interface** | Open Stage Control | OSC/WebSocket bridge for testing |
| **Scripts** | OLMS Core scripts | System configuration and startup |
| **X11 Support** | xorg-xauth + display manager | X11 authentication for GUI mode |

### 2. Quick Setup with Bootstrap (Recommended)

For contributors, the fastest way to get a working development environment is using the bootstrap script:

```bash
# Navigate to OLMS-Core directory
cd /path/to/OLMS-Core

# Run the bootstrap script (requires root)
sudo ./setup-env.sh

# Restart your session
# Then start OLMS for testing
./scripts/olms-startup.sh
```

**Benefits for Contributors:**
- Complete automated configuration in under 2 minutes
- No need to manually configure individual components
- Consistent setup across all development environments
- Includes all necessary permissions and limits for audio development

### 2. Realtime Privileges Configuration

**IMPORTANT**: OLMS requires proper realtime privileges for optimal audio performance. The system has been configured with enhanced realtime privileges management.

#### 2.1 Bootstrap Configuration (Recommended)

**For most users, the bootstrap script handles all realtime configuration automatically.** If you used the bootstrap method, realtime privileges are already configured and no additional setup is needed.

#### 2.2 Manual Configuration (Advanced Users)

If you need to configure realtime privileges manually (for example, if you used the Manual Installation method):

```bash
# Create required groups
sudo groupadd audio
sudo groupadd realtime

# Add user to groups
sudo usermod -aG audio,realtime $USER

# Install realtime configuration
sudo ln -sf /path/to/OLMS-Core/config/realtime/99-realtime.conf /etc/security/limits.d/99-realtime.conf

# Apply systemd realtime override
sudo ./scripts/olms-rt-override.sh

# Verify configuration
ulimit -r  # Should show 99
groups $USER  # Should show both audio and realtime
```

**Note:** The bootstrap script (`./setup-env.sh`) automates all these steps and is recommended for most users.


#### 2.3 X11 Authentication Setup

**IMPORTANT**: For GUI mode operation, X11 authentication must be properly configured:

```bash
# Install X11 authentication packages (included in PKGBUILD)
sudo pacman -S xorg-xauth lightdm

# Verify XAUTHORITY file exists and has content
ls -la ~/.Xauthority

# If XAUTHORITY is empty, copy from display manager
sudo xauth -f /run/lightdm/root/:0 extract - :0 | xauth merge -

# Test X11 connection
export DISPLAY=:0
xset q  # Should connect successfully
```

#### 2.4 Verification

After configuration, verify the realtime privileges are working:

```bash
# Check realtime priority limit
ulimit -r  # Should be 99

# Check memory lock limit
ulimit -l  # Should be unlimited

# Check group membership
groups $USER  # Should include audio and realtime

# Check systemd user limits
sudo systemctl --user show | grep -E "(LimitRTPRIO|LimitMEMLOCK)"

# Test with JACK
jackd -d alsa -d hw:0 -r 48000 -p 64 -n 3
```

#### 2.5 Troubleshooting

If you encounter realtime privilege issues:

1. **Check Group Membership**: Ensure user is in both `audio` and `realtime` groups
2. **Log Out/In**: Group changes require re-login to take effect
3. **Verify Configuration**: Check that `/etc/security/limits.d/99-realtime.conf` is properly installed
4. **Check Limits**: Verify `ulimit -r` returns 99
5. **Check X11 Authentication**: If using GUI mode, verify XAUTHORITY file and X11 connection

#### 2.6 Common Issues

| Issue | Solution |
| :--- | :--- |
| **ulimit -r shows 97 instead of 99** | Check realtime configuration file and user group membership, apply systemd override |
| **JACK fails with realtime priority errors** | Verify user is in audio and realtime groups, check ulimit settings, verify systemd limits |
| **Ardour processes can't get RT priority** | Ensure realtime privileges are configured correctly, check system limits |
| **X11 authentication errors in GUI mode** | Check XAUTHORITY file, copy from display manager if empty, verify DISPLAY variable |
| **"Cannot open display" errors** | Ensure X11 authentication is working, test with `xset q` command |

#### 2.6 Advanced Configuration: systemd Override

For Arch Linux systems where `ulimit -r` shows 97 instead of 99, you may need to configure systemd user limits:

```bash
# Apply systemd realtime override
sudo ./scripts/olms-rt-override.sh

# Verify the override
sudo systemctl --user show | grep -i limit
```

This creates `/etc/systemd/user.conf.d/10-olms-realtime.conf` with:
```ini
[Manager]
DefaultLimitRTPRIO=99
DefaultLimitMEMLOCK=infinity
```

#### 2.7 Security Considerations

**IMPORTANT**: The realtime configuration is designed with security in mind:

- **No wildcard fallback**: The configuration uses specific groups (`@audio`, `@realtime`) instead of `*` to prevent privilege escalation
- **Group-based access**: Only users in the `audio` or `realtime` groups receive realtime privileges
- **Verification required**: Always verify group membership and limits after configuration

#### 2.8 Post-Installation Verification

After installing the OLMS package, verify the complete realtime configuration:

```bash
# Check all realtime components
echo "=== Realtime Privileges Verification ==="
echo "1. Group membership:"
groups $USER | grep -E "(audio|realtime)" && echo "   ✓ User in required groups" || echo "   ✗ User not in required groups"

echo "2. PAM limits:"
ulimit -r && echo "   ✓ Realtime priority limit: $(ulimit -r)" || echo "   ✗ Realtime priority limit failed"

echo "3. Memory lock:"
ulimit -l && echo "   ✓ Memory lock limit: $(ulimit -l)" || echo "   ✗ Memory lock limit failed"

echo "4. systemd user limits:"
sudo systemctl --user show | grep -E "(LimitRTPRIO|LimitMEMLOCK)" | head -2

echo "5. Test JACK with realtime:"
jackd -d alsa -d hw:0 -r 48000 -p 64 -n 3 -P 99 2>&1 | grep -i "realtime\|rt\|priority" || echo "   ⚠ JACK test skipped (no audio hardware)"
```

### 2.6 Manual Testing Environment Setup

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

#### 2.4 Manual Machine Preparation with prepare_machine Script

For contributors working on Arch RT systems without the complete automated distribution, the `prepare_machine.sh` script provides a coordinated approach to manual system preparation. This script acts as a workflow orchestrator that ensures proper system configuration before audio engine startup.

**Concept Overview:**
The `prepare_machine.sh` script implements a sequential workflow that guarantees correct system configuration before audio engine initialization. It is designed specifically for contributors working on machines without automated configuration, providing a controlled environment for development and testing.

**Workflow Architecture:**
The script follows a structured approach with distinct phases:
- **Phase 1**: Real-time system optimization (RT tuning)
- **Phase 2**: Hardware configuration (IRQ pinning)
- **Phase 3**: CPU resource allocation (affinity settings)
- **Phase 4**: Audio engine coordination (ardour_launcher.sh invocation)

**Integration with ardour_launcher.sh:**
The `prepare_machine.sh` script functions as a wrapper that prepares the system environment before delegating audio engine startup to `ardour_launcher.sh`. This ensures that all system dependencies are properly configured before the audio engine is launched, maintaining the separation between system preparation and audio processing.

**Testing vs Production Workflow:**
- **Development Environment**: The `prepare_machine.sh` script enables step-by-step manual testing with full control over each preparation phase
- **Production Environment**: The same preparation steps are automated through systemd services for reliable, hands-off operation
- This approach provides a clear migration path from manual development workflows to automated deployment

**Contributor Benefits:**
- **Complete Control**: Contributors maintain full oversight of the system preparation process
- **Debugging Support**: Each phase can be monitored and debugged individually
- **Flexible Testing**: Individual preparation phases can be tested in isolation
- **Gradual Automation**: Provides a foundation for transitioning to fully automated deployment

This coordinated approach ensures that contributors can reliably prepare their development environment while maintaining compatibility with automated infrastructure.

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

#### 2.4 Manual Machine Preparation with prepare_machine Script

For contributors working on Arch RT systems without the complete automated distribution, the `prepare_machine.sh` script provides a coordinated approach to manual system preparation. This script acts as a workflow orchestrator that ensures proper system configuration before audio engine startup.

**Concept Overview:**
The `prepare_machine.sh` script implements a sequential workflow that guarantees correct system configuration before audio engine initialization. It is designed specifically for contributors working on machines without the automated distribution, providing a controlled environment for development and testing.

**Workflow Architecture:**
The script follows a structured approach with distinct phases:
- **Phase 1**: Real-time system optimization (RT tuning)
- **Phase 2**: Hardware configuration (IRQ pinning)
- **Phase 3**: CPU resource allocation (affinity settings)
- **Phase 4**: Audio engine coordination (ardour_launcher.sh invocation)

**Integration with ardour_launcher.sh:**
The `prepare_machine.sh` script functions as a wrapper that prepares the system environment before delegating audio engine startup to `ardour_launcher.sh`. This ensures that all system dependencies are properly configured before the audio engine is launched, maintaining the separation between system preparation and audio processing.

**Testing vs Production Workflow:**
- **Development Environment**: The `prepare_machine.sh` script enables step-by-step manual testing with full control over each preparation phase
- **Production Environment**: The same preparation steps are automated through systemd services for reliable, hands-off operation
- This approach provides a clear migration path from manual development workflows to automated production deployment

**Contributor Benefits:**
- **Complete Control**: Contributors maintain full oversight of the system preparation process
- **Debugging Support**: Each phase can be monitored and debugged individually
- **Flexible Testing**: Individual preparation phases can be tested in isolation
- **Gradual Automation**: Provides a foundation for transitioning to fully automated deployment

This coordinated approach ensures that contributors can reliably prepare their development environment while maintaining compatibility with the production automation infrastructure.

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
