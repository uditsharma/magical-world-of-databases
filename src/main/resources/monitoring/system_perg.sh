#!/bin/sh

# Simple System Performance Monitor for BusyBox environments
# Monitors page faults, CPU usage, disk I/O and context switches

# Default interval in seconds
INTERVAL=${1:-5}
# Run time in minutes (10 minutes by default)
RUNTIME=${2:-10}
# Convert runtime to seconds
RUNTIME_SECONDS=$((RUNTIME * 60))

# Output file - either user-provided or auto-generated
if [ "$3" != "" ]; then
    OUTPUT_FILE="$3"
else
    OUTPUT_FILE="system_stats_$(date +%Y%m%d_%H%M%S).log"
fi

# Function to get values from /proc/vmstat
get_vmstat_value() {
    grep "^$1 " /proc/vmstat | awk '{print $2}'
}

# Function to get CPU usage from /proc/stat
get_cpu_usage() {
    # Get CPU line from /proc/stat
    cpu_line=$(grep '^cpu ' /proc/stat)

    # Extract values
    user=$(echo $cpu_line | awk '{print $2}')
    nice=$(echo $cpu_line | awk '{print $3}')
    system=$(echo $cpu_line | awk '{print $4}')
    idle=$(echo $cpu_line | awk '{print $5}')
    iowait=$(echo $cpu_line | awk '{print $6}')

    # Calculate total
    total=$((user + nice + system + idle + iowait))

    # Return values as space-separated string
    echo "$user $system $iowait $total"
}

# Function to get disk stats from /proc/diskstats
get_disk_stats() {
    # Get main disk (usually sda or mmcblk0)
    disk_line=$(grep -E ' sda | mmcblk0 ' /proc/diskstats | head -1)
    if [ -z "$disk_line" ]; then
        echo "0 0"
        return
    fi

    # Fields 6 and 10 are read and write sectors
    # Each sector is typically 512 bytes = 0.5 KB
    read_sectors=$(echo $disk_line | awk '{print $6}')
    write_sectors=$(echo $disk_line | awk '{print $10}')

    # Convert sectors to KB
    read_kb=$((read_sectors / 2))
    write_kb=$((write_sectors / 2))

    echo "$read_kb $write_kb"
}

# Function to get context switch count
get_context_switches() {
    # Get context switches from /proc/stat
    cs_count=$(grep '^ctxt ' /proc/stat | awk '{print $2}')
    echo "$cs_count"
}

# Print script info
echo "Simple System Performance Monitor (BusyBox compatible)" | tee $OUTPUT_FILE
echo "Monitoring interval: ${INTERVAL} seconds" | tee -a $OUTPUT_FILE
echo "Runtime: ${RUNTIME} minutes" | tee -a $OUTPUT_FILE
echo "Start time: $(date)" | tee -a $OUTPUT_FILE
echo "" | tee -a $OUTPUT_FILE

# Print header and save to file
printf "%-19s | %-8s %-8s %-8s %-8s | %-6s %-6s %-6s | %-10s %-10s | %-12s\n" \
    "TIMESTAMP" "MIN_PF" "MAJ_PF" "HIT%" "MISS%" "CPU_U%" "CPU_S%" "IO_W%" "READ_KB" "WRITE_KB" "CTX_SW/s" | tee -a $OUTPUT_FILE
echo "--------------------------------------------------------------------------------------" | tee -a $OUTPUT_FILE

# Initialize previous values
prev_minor=$(get_vmstat_value pgfault)
prev_major=$(get_vmstat_value pgmajfault)
prev_cpu_stats=$(get_cpu_usage)
prev_cpu_user=$(echo $prev_cpu_stats | awk '{print $1}')
prev_cpu_system=$(echo $prev_cpu_stats | awk '{print $2}')
prev_cpu_iowait=$(echo $prev_cpu_stats | awk '{print $3}')
prev_cpu_total=$(echo $prev_cpu_stats | awk '{print $4}')
prev_disk_stats=$(get_disk_stats)
prev_read_kb=$(echo $prev_disk_stats | awk '{print $1}')
prev_write_kb=$(echo $prev_disk_stats | awk '{print $2}')
prev_ctx_switches=$(get_context_switches)

# Initialize counters for summary
total_minor=0
total_major=0
total_ctx_switches=0
start_time=$(date +%s)
end_time=$((start_time + RUNTIME_SECONDS))
samples=0

