#!/bin/bash

# Test JACK detection
echo "=== Testing JACK Detection ==="

# Method 1: Check for any process with JACK in command line (most reliable)
echo "Method 1: pgrep -f 'jackd|jackdbus'"
jack_processes=$(pgrep -f "jackd\|jackdbus" 2>/dev/null || true)
echo "Found processes: $jack_processes"

if [[ -n "$jack_processes" ]]; then
    # Filter for actual JACK server processes (not just clients)
    for pid in $jack_processes; do
        echo "Checking PID $pid"
        if [[ -f "/proc/$pid/cmdline" ]]; then
            local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
            echo "Command line: $cmdline"
            # Check if this is actually a JACK server process
            if [[ "$cmdline" =~ jackd.*-d.*alsa ]] || [[ "$cmdline" =~ jackdbus ]] || [[ "$cmdline" =~ jackd.*-d.*dummy ]]; then
                echo "✓ Found JACK server process: $pid"
                exit 0
            else
                echo "✗ Not a JACK server process"
            fi
        else
            echo "✗ Cannot read cmdline for PID $pid"
        fi
    done
fi

echo "No JACK server process found"
