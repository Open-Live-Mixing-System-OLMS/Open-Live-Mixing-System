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