# Run until the end time is reached
while [ $(date +%s) -lt $end_time ]; do
    # Sleep first to allow initial values to be gathered
    sleep $INTERVAL

    # Get current timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Get current page fault values
    curr_minor=$(get_vmstat_value pgfault)
    curr_major=$(get_vmstat_value pgmajfault)

    # Get current CPU stats
    curr_cpu_stats=$(get_cpu_usage)
    curr_cpu_user=$(echo $curr_cpu_stats | awk '{print $1}')
    curr_cpu_system=$(echo $curr_cpu_stats | awk '{print $2}')
    curr_cpu_iowait=$(echo $curr_cpu_stats | awk '{print $3}')
    curr_cpu_total=$(echo $curr_cpu_stats | awk '{print $4}')

    # Get current disk stats
    curr_disk_stats=$(get_disk_stats)
    curr_read_kb=$(echo $curr_disk_stats | awk '{print $1}')
    curr_write_kb=$(echo $curr_disk_stats | awk '{print $2}')

    # Get current context switches
    curr_ctx_switches=$(get_context_switches)

    # Calculate page fault differences
    minor_diff=$((curr_minor - prev_minor))
    major_diff=$((curr_major - prev_major))
    total_diff=$((minor_diff + major_diff))

    # Calculate CPU usage percentages
    cpu_diff_total=$((curr_cpu_total - prev_cpu_total))
    if [ $cpu_diff_total -gt 0 ]; then
        cpu_user_pct=$(( (curr_cpu_user - prev_cpu_user) * 100 / cpu_diff_total ))
        cpu_system_pct=$(( (curr_cpu_system - prev_cpu_system) * 100 / cpu_diff_total ))
        cpu_iowait_pct=$(( (curr_cpu_iowait - prev_cpu_iowait) * 100 / cpu_diff_total ))
    else
        cpu_user_pct=0
        cpu_system_pct=0
        cpu_iowait_pct=0
    fi

    # Calculate disk I/O differences (per second)
    read_kb_diff=$(( (curr_read_kb - prev_read_kb) / INTERVAL ))
    write_kb_diff=$(( (curr_write_kb - prev_write_kb) / INTERVAL ))

    # Calculate context switches per second
    ctx_switches_diff=$(( (curr_ctx_switches - prev_ctx_switches) / INTERVAL ))

    # Update total counters
    total_minor=$((total_minor + minor_diff))
    total_major=$((total_major + major_diff))
    total_ctx_switches=$((total_ctx_switches + ctx_switches_diff))
    samples=$((samples + 1))

    # Calculate cache hit/miss ratios
    if [ $total_diff -gt 0 ]; then
        hit_ratio=$(( minor_diff * 100 / total_diff ))
        miss_ratio=$(( major_diff * 100 / total_diff ))
    else
        hit_ratio=0
        miss_ratio=0
    fi

    # Print the values and save to file
    printf "%-19s | %-8d %-8d %-8d %-8d | %-6d %-6d %-6d | %-10d %-10d | %-12d\n" \
           "$timestamp" "$minor_diff" "$major_diff" "$hit_ratio" "$miss_ratio" \
           "$cpu_user_pct" "$cpu_system_pct" "$cpu_iowait_pct" \
           "$read_kb_diff" "$write_kb_diff" "$ctx_switches_diff" | tee -a $OUTPUT_FILE

    # Store current values as previous for next iteration
    prev_minor=$curr_minor
    prev_major=$curr_major
    prev_cpu_user=$curr_cpu_user
    prev_cpu_system=$curr_cpu_system
    prev_cpu_iowait=$curr_cpu_iowait
    prev_cpu_total=$curr_cpu_total
    prev_read_kb=$curr_read_kb
    prev_write_kb=$curr_write_kb
    prev_ctx_switches=$curr_ctx_switches
done

# Calculate overall statistics
total_faults=$((total_minor + total_major))
if [ $total_faults -gt 0 ]; then
    overall_hit_ratio=$(( total_minor * 100 / total_faults ))
    overall_miss_ratio=$(( total_major * 100 / total_faults ))
else
    overall_hit_ratio=0
    overall_miss_ratio=0
fi

# Print summary
echo "" | tee -a $OUTPUT_FILE
echo "==================== SUMMARY ====================" | tee -a $OUTPUT_FILE
echo "Monitoring period: $RUNTIME minutes ($samples samples)" | tee -a $OUTPUT_FILE
echo "" | tee -a $OUTPUT_FILE
echo "PAGE FAULT STATISTICS:" | tee -a $OUTPUT_FILE
echo "  Total minor page faults: $total_minor" | tee -a $OUTPUT_FILE
echo "  Total major page faults: $total_major" | tee -a $OUTPUT_FILE
echo "  Total page faults: $total_faults" | tee -a $OUTPUT_FILE
echo "  Overall cache hit ratio: ${overall_hit_ratio}%" | tee -a $OUTPUT_FILE
echo "  Overall cache miss ratio: ${overall_miss_ratio}%" | tee -a $OUTPUT_FILE
echo "" | tee -a $OUTPUT_FILE
echo "CONTEXT SWITCH STATISTICS:" | tee -a $OUTPUT_FILE
if [ $samples -gt 0 ]; then
    avg_ctx_switches=$((total_ctx_switches / samples))
    echo "  Total context switches: $total_ctx_switches" | tee -a $OUTPUT_FILE
    echo "  Average context switches/sec: $avg_ctx_switches" | tee -a $OUTPUT_FILE
else
    echo "  No samples collected" | tee -a $OUTPUT_FILE
fi
echo "" | tee -a $OUTPUT_FILE
echo "Statistics saved to: $OUTPUT_FILE" | tee -a $OUTPUT_FILE
echo "=================================================" | tee -a $OUTPUT_FILE