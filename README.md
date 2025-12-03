# Open Live Mixing System (OLMS)

[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Status](https://img.shields.io/badge/Status-PoC%20In%20Progress-green.svg)](./issues/1)
[![Sample Rate](https://img.shields.io/badge/Sample%20Rate-48%20kHz-orange.svg)]()
[![RTL Target](https://img.shields.io/badge/RTL%20Target-%3C%205ms%20(Goal)-brightgreen.svg)]()
[![Stability](https://img.shields.io/badge/Stability-<2%20X--runs/hour-orange.svg)]()

**OLMS:** The Open Live Mixing System. A project aimed at transforming any compatible Mini-PC into a professional, dedicated digital mixing console. Built on a Real-Time Linux core, Ardour Headless, and JACK2/ALSA, it targets a Round-Trip Latency (RTL) of less than $< 5 \text{ ms}$ and **<2 X-runs/hour**. Control is managed via a responsive web UI/OSC bridge. Open Core (GPLv3). This project is currently in a Proof of Concept (PoC) phase.

**Official Website:**

👉 [https://openlivemixingsystem.org/](https://openlivemixingsystem.org/)

---

## 🚀 Architecture Overview and Key Concepts

For detailed technical specifications, refer to the [PROJECT_SPECS.md](https://github.com/Open-Live-Mixing-System-OLMS/Open-Live-Mixing-System/blob/main/PROJECT_SPECS.md) document.

OLMS is built on a Simplified 2-Layer Architecture that ensures stability and performance:

1.  **Web UI (Proprietary):** HTML5/JS/CSS-based user interface for controlling faders, mute, solo, pan, plugins, routing matrix, and metering.
2.  **Ardour Headless (GPL):** The main audio engine, configured with 48-channel templates (6 banks of 8 channels), bypassed plugins, and static routing. It integrates Lua Scripts for Session, Bank, Scene Management, and Dynamic I/O Patching.

### Block Track Management
The system supports multi-channel configurations via 8-track "banks." At startup, a script detects available physical ports and activates only the necessary banks (e.g., 16 I/O → Banks 1-2). Inactive banks have their tracks disabled in Ardour and hidden in the UI but can be activated at runtime via OSC. Pre-configured templates are available for 16ch, 24ch, 32ch, and 48ch.

### Real-Time Configuration and CPU Pinning
The system includes an advanced Real-Time (RT) kernel configuration. It focuses on simplifying IRQ pinning to a dedicated core for the audio card and using high RT priority for JACK/Ardour/Carla processes, rather than complex CPU core allocation. This also includes disabling features like Hyper-Threading and deep C-states to maximize stability and reduce latency.

---

## 🤝 Join the OLMS Community

We invite developers and audio enthusiasts to join the Open Live Mixing System project. If you're passionate about real-time audio and open-source technology, we'd love for you to contribute!

**Community Discussions:**

*   **Ardour Forum:** 👉 [https://discourse.ardour.org/t/open-live-mixing-system-dont-buy-a-mixer-do-it-instead/112632](https://discourse.ardour.org/t/open-live-mixing-system-dont-buy-a-mixer-do-it-instead/112632)
*   **LinuxMusicians Forum:** 👉 [https://linuxmusicians.com/viewtopic.php?p=180690](https://linuxmusicians.com/viewtopic.php?p=180690)
*   **Reddit r/linuxaudio:** 👉 [https://www.reddit.com/r/linuxaudio/comments/1pc8g1p/open_live_mixing_system_dont_buy-a-mixer-do-it/](https://www.reddit.com/r/linuxaudio/comments/1pc8g1p/open_live_mixing_system_dont-buy-a-mixer-do-it/)

---

## THE OPEN LIVE MIXING SYSTEM (OLMS) MANIFESTO

### Vision: Redefining Digital Mixing with Open Source

> "Our central idea is to transform a common, inexpensive computer—ideally a **fanless Mini-PC with compatible USB audio interfaces**—into a dedicated, reliable rack-mount digital mixer, entirely controllable via Wi-Fi network."

OLMS offers an open-source alternative, aiming to replicate the **"power-on-and-mix" reliability** of professional systems, primarily through a custom, self-installing Linux operating system (the OLMS distro), operating at a **fixed Sample Rate of 48 kHz**.

### The Technical Challenge: Real-Time Audio

We are committed to providing stable multi-channel live audio with **RTL below 5ms** and **less than 2 audible audio glitches** (X-runs) **per hour**.

Our technology stack is built on solid open-source foundations:
*   **Base Platform:** A custom Linux distribution with a **Real-Time (RT) kernel** for minimal latency.
*   **Audio Core:** **Ardour** (DAW/Mixer) running in **headless mode** (without GUI), used as a stable LV2 host.
*   **Audio Server:** **JACK2 (Primary) / ALSA Backend (Fallback)**, configured for maximum Real-Time (RT) priority.
*   **Control:** A complete, responsive, and touch-friendly **Web Browser** user interface (HTML5/JS) communicating with Ardour via an **OSC Bridge Server**.
*   **Core Logic:** **Lua Scripts (integrated within Ardour)** manage advanced features like Session, Bank, Scene Management, and Dynamic I/O Patching.

### The Open Core Pledge and Commercial Sustainability

The entire critical part of the mixing system—the OLMS Distro, the RT Kernel, JACK/ALSA configuration, Ardour Headless, Lua Scripts, the Web GUI, and the OSC Bridge Server—is **100% Open Source** and released under the **GPLv3 License**.

Our path to sustainability is a **Hybrid Open Core Model**. The commercial strategy focuses on advanced, high-value features (e.g., Anti-Feedback System, Live Auto-Mixer) and the sale of **Service Level Agreements (SLA)** and **Officially Certified Hardware** (Mini-PCs guaranteed to meet RTL/X-run targets under full load). This model ensures stability and continuous development for the free core.

### The Final Validation: X-run Stability

OLMS's credibility rests on meeting rigorous RT metrics in its current PoC phase:
1.  **Latency:** Total Round-Trip Latency (RTL) must consistently be $< 5 \text{ ms}$ at 48 kHz.
2.  **Stability:** The system MUST achieve less than 2 X-runs per hour during one hour of stress testing under full load conditions.
