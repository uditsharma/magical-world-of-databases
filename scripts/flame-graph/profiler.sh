#!/bin/bash

# Colors using tput (more compatible)
if [ -t 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    NC=$(tput sgr0)  # No Color
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    NC=""
fi

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo "${color}$*${NC}"
}

# Function to print error messages
error() {
    print_color "$RED" "ERROR: $*" >&2
}

# Function to print warning messages
warn() {
    print_color "$YELLOW" "WARNING: $*"
}

# Function to print info messages
info() {
    print_color "$GREEN" "$*"
}

# Function to print debug messages
debug() {
    [ "$DEBUG_MODE" = true ] && print_color "$BLUE" "DEBUG: $*"
}

# Default values
PID=""
DURATION=30
EVENT="cpu"
INTERVAL=1000000
FORMAT="html"
OUTPUT_DIR="./java_profiling"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PROFILER_MODE="async"  # async or perf
COLLECT_SYSTEM_METRICS=false
CONTINUOUS_MODE=false
DEBUG_MODE=false
LINE_NUMBERS=true

usage() {
    cat << EOF
$(print_color "$BLUE" "Java Performance Profiling Script")

Usage: $0 [OPTIONS]

$(print_color "$GREEN" "Required:")
    -p PID          Process ID to profile

$(print_color "$YELLOW" "Profiling Options:")
    -d DURATION     Duration in seconds (default: 30)
    -e EVENT        Event to profile:
                    - cpu (default): CPU sampling
                    - alloc: Heap allocations
                    - lock: Lock contention
                    - wall: Wall clock profiling
                    - cache-misses: CPU cache misses
                    - all: All events (higher overhead)
    -i INTERVAL     Sampling interval in nanoseconds (default: 1000000)
    -f FORMAT       Output format: html, svg, jfr (default: html)

$(print_color "$YELLOW" "Filtering Options:")
    -t             Include thread names
    -l FILTER      Include stack trace filter (e.g., 'java/*,javax/*')
    -x FILTER      Exclude stack trace filter (e.g., '*jni*')
    -b             Include line numbers in traces

$(print_color "$YELLOW" "Mode Options:")
    -m MODE        Profiler mode: async (default), perf
    -s             Collect system metrics (CPU, memory, IO)
    -c             Continuous mode (run until Ctrl+C)
    -v             Debug mode (verbose output)

$(print_color "$YELLOW" "Output Options:")
    -o DIR         Output directory (default: ./java_profiling)

$(print_color "$GREEN" "Examples:")
    # Basic CPU profiling
    $0 -p 1234

    # Comprehensive profiling with system metrics
    $0 -p 1234 -e all -s -d 60

    # Memory allocation profiling with thread names
    $0 -p 1234 -e alloc -t

    # Continuous CPU profiling with system metrics
    $0 -p 1234 -c -s

    # Lock contention analysis with specific package filtering
    $0 -p 1234 -e lock -l 'com/example/*' -t
EOF
}

