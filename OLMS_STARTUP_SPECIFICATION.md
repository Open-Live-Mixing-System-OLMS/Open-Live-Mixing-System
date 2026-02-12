# OLMS Startup Process Specification

## Overview

This document provides a comprehensive technical specification of the Open Live Mixing System (OLMS) startup process, detailing the complete bootstrap operations and system initialization sequence. The specification describes the behavior without including actual code implementation.

## System Architecture

### Core Design Principles

The OLMS startup system follows a multi-phase approach designed for real-time audio processing with the following key principles:

1. **Modular Phase-Based Execution**: The startup process is divided into 8 distinct phases, each with specific responsibilities
2. **User-Centric Privilege Management**: Smart user detection and privilege handling for both direct execution and sudo scenarios
3. **Hardware-Agnostic Configuration**: Universal compatibility across different Linux distributions and hardware configurations
4. **Real-Time Optimization**: Comprehensive system tuning for low-latency audio processing
5. **Robust Error Handling**: Graceful degradation and fallback mechanisms throughout the process

### System Components

- **Orchestrator**: Central control script that manages the entire startup sequence
- **Phase Scripts**: Individual scripts handling specific aspects of system initialization
- **Bootstrap System**: Initial configuration and permission setup
- **Runtime Managers**: Dynamic permission and resource management tools

## Startup Process Phases

### Phase 0: Pre-Startup and Process Management

#### 0.1 Audio Environment Nuclear Cleanup
**Purpose**: Complete audio system reset and preparation

**Operations**:
- Aggressive termination of all audio processes (JACK, PipeWire, PulseAudio, Ardour)
- Comprehensive socket file cleanup across multiple directories (/tmp, /dev/shm, /var/run)
- Shared memory IPC cleanup (semaphores and memory segments)
- Hardware reset through kernel module unloading/reloading
- USB audio device detection with kernel-class method
- Temporary directory cleanup with aggressive file removal

**Key Features**:
- Multi-stage process termination (SIGTERM → SIGKILL with sudo escalation)
- Smart USB device detection using /proc/asound/cards and SysFS
- Hardware reset through snd-usb-audio, snd_hda_intel, snd_hda_codec, snd_seq module management
- USB device wait timeout with 30-second detection window

#### 0.2 Lock Management
**Purpose**: Process synchronization and conflict prevention

**Operations**:
- PID file creation and management
- Process termination with forced cleanup
- Lock file verification and automatic cleanup
- Graceful Ardour session closing with save functionality

**Key Features**:
- Smart lock file handling with automatic cleanup on conflicts
- Graceful Ardour session termination with SIGUSR1 save signal
- Multi-stage termination (SIGTERM → SIGKILL) with timeout handling
- Session file integrity verification after termination

### Phase 1: Real-Time System Optimization

#### Purpose
Comprehensive system tuning for real-time audio processing requirements

#### Operations

**Kernel Parameter Configuration**:
- RT runtime allocation (95% for production, 80% for testing, 60% for light mode)
- RT period configuration (1 second standard)
- CPU migration cost optimization
- Wakeup granularity tuning

**CPU Governor Management**:
- Performance governor enforcement across all CPU cores
- Sysfs permission verification and correction
- Minimum frequency locking to maximum frequency
- Turbo Boost disabling for consistent performance

**Power Management Configuration**:
- C-state disabling (C3 and C6 states) for all CPU cores
- irqbalance status verification
- Hardware power saving feature management

**Real-Time Privilege Configuration**:
- Memory locking limits (unlimited)
- Real-time priority limits (99)
- User group membership verification (realtime, audio groups)

**Key Features**:
- Mode-based configuration (prod/test/light) with different RT allocation strategies
- Dynamic CPU core detection and configuration
- Comprehensive permission management for sysfs files
- User privilege verification with session restart requirements

### Phase 2: Hardware Configuration

#### Purpose
Hardware-specific configuration and optimization

#### Operations

**CPU Affinity Management**:
- System process isolation on Core 0
- IRQ pinning to Core 1
- Audio processing isolation on remaining cores (2-N)

**Hardware Detection**:
- USB audio device identification
- ALSA card detection and configuration
- Hardware capability assessment

**IRQ Management**:
- USB controller IRQ pinning to dedicated core
- IRQ affinity verification
- Interrupt handling optimization

**Key Features**:
- Dynamic core allocation based on system topology
- Hardware-specific optimization profiles
- IRQ conflict prevention and resolution

### Phase 3: JACK Server Initialization (Fixed Strategy)

