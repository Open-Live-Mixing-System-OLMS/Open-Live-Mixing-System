# OLMS Scripts Implementation Summary

## Overview

This document summarizes the implementation of the OLMS machine preparation scripts based on the OLMS specifications. The scripts follow a hierarchical architecture where `olms-startup.sh` acts as the main coordinator, calling specialized scripts for different aspects of system preparation.

## Implemented Scripts

### 1. Main Coordinator
- **`scripts/olms-startup.sh`** - Primary startup script that coordinates the complete system initialization
  - **Phase 0**: Audio Cleanup (terminates existing audio processes)
  - **Phase 1**: RT Optimization + Stop IRQ Balance (executes `rt_tuning.sh`)
  - **Phase 2**: Hardware IRQ Pinning (executes `irq_pinning.sh`)
  - **Phase 3**: Machine Preparation (executes `prepare_machine.sh`)
  - **Phase 4**: Audio Engine Startup (executes `audio_engine.sh` in background)
  - **Phase 5**: CPU Affinity Configuration (executes `olms-apply-affinity.sh`)

### 2. Specialized Orchestrators
- **`scripts/prepare_machine.sh`** - Machine preparation orchestrator for system configuration
  - Phase 1: Real-time System Optimization (calls `rt_tuning.sh`)
  - Phase 2: Hardware Configuration (calls `irq_pinning.sh`)
  - Phase 3: CPU Resource Allocation (calls `olms-apply-affinity.sh`)
  - Phase 4: Audio Engine Coordination (returns control to `olms-startup.sh`)

### 3. Individual Phase Scripts

#### Phase 1: Real-time System Optimization
- **`scripts/rt_tuning.sh`** (existing) - CPU/Kernel optimizations
  - Configures kernel parameters for real-time performance
  - Sets CPU governor to performance mode
  - Disables power-saving states (C-states)
  - Configures memory locking limits

#### Phase 2: Hardware Configuration  
- **`scripts/irq_pinning.sh`** (newly created) - Hardware IRQ pinning
  - Detects audio hardware and identifies IRQ numbers
  - Pins audio card IRQs to dedicated CPU cores
  - Configures IRQ affinity for optimal audio performance
  - Verifies IRQ pinning configuration

#### Phase 3: CPU Resource Allocation
- **`scripts/olms-apply-affinity.sh`** (newly created) - CPU affinity configuration
  - Sets CPU affinity for audio processes (JACK, Ardour)
  - Configures process priorities (nice/renice values)
  - Applies RT priorities (SCHED_FIFO) to audio processes
  - Allocates dedicated CPU cores for audio processing
  - Verifies CPU affinity settings

#### Phase 4: Audio Engine Coordination
- **`scripts/audio_engine.sh`** (renamed from ardour_launcher.sh) - Audio engine launch
  - Starts JACK2 server with optimized parameters
  - Launches Ardour as JACK client (not master)
  - Supports testing mode (with GUI) and production mode (headless)
  - Handles virtual audio backend when no hardware is available
  - Configures X11/Xvfb environment for GUI/headless modes
  - Provides comprehensive error handling and status reporting

### 4. Additional System Scripts

#### System Monitoring
- **`scripts/disk_guard.sh`** (newly created) - Disk space monitoring
  - Monitors disk space on critical paths (/var, /tmp, /home)
  - Provides warning and critical thresholds (configurable)
  - Performs automatic cleanup of temporary files and logs
  - Runs as a background service for continuous monitoring

#### Setup and Configuration
- **`scripts/setup_realtime_privileges.sh`** (existing) - Realtime privileges setup
  - Configures realtime scheduling and memory locking
  - Adds users to realtime group
  - Creates appropriate system limits configuration

- **`scripts/usb_audio_session_adapter.sh`** (existing) - USB audio session adaptation
  - Adapts Ardour session to detected USB audio devices
  - Automatically detects USB audio card port names
  - Maps system:capture/playback connections to actual names

### 5. Launchers
- **`scripts/launchers/olms-test-launcher.sh`** - Test environment launcher
  - Launches system in testing mode with GUI
  - Provides visual feedback and debugging capabilities
  - Includes detailed system monitoring

- **`scripts/launchers/olms-prod-launcher.sh`** - Production environment launcher
  - Launches system in production mode (headless)
  - Optimized for automated operations
  - Minimal user interaction required

### 6. Additional Scripts (Based on Current Analysis)

