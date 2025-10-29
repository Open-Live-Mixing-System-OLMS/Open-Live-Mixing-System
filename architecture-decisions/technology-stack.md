# Technology Stack (Tech Stack) and Components

## 2.1. Operating System and Audio Server (PipeWire)

**Base Distribution:** Linux with an emphasis on lightness and stability.

* **Kernel:** Use of a **Real-Time (RT) Kernel** to guarantee the minimum possible latency (target: less than $10 \text{ ms}$ round-trip).
* **Main Audio Server:** **PipeWire (PW)** replaces JACK. PipeWire is configured to operate with maximum Real-Time (RT) priorities to minimize latency.
* **Ardour Integration:** Ardour communicates directly with PipeWire (through its native backend).

## Language Choice

There are a few options here:

* Python
* Rust
* Golang
* C
* C++

The primary concern is low latency and mature bindings with Pipewire. I have spent the best part of an evening trying to get a simple Pipewire client running in multiple languages. I really want to use Rust, but the bindings are not in a good state yet. There was no combination of Rust/Pipewire that I got to successfully compile.

Python has good bindings, but performance is a concern. Latency 10ms seem out of reach. It would be absolutely fine for management tools, but not for anything that sits in the audio path. Golang has some bindings, but they are not very mature. C and C++ have the best support for Pipewire, but I am not very comfortable with them.

Fortunately, we do not care if I am comfortable with the language, as long as it works well. After all, I am Dev**Rel** not Dev, so I propose we go with C for anything that is within the audio path. It has the best support for Pipewire, I can manage to write some basic code in it (can at least review it) and many good Devs know C. I really wanted to suggest Rust because I think it would attract more devs, but the bindings are just not mature enough at this stage.
