# Open Live Mixing System (OLMS) - Complete Architecture v1.1

## Technology Stack
*   **OS**: Linux RT (Arch) with PREEMPT_RT kernel
*   **Audio Layer**: PipeWire + PipeWire-plumber
*   **Engine**: Ardour 8 Headless
*   **Protocol**: OSC
*   **Interface**: Custom Web UI (HTML5/JS/CSS)
*   **Backend UI**: Node.js or Python server with OSC library

## Current Development Stack (PoC - Proof of Concept)
*   **Environment**: VirtualBox on Arch Linux
*   **Virtual Audio (UPDATED)**: PipeWire Null-Sink with 16 virtual Mono channels for precise routing, or ALSA loopback with advanced ALSA/PipeWire configuration.
*   **Temporary GUI**: XFCE4 + LightDM (to be removed post-template)
*   **OSC Testing**: Open Stage Control (standalone app)
*   **Vibe Coding**: Cline + Gemini for UI and automation scripts

## 3-Layer Architecture
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
│   MIDDLEWARE LAYER (Proprietary)    │
│   - Node.js/Python Daemon           │
│   - Session state management        │
│   - Add-on system                   │
│   - Scene/snapshot manager          │
│   - Bank manager (enable/disable)   │
└──────────────┬──────────────────────┘
               │ Standard OSC
┌──────────────▼──────────────────────┐
│   ARDOUR HEADLESS (GPL)             │
│   - 48ch Template (6 banks × 8ch)   │
│   - Plugins in bypass               │
│   - Static routing                  │
│   - Tracks can be disabled per bank │
└──────────────┬──────────────────────┘
               │ JACK API