#### CPU Shielding
- **`scripts/cpu_shielding_v2.sh`** - CPU shielding implementation using cgroup v2
  - Creates dedicated CPU groups for system and audio processes
  - Uses cgroup v2 cpuset controller for process isolation
  - Architecture: Core 0=System, Core 1=IRQ, Core 2+=Audio Processing
  - Moves existing processes to appropriate cgroups
  - Provides dynamic migration for audio processes

#### System Verification
- **`scripts/olms-final-verification.sh`** - Comprehensive system verification
  - Verifies kernel RT parameters
  - Checks CPU governor settings
  - Validates realtime privileges
  - Confirms IRQ pinning configuration
  - Verifies CPU affinity for audio processes
  - Checks realtime priorities
  - Validates audio system status (JACK/Ardour)
  - Monitors system resources
  - Provides detailed reporting with verbose output option

#### Audio Virtualization
- **`scripts/audio_virtual.sh`** - Virtual audio backend setup
  - Configures virtual audio devices for testing
  - Handles JACK dummy backend setup
  - Provides fallback audio configuration
  - Supports headless operation without hardware

#### System Reset
- **`scripts/olms-hard-reset.sh`** - Complete system reset
  - Terminates all audio processes
  - Cleans up JACK and audio environment
  - Resets CPU affinity and cgroup assignments
  - Restores system to clean state

#### Audio Testing
- **`scripts/olms-audio-test.sh`** - Audio system testing
  - Tests JACK functionality
  - Verifies Ardour connectivity
  - Performs audio loopback tests
  - Validates system performance

## Architecture Benefits

### Modular Design
- **Separation of Concerns**: Each script handles a specific aspect of system preparation
- **Reusability**: Scripts can be used individually or in combination
- **Maintainability**: Easier to modify and test individual components
- **Debugging**: Issues can be isolated to specific phases

### Synchronization with Systemd Services
The scripts are designed to work both in development/testing mode and production mode:

**Development Mode (Manual):**
```bash
./scripts/olms-startup.sh --test
```

**Production Mode (Systemd):**
```bash
systemctl enable olms-rt-tuning.service
systemctl enable olms-irq-pinning.service  
systemctl enable olms-affinity.service
systemctl enable ardour.service
systemctl enable olms-disk-guard.service
```

### Error Handling and Status Reporting
- Comprehensive error checking at each phase
- Clear status messages with timestamps
- Graceful fallback when individual scripts are missing
- Detailed help and usage information
- Retry mechanisms and fallbacks for stubborn processes

## OLMS CPU Architecture (4+ Core)

- **Core 0**: Operating system, basic services, general I/O
- **Core 1**: IRQ controller for USB audio card (IRQ pinning)
- **Core 2+**: JACK2 processes and Ardour DSP threads (CPU affinity)

## Startup Modes

1. **Test Mode**: Launch with GUI for development and monitoring
2. **Production Mode**: Headless launch for automated operations
3. **Virtual Mode**: Virtual audio backend when no hardware is available

## Usage Examples

### Complete System Startup
```bash
# Launch complete system in testing mode with GUI
./scripts/olms-startup.sh

# Launch complete system in production mode (headless)
./scripts/olms-startup.sh --prod

# Launch complete system with virtual audio (no hardware required)
./scripts/olms-startup.sh --virtual

# Launch complete system testing mode with virtual audio
./scripts/olms-startup.sh --test --virtual
```

### Machine Preparation Only
```bash
# Launch machine preparation in testing mode
./scripts/prepare_machine.sh

# Launch machine preparation in production mode
./scripts/prepare_machine.sh --prod

# Launch machine preparation with virtual audio
./scripts/prepare_machine.sh --virtual
```

### Audio Engine Only
```bash
# Launch audio engine in testing mode
./scripts/audio_engine.sh

# Launch audio engine in production mode
./scripts/audio_engine.sh --prod

# Launch audio engine with virtual audio
./scripts/audio_engine.sh --virtual
```

### Individual Script Usage
```bash
# Test IRQ pinning only
sudo ./scripts/irq_pinning.sh --cpu-core 2

# Test CPU affinity only
sudo ./scripts/olms-apply-affinity.sh --audio-core 1

# Monitor disk space
./scripts/disk_guard.sh --interval 30 --warning 80 --critical 90

# Configure CPU shielding
sudo ./scripts/cpu_shielding_v2.sh --system-core 0 --audio-cores 2,3

# Run system verification
sudo ./scripts/olms-final-verification.sh --verbose

# Test audio system
./scripts/olms-audio-test.sh

# Perform hard reset
./scripts/olms-hard-reset.sh
```

