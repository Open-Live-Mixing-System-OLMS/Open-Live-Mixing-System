# OLMS Scripts Implementation Summary

## Overview

This document summarizes the implementation of the OLMS machine preparation scripts based on the OLMS specifications. The scripts follow a hierarchical architecture where `olms-startup.sh` acts as the main coordinator, calling specialized scripts for different aspects of system preparation.

## Implemented Scripts

### 1. Main Coordinator
- **`scripts/olms-startup.sh`** - Primary startup script that coordinates the complete system initialization
  - Phase 1: Real-time System Optimization (calls `rt_tuning.sh`)
  - Phase 2: Hardware Configuration (calls `irq_pinning.sh`)
  - Phase 3: Machine Preparation (calls `prepare_machine.sh`)
  - Phase 4: Audio Engine Startup (calls `audio_engine.sh`)

### 2. Specialized Orchestrators
- **`scripts/prepare_machine.sh`** - Machine preparation orchestrator for system configuration
  - Phase 1: Real-time System Optimization (calls `rt_tuning.sh`)
  - Phase 2: Hardware Configuration (calls `irq_pinning.sh`)
  - Phase 3: CPU Resource Allocation (calls `olms-apply-affinity.sh`)
  - Phase 4: Audio Engine Coordination (returns control to `olms-startup.sh`)

### 2. Individual Phase Scripts

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
  - Allocates dedicated CPU cores for audio processing
  - Verifies CPU affinity settings

#### Phase 4: Audio Engine Coordination
- **`scripts/audio_engine.sh`** (renamed from ardour_launcher.sh) - Audio engine launch
  - Starts JACK and Ardour Headless
  - Supports testing mode (with GUI) and production mode (headless)
  - Handles virtual audio backend when no hardware is available
  - Provides comprehensive error handling and status reporting

### 3. Additional System Scripts

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
./scripts/prepare_machine.sh --test
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
```

## File Structure
```
scripts/
├── olms-startup.sh              # Main coordinator (startup sequence)
├── prepare_machine.sh           # Machine preparation orchestrator
├── audio_engine.sh              # Audio engine launcher (renamed)
├── rt_tuning.sh                 # Phase 1: RT optimization
├── irq_pinning.sh               # Phase 2: Hardware config (NEW)
├── olms-apply-affinity.sh       # Phase 3: CPU allocation (NEW)
├── disk_guard.sh                # System monitoring (NEW)
├── setup_realtime_privileges.sh # Setup utilities
└── usb_audio_session_adapter.sh # Audio adaptation
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

## Next Steps

1. **Installation**: Copy scripts to `/usr/bin/` for production use
2. **Testing**: Test the complete workflow on target hardware
3. **Documentation**: Update setup instructions and troubleshooting guides
4. **Monitoring**: Add performance metrics and logging

## Notes

- All scripts include comprehensive help with `--help` option
- Scripts support both command-line arguments and environment variables
- Error handling includes fallback mechanisms for missing dependencies
- Scripts are designed for both development and production environments
- All scripts follow consistent naming conventions and error reporting