#### Purpose
JACK audio server startup with anti-zombie mode and connection stability

#### Operations

**Phase 1: Bit-Depth Detection**:
- Safe buffer configuration (256:3) for hardware testing
- Dynamic hardware detection via /sys/class/sound/card*
- Bit-depth testing sequence (32-bit → 24-bit → 16-bit fallback)
- Hardware ceiling detection for optimal performance

**Phase 2: Buffer Detection**:
- Latency optimization through buffer size testing
- Configuration testing sequence (32:2 → 32:3 → 64:2 → 64:3 → etc.)
- Stability verification with extended monitoring

**Server Startup**:
- JACK daemon launch with real-time priority
- Socket permission management and symbolic link creation
- Connection stability verification with multi-phase validation

**Key Features**:
- Two-phase detection strategy for optimal hardware configuration
- Anti-zombie mode with extended stability monitoring (10-second validation)
- Comprehensive socket permission management
- Fallback to dummy backend if hardware detection fails

### Phase 4: X11 Environment & Display Management

#### Purpose
Graphics environment configuration for Ardour DAW operation

#### Operations

**Display Detection**:
- Multi-method display detection (socket files, xauth entries, common values)
- Wayland/XWayland compatibility
- Nested environment detection (VNC, X2Go, etc.)
- Process-based display detection from active X11 processes

**XAUTHORITY Configuration**:
- .Xauthority file location and permission management
- Root-to-user transition configuration
- X11 access permission granting

**Runtime Directory Management**:
- XDG_RUNTIME_DIR configuration per target user
- D-Bus session setup with private abstract sockets
- User-specific environment isolation

**Permissions Configuration**:
- X11 permission management for root execution scenarios
- xhost access configuration
- Graphics environment isolation

**Key Features**:
- Universal display detection supporting multiple graphics environments
- Robust X11 permission management for sudo execution scenarios
- Private D-Bus session management per user
- Headless mode support with Xvfb fallback

### Phase 5: Ardour DAW Startup

#### Purpose
Ardour Digital Audio Workstation initialization with session adaptation

#### Operations

**Session Adaptation**:
- JACK port detection and mapping
- Session file backup and modification
- Port mapping validation and verification
- Session reload with adapted configuration

**User Environment Transition**:
- Target user detection and environment setup
- Permission management for audio files and directories
- Environment variable configuration for JACK integration

**Process Management**:
- Ardour startup with real-time priority
- CPU affinity enforcement
- Process monitoring and stability verification

**Headless Mode Support**:
- Xvfb virtual display management
- Headless Ardour configuration
- Background process management

**Key Features**:
- Dynamic session adaptation based on available hardware
- Robust user environment transition with privilege management
- Headless operation support for server environments
- Comprehensive error handling and fallback mechanisms

### Phase 6: Final System Report

#### Purpose
Comprehensive system verification and status reporting

#### Operations

**Process Verification**:
- System process isolation verification (Core 0)
- JACK server status and configuration verification
- Ardour DAW status and CPU affinity verification
- IRQ pinning verification

**Technical Data Extraction**:
- Real-time JACK configuration analysis
- Audio hardware information extraction
- Latency calculation and verification
- Socket file and port status verification

**System Summary**:
- Architecture summary with core allocation
- Performance metrics and status indicators
- Error and warning count reporting
- Operational readiness assessment

**Key Features**:
- Comprehensive system state verification
- Real-time technical data extraction and analysis
- Performance metrics calculation and reporting
- Operational readiness assessment with detailed logging

## Bootstrap Operations

### Initial System Configuration

#### Purpose
One-time system setup and configuration for OLMS operation

#### Operations

**User Environment Detection**:
- Smart user detection for sudo and direct execution scenarios
- Home directory verification and creation
- User privilege verification

**Directory Structure Creation**:
- OLMS configuration directories
- Session template directories
- Runtime permission management directories

**Udev Rules Generation**:
- USB device permission rules
- JACK socket permission rules
- CPU governor permission rules
- IRQ management permission rules
- taskset/chrt permission rules

**System Configuration Files**:
- Real-time limits configuration (/etc/security/limits.d/)
- Kernel parameter configuration (/etc/sysctl.d/)
- PAM configuration for limit loading
- User group membership configuration

**Runtime Permission Management**:
- Sysfs permission rules (/etc/tmpfiles.d/)
- Direct sysfs permission application
- Runtime permission manager installation
- Automatic startup configuration

**X11 Environment Setup**:
- Display environment variable configuration
- XAUTHORITY file management for root transitions
- xhost permission configuration
- Graphics environment isolation