### Launchers
```bash
# Test environment launcher
./scripts/launchers/olms-test-launcher.sh

# Production environment launcher
./scripts/launchers/olms-prod-launcher.sh
```

## File Structure
```
scripts/
├── olms-startup.sh              # Main coordinator (startup sequence)
├── prepare_machine.sh           # Machine preparation orchestrator
├── audio_engine.sh              # Audio engine launcher (renamed)
├── rt_tuning.sh                 # Phase 1: RT optimization
├── irq_pinning.sh               # Phase 2: Hardware config
├── olms-apply-affinity.sh       # Phase 3: CPU allocation
├── cpu_shielding_v2.sh          # CPU shielding implementation
├── disk_guard.sh                # System monitoring
├── setup_realtime_privileges.sh # Setup utilities
├── usb_audio_session_adapter.sh # Audio adaptation
├── olms-final-verification.sh   # System verification
├── audio_virtual.sh             # Virtual audio setup
├── olms-hard-reset.sh           # System reset
├── olms-audio-test.sh           # Audio testing
├── launchers/
│   ├── olms-test-launcher.sh    # Test environment launcher
│   └── olms-prod-launcher.sh    # Production environment launcher
└── config/
    ├── install-symlinks.sh      # Configuration utilities
    └── test_complete_system.sh  # Complete system testing
```

## Systemd Service Integration

The scripts are synchronized with the following systemd services:

| Service | Script | Description |
|---------|--------|-------------|
| `olms-rt-tuning.service` | `/usr/bin/rt_tuning.sh` | Real-time tuning |
| `olms-irq-pinning.service` | `/usr/bin/irq_pinning.sh` | IRQ pinning |
| `olms-affinity.service` | `/usr/bin/olms-apply-affinity` | CPU affinity |
| `ardour.service` | `/usr/bin/audio_engine.sh` | Audio engine |
| `olms-disk-guard.service` | `/usr/bin/disk_guard.sh` | Disk monitoring |
| `olms-irq-pinning.service` | `/usr/bin/irq_pinning.sh` | Hardware IRQ pinning |
| `olms-rt-tuning.service` | `/usr/bin/rt_tuning.sh` | Real-time kernel tuning |

## Enhanced Features (Based on Current Analysis)

### Advanced Error Handling
- **Retry mechanisms** with configurable attempts and timeouts
- **Graceful degradation** when hardware is unavailable
- **Fallback strategies** for different system configurations
- **Comprehensive logging** with timestamped status messages

### Multi-Environment Support
- **X11/XWayland/Xvfb** support for different display configurations
- **USB audio detection** with automatic hardware identification
- **Virtual audio backend** for testing without hardware
- **Multi-core CPU support** for modern systems

### Professional Audio Optimizations
- **Fixed 64-sample buffer size** for optimal audio performance
- **CPU governor performance mode** for consistent performance
- **IRQ isolation** to reduce interference
- **RT priority scheduling** for critical audio processes

### System Monitoring and Verification
- **Comprehensive verification** of all optimizations
- **Real-time monitoring** of system resources
- **Detailed reporting** with verbose output options
- **Automated testing** of audio system functionality

## Next Steps

1. **Installation**: Copy scripts to `/usr/bin/` for production use
2. **Testing**: Test the complete workflow on target hardware
3. **Documentation**: Update setup instructions and troubleshooting guides
4. **Monitoring**: Add performance metrics and logging
5. **Integration**: Ensure proper systemd service configuration
6. **Validation**: Verify all scripts work correctly in both manual and automated modes

## Notes

- All scripts include comprehensive help with `--help` option
- Scripts support both command-line arguments and environment variables
- Error handling includes fallback mechanisms for missing dependencies
- Scripts are designed for both development and production environments
- All scripts follow consistent naming conventions and error reporting
- System designed to be robust with retry mechanisms, fallbacks, and error handling
- Each script can be executed independently or as part of the complete chain
- Enables both incremental testing and complete system startup
- Enhanced with cgroup v2 support for modern Linux systems
- Includes comprehensive verification and monitoring capabilities
- Supports both traditional and standalone JACK configurations
- Provides professional-grade audio system optimization
