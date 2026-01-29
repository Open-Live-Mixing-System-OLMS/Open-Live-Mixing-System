#!/bin/bash

# Test della logica CPU optimization
MODE="test"
JACK_PERIOD_SIZE="64"

print_status() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# CPU optimization logic
if [ "$MODE" = "test" ]; then
    JACK_PERIOD_SIZE="128"
    print_status "Testing mode detected: Using larger buffer size (128 samples) for CPU safety"
    print_status "Note: This increases latency but reduces CPU usage for GUI/SSH stability"
else
    JACK_PERIOD_SIZE="64"
    print_status "Production mode detected: Using smaller buffer size (64 samples) for minimal latency"
fi

echo "JACK_PERIOD_SIZE impostato a: $JACK_PERIOD_SIZE"