┌──────────────▼──────────────────────┐
│   PIPEWIRE + PLUMBER (GPL)          │
│   - Hardware I/O management         │
│   - Automatic audio connections     │
└─────────────────────────────────────┘
```

## Block Track Management (Banks)
**Structure:**
*   Bank 1: Tracks 1-8
*   Bank 2: Tracks 9-16
*   Bank 3: Tracks 17-24
*   Bank 4: Tracks 25-32
*   Bank 5: Tracks 33-40
*   Bank 6: Tracks 41-48

**On Startup:** Script queries PipeWire to detect available physical ports. Automatically activates only necessary banks (e.g., 16 I/O → Bank 1-2).
**Inactive banks**: Tracks disabled in Ardour, hidden in UI.
**Runtime activation via OSC**: `/ardour/track/enable [bank_id]`

### Pre-configured Multiple Templates:
*   16ch (2 banks)
*   24ch (3 banks)
*   32ch (4 banks)
*   48ch (6 banks)

## RT Configuration and CPU Pinning
### Kernel Boot Parameters
`isolcpus=0,1 nohz_full=0,1 rcu_nocbs=0,1 threadirqs intel_pstate=disable processor.max_cstate=1`

### Dynamic Core Allocation System (UPDATED LOGIC)
The system automatically detects P-cores and E-cores to define the following allocation profiles, ensuring maximum isolation for critical audio processing. Carla is hosted as a separate, pinned process for heavy reverb processing.

| P-cores Total | Core Isolation (IRQ/PW/OS) | Carla (Heavy Reverbs) | Ardour (Mix Engine) | Max Heavy Reverbs Supported |
| :------------ | :------------------------- | :-------------------- | :------------------ | :-------------------------- |
| 4             | Core 0 (IRQ), Core 1 (PW)  | None/Internal         | Core 2-3 (2 cores)  | 0 (Convolutions Disabled)   |
| 6             | Core 0 (IRQ), Core 1 (PW), Core 2 (OS) | Core 3 (1 core) | Core 4-5 (2 cores)  | 1-2                         |
| 8             | Core 0 (IRQ), Core 1 (PW), Core 2 (OS) | Core 3-4 (2 cores) | Core 5-7 (3 cores)  | 4                           |
| 12+           | Core 0 (IRQ), Core 1 (PW), Core 2 (OS) | Core 3-4 (2 cores) | Core 5-11+ (7+ cores)| 4+                          |

*   **E-cores (if present)**: Dedicated to Middleware, background tasks, and non-RT processing.

### CPU Core Assignment (Implementation Details)
*   **IRQ Pinning (P-cores):**
    *   Core 0-1: Audio card IRQ (isolated)
    *   `echo 03 > /proc/irq/[audio_irq]/smp_affinity`
*   **Process Pinning (Dynamic):**
    *   PipeWire: Pinned to its isolated core (e.g., `taskset -c 1` or `2`) + `chrt -f 85`
    *   Carla (if enabled): Pinned to dedicated cores (e.g., `taskset -c 3,4`) + `chrt -f 78`
    *   Ardour headless: Pinned to the remaining contiguous isolated P-cores (e.g., `taskset -c 5-7`) + `chrt -f 75`

### Critical Disabling
*   Hyper-Threading (Intel)
*   CPU frequency scaling → performance governor
*   Deep C-states (>C1)
*   Swap during runtime (vm.swappiness = 10)

### PipeWire Config (`/etc/pipewire/pipewire.conf`)
```
default.clock.quantum = 128
default.clock.min-quantum = 128
default.clock.max-quantum = 256
default.clock.rate = 48000
```
*   **Buffer size**: fixed 128 or 256 samples (no runtime switching)

### Implementation Workflow for Dynamic Allocation
1.  `/usr/local/bin/olms-detect-cpu`: Reads CPU topology and generates JSON output.
2.  `/etc/olms/cpu-allocation.conf`: Generated by detect script, mapping IRQ/PipeWire/Ardour/Carla to specific cores based on the table above.
3.  `/usr/local/bin/olms-apply-affinity`: Executes `taskset`, `chrt`, and writes to `/proc/irq/*/smp_affinity`.
4.  `/etc/default/grub modifier script`: Adds `isolcpus=` dynamically based on the detected topology (Requires reboot after first run).
5.  `systemd service`: `olms-affinity.service`: Executes `olms-apply-affinity` on boot (Before: `pipewire.service`, `ardour.service`).

## Business Model
### GPL Core (Free):
*   OS + Configured Ardour headless
*   Startup scripts, basic routing, bank management
*   Minimal web UI (fader/mute/solo/bank selector)
*   Open source plugins (a-*, LSP, x42, Calf)

### Proprietary Add-on Marketplace:
*   Premium LV2/VST audio plugins
*   External middleware modules (scene manager, automations, multi-user)
*   Advanced UI themes and layouts
*   Feature packs (advanced routing, premium metering, bank presets)

## Development
*   **Phase 1 - PoC (2-3 months)**: Validation with Open Stage Control + Ardour headless. Latency/xruns/stability test on 2 banks (16ch). Runtime enable/disable banks validation. Environment: VirtualBox + ALSA loopback + Ardour GUI. **Deliverable**: Functional 16ch template with stable OSC control.
*   **Phase 2 - Template (1-2 months)**: 48ch session with 6 pre-configured banks. Dynamic routing and bank activation scripts. IRQ pinning and CPU tuning scripts.
*   **Phase 3 - UI Custom (2-3 months)**: Proprietary web UI development using vibe coding (Cline + Gemini). Components: fader, metering, plugin controls, routing matrix, bank selector.
*   **Phase 4 - Marketplace (3-4 months)**: Add-on system, licensing (hardware fingerprint + online validation), documentation.

## Immediate PoC Roadmap
### 1. Base Setup (Day 1)
*   ✓ Arch Linux installed
*   ✓ XFCE4 + LightDM for temporary GUI
*   Install Ardour 8 with GUI
*   Configure PipeWire: 128/256 buffer, 48kHz
*   Activate ALSA loopback: `sudo modprobe snd-aloop`

### 2. Template in GUI (Days 2-3)
*   Create 16 audio track session (2 banks)
*   Routing: Assign loopback inputs to tracks 1-16
*   Master bus + 2-3 base LV2 plugins in bypass
*   Save template: "OLMS_16ch_2banks"

### 3. OSC Test (Days 4-6)
*   Enable OSC in Ardour preferences
*   Install Open Stage Control
*   Create test fader for `/strip/gain`, `/strip/mute`, `/strip/solo`
*   Verify real-time control without xruns

### 4. Stability Test (Days 7-9)
*   Play audio on all 16 tracks
*   OSC stress test under load
*   Monitor xruns with `pw-top`
*   Target: <2 xruns/hour

### 5. Headless Validation (Day 10)
*   Test: `ardour8 --no-splash --template=OLMS_16ch_2banks.template`
*   Confirm OSC functions without GUI

## Target Hardware
*   **Entry**: N100, 8GB RAM → 2 banks (16ch)
*   **Mid**: i5-12450H, 16GB RAM → 4 banks (32ch)
*   **Pro**: i7/Ryzen7+, 32GB RAM → 6 banks (48ch)

## Expected Performance
*   **CPU usage**:
    *   2 active banks: 3-8%
    *   4 active banks: 8-15%
    *   6 active banks: 12-25%
*   **RTT Latency**: 5-10ms @ 128 samples
*   **Xruns**: <2/hour with correct tuning
*   **RAM overhead per inactive bank**: ~50-100MB

## Essential Scripts to Develop
*   `irq_pinning.sh` - Configures IRQ affinity automatically
*   `bank_manager.sh` - Enable/disable banks via OSC
*   `hardware_detect.sh` - Detects I/O and suggests templates
*   `rt_tuning.sh` - Applies kernel/CPU optimizations
*   `ardour_launcher.sh` - Launches Ardour with correct RT parameters

## Key Architectural Choices
*   **Why VirtualBox for PoC**: Zero hardware investment until concept is validated with contributors.
*   **Why temporary GUI**: Manual template creation + visual OSC debugging, removed in production.
*   **Why ALSA loopback/Null-Sink**: Simulates 16 distinct mono I/O channels for routing/stability testing, overcoming PipeWire's channel grouping issues.
*   **Why Open Stage Control**: Quick drag-and-drop OSC testing before developing custom UI.
*   **Why template manual first**: Understanding the Ardour workflow before automating with scripts.
*   **Why dedicated cores for Carla (UPDATED)**: Heavy convolution reverb plugins require guaranteed, isolated CPU time. Pinning Carla to 1-2 dedicated P-cores ensures maximum stability for the core mix engine (Ardour) while enabling high-quality effects.
