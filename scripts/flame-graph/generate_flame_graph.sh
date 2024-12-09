#!/bin/bash

# Check if PID is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <PID> [duration_in_seconds]"
    exit 1
fi

PID=$1
DURATION=${2:-30}  # Default 30 seconds if not specified
OUTPUT_DIR="./flamegraphs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Function to check if async-profiler exists
check_async_profiler() {
    if [ ! -d "./async-profiler" ]; then
        echo "async-profiler not found. Installing..."
        git clone https://github.com/jvm-profiling-tools/async-profiler.git
        cd async-profiler
        make
        cd ..
    fi
}

# Function to generate flame graph using async-profiler
generate_async_profiler() {
    echo "Generating flame graph using async-profiler for $DURATION seconds..."

    ./async-profiler/build/bin/asprof -d "$DURATION" -f "$OUTPUT_DIR/flamegraph_${TIMESTAMP}.html" "$PID"

    echo "Flame graph generated at: $OUTPUT_DIR/flamegraph_${TIMESTAMP}.html"
}

# Function to generate flame graph using perf (requires root)
generate_perf() {
    echo "Generating flame graph using perf for $DURATION seconds..."

    # Record perf data
    perf record -F 99 -p "$PID" -g -- sleep "$DURATION"

    # Generate folded stacks
    perf script | ./FlameGraph/stackcollapse-perf.pl > "$OUTPUT_DIR/out.folded"

    # Generate SVG
    ./FlameGraph/flamegraph.pl "$OUTPUT_DIR/out.folded" > "$OUTPUT_DIR/flamegraph_${TIMESTAMP}.svg"

    # Cleanup
    rm -f perf.data

    echo "Flame graph generated at: $OUTPUT_DIR/flamegraph_${TIMESTAMP}.svg"
}

# Check for dependencies
if command -v java >/dev/null 2>&1; then
    check_async_profiler
    generate_async_profiler
elif command -v perf >/dev/null 2>&1; then
    # Check if FlameGraph tools exist
    if [ ! -d "./FlameGraph" ]; then
        echo "FlameGraph tools not found. Installing..."
        git clone https://github.com/brendangregg/FlameGraph.git
    fi
    generate_perf
else
    echo "Error: Neither Java nor perf found. Please install either Java or perf."
    exit 1
fi