check_dependencies() {
    local missing_deps=()

    for cmd in java jps top awk sed grep; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done

    if [ "$PROFILER_MODE" = "async" ]; then
        if [ ! -d "./async-profiler" ]; then
            warn "async-profiler not found, will attempt to install"
        fi
    elif [ "$PROFILER_MODE" = "perf" ]; then
        if ! command -v perf >/dev/null 2>&1; then
            missing_deps+=(perf)
        fi
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

install_async_profiler() {
    if [ ! -d "./async-profiler" ]; then
        warn "Installing async-profiler..."
        git clone https://github.com/jvm-profiling-tools/async-profiler.git
        cd async-profiler
        make
        if [ $? -ne 0 ]; then
            error "Failed to build async-profiler"
            exit 1
        fi
        cd ..
        info "async-profiler installed successfully"
    fi
}

install_flamegraph_tools() {
    if [ ! -d "./FlameGraph" ]; then
        warn "Installing FlameGraph tools..."
        git clone https://github.com/brendangregg/FlameGraph.git
        if [ $? -ne 0 ]; then
            error "Failed to clone FlameGraph repository"
            exit 1
        fi
        info "FlameGraph tools installed successfully"
    fi
}

collect_system_metrics() {
    local pid=$1
    local output_file="$OUTPUT_DIR/system_metrics_${TIMESTAMP}.txt"

    info "Collecting system metrics..."

    while true; do
        date "+%Y-%m-%d %H:%M:%S" >> "$output_file"
        top -b -n 1 -p $pid | tail -n 1 >> "$output_file"
        mpstat 1 1 | tail -n 1 >> "$output_file"
        free -m >> "$output_file"

        if [ -f "/proc/$pid/io" ]; then
            cat "/proc/$pid/io" >> "$output_file"
        fi

        echo "---" >> "$output_file"
        sleep 1

        if [ "$CONTINUOUS_MODE" = false ]; then
            if [ $SECONDS -ge $DURATION ]; then
                break
            fi
        fi
    done &
    echo $! > "$OUTPUT_DIR/metrics_pid"
}

generate_async_profile() {
    local cmd="./async-profiler/build/bin/asprof"
    cmd+=" -d $DURATION"
    cmd+=" -e $EVENT"
    cmd+=" -i $INTERVAL"

    [ ! -z "$INCLUDE_FILTER" ] && cmd+=" -I $INCLUDE_FILTER"
    [ ! -z "$EXCLUDE_FILTER" ] && cmd+=" -X $EXCLUDE_FILTER"
    [ "$THREAD_NAMES" = true ] && cmd+=",threads"
    [ "$LINE_NUMBERS" = true ] && cmd+=",lines"

    case $FORMAT in
        "html") cmd+=" -f $OUTPUT_DIR/flamegraph_${TIMESTAMP}.html" ;;
        "svg")  cmd+=" -f $OUTPUT_DIR/flamegraph_${TIMESTAMP}.svg" ;;
        "jfr")  cmd+=" -o jfr -f $OUTPUT_DIR/profile_${TIMESTAMP}.jfr" ;;
    esac

    cmd+=" $PID"

    info "Executing: $cmd"
    eval "$cmd"
}

generate_perf_profile() {
    local perf_data="$OUTPUT_DIR/perf_${TIMESTAMP}.data"
    info "Generating perf profile..."
    perf record -F 99 -p "$PID" -g -- sleep "$DURATION" -o "$perf_data"

    info "Generating flame graph..."
    perf script -i "$perf_data" | \
        ./FlameGraph/stackcollapse-perf.pl | \
        ./FlameGraph/flamegraph.pl > "$OUTPUT_DIR/flamegraph_${TIMESTAMP}.svg"
}

cleanup() {
    warn "Cleaning up..."

    if [ -f "$OUTPUT_DIR/metrics_pid" ]; then
        kill $(cat "$OUTPUT_DIR/metrics_pid") 2>/dev/null
        rm "$OUTPUT_DIR/metrics_pid"
    fi

    rm -f perf.data*

    info "Profiling completed. Results are in: $OUTPUT_DIR"
}

# Parse command line arguments
while getopts "p:d:e:i:f:l:x:m:o:tbscv" opt; do
    case $opt in
        p) PID="$OPTARG" ;;
        d) DURATION="$OPTARG" ;;
        e) EVENT="$OPTARG" ;;
        i) INTERVAL="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        l) INCLUDE_FILTER="$OPTARG" ;;
        x) EXCLUDE_FILTER="$OPTARG" ;;
        m) PROFILER_MODE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) THREAD_NAMES=true ;;
        b) LINE_NUMBERS=true ;;
        s) COLLECT_SYSTEM_METRICS=true ;;
        c) CONTINUOUS_MODE=true ;;
        v) DEBUG_MODE=true ;;
        ?) usage; exit 1 ;;
    esac
done

if [ -z "$PID" ]; then
    error "PID is required"
    usage
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
trap cleanup EXIT

check_dependencies

if [ "$PROFILER_MODE" = "async" ]; then
    install_async_profiler
elif [ "$PROFILER_MODE" = "perf" ]; then
    install_flamegraph_tools
fi

if [ "$COLLECT_SYSTEM_METRICS" = true ]; then
    collect_system_metrics "$PID"
fi

info "Starting profiling of PID $PID..."
SECONDS=0

if [ "$PROFILER_MODE" = "async" ]; then
    generate_async_profile
else
    generate_perf_profile
fi

if [ "$CONTINUOUS_MODE" = true ]; then
    warn "Running in continuous mode. Press Ctrl+C to stop..."
    while true; do
        sleep 1
    done
fi

exit 0