**Key Features**:
- Universal compatibility across Linux distributions
- Comprehensive permission management for all system components
- Automatic configuration file generation
- Runtime permission management with automatic startup
- X11 environment configuration for graphics compatibility

## Error Handling and Recovery

### Multi-Level Error Handling

#### Phase-Level Error Handling
- Individual phase error detection and reporting
- Graceful degradation with fallback mechanisms
- Phase-specific error recovery procedures

#### System-Level Error Handling
- Process conflict detection and resolution
- Resource availability verification
- Hardware compatibility checking

#### User-Level Error Handling
- Permission error detection and automatic correction
- Configuration error detection and automatic repair
- User environment error detection and correction

### Recovery Mechanisms

#### Automatic Recovery
- Process termination and restart
- Configuration file regeneration
- Permission restoration

#### Manual Recovery
- Detailed error reporting with actionable information
- Configuration verification tools
- Manual intervention guidance

## Performance Optimization

### Real-Time Performance

#### CPU Optimization
- Core isolation for system, IRQ, and audio processing
- CPU governor enforcement
- C-state disabling for consistent performance
- Turbo Boost disabling for stable clock speeds

#### Memory Optimization
- Memory locking for real-time processes
- Shared memory optimization
- Memory allocation strategy optimization

#### I/O Optimization
- IRQ pinning for audio devices
- USB device optimization
- Audio buffer optimization

### Latency Reduction

#### Audio Latency
- JACK buffer size optimization
- Period count optimization
- Sample rate optimization
- Hardware-specific latency tuning

#### System Latency
- Process priority optimization
- CPU affinity optimization
- Interrupt handling optimization

## Security Considerations

### Permission Management
- Minimal privilege escalation
- User-specific permission management
- Secure file permission handling
- Process isolation

### System Security
- Secure configuration file management
- Safe process execution
- Protected system resource access
- User environment isolation

## Compatibility Matrix

### Supported Linux Distributions
- Arch Linux (primary development platform)
- Ubuntu/Debian variants
- Fedora/CentOS/RHEL variants
- openSUSE variants
- Other systemd-based distributions

### Supported Hardware
- USB audio interfaces (universal support)
- PCI audio cards
- Integrated audio (with disable capability)
- Professional audio interfaces
- Budget audio interfaces

### Supported Graphics Environments
- X11 with various window managers
- Wayland with XWayland compatibility
- Headless operation with Xvfb
- Virtual display environments

## Configuration Management

### Configuration Files
- /etc/udev/rules.d/99-olms-*.rules (device permissions)
- /etc/security/limits.d/99-olms-realtime.conf (user limits)
- /etc/sysctl.d/99-olms-rt.conf (kernel parameters)
- /etc/tmpfiles.d/olms-cpu.conf (sysfs permissions)
- /etc/profile.d/olms-x11.sh (X11 environment)

### Runtime Configuration
- User-specific configuration in ~/.olms/
- Session-specific configuration in session directories
- Runtime permission management
- Dynamic hardware detection and configuration

### Configuration Verification
- Configuration file integrity checking
- Permission verification
- System compatibility verification
- Performance optimization verification

## Monitoring and Diagnostics

### System Monitoring
- Process status monitoring
- Resource usage monitoring
- Performance metric collection
- Error condition detection

### Diagnostic Tools
- Configuration verification tools
- Performance analysis tools
- Error diagnosis tools
- System health monitoring

### Logging and Reporting
- Comprehensive system logging
- Performance metric reporting
- Error condition reporting
- Operational status reporting

## Maintenance and Updates

### System Maintenance
- Configuration file updates
- Permission management updates
- System compatibility updates
- Performance optimization updates

### Update Procedures
- Configuration migration procedures
- Compatibility verification procedures
- Performance verification procedures
- Error condition resolution procedures

### Troubleshooting
- Common issue resolution
- Performance problem diagnosis
- Configuration problem resolution
- Hardware compatibility issues

## Conclusion

The OLMS startup process represents a comprehensive, multi-phase system initialization designed for professional real-time audio processing. The specification details a robust architecture that provides universal compatibility, comprehensive error handling, and optimal performance tuning while maintaining security and stability throughout the entire startup sequence.

The system's modular design allows for individual phase testing and debugging, while the comprehensive error handling ensures reliable operation across diverse hardware and software environments. The bootstrap operations provide a solid foundation for system operation, with automatic configuration and permission management reducing the complexity of system setup and maintenance.