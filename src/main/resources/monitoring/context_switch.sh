#!/bin/bash

# Monitor context switches per second for processing threads with aligned output
INTERVAL=1

echo "Monitoring context switches per second for processing threads"
echo "Press Ctrl+C to stop monitoring"
echo ""

# Initialize associative arrays for previous values
declare -A prev_vol
declare -A prev_invol

while true; do
  echo "=================== $(date) ==================="
  printf "%-20s | %-6s | %-8s | %-9s | %-9s\n" "THREAD_NAME" "TID" "VOL/sec" "INVOL/sec" "TOTAL/sec"
  echo "-----------------------------------------------------------"

  # Find all processing threads
  for COMM in $(find /proc/*/task/*/comm -type f 2>/dev/null); do
    # Skip if file doesn't exist anymore
    [ ! -f "$COMM" ] && continue

    # Get thread name, skipping if error
    THREAD_NAME=$(cat "$COMM" 2>/dev/null) || continue

    # Only process threads with "processing" in the name
    if echo "$THREAD_NAME" | grep -q "processing"; then
      TASK_DIR=$(dirname "$COMM")
      TID=$(basename "$TASK_DIR")

      # Get current counts
      STATUS_FILE="$TASK_DIR/status"
      if [ -f "$STATUS_FILE" ]; then
        # Use anchored patterns to avoid partial matches
        VOL=$(grep "^voluntary_ctxt_switches:" "$STATUS_FILE" | awk '{print $2}' 2>/dev/null)
        INVOL=$(grep "^nonvoluntary_ctxt_switches:" "$STATUS_FILE" | awk '{print $2}' 2>/dev/null)

        # Create a unique key for the thread
        KEY="${THREAD_NAME}_${TID}"

        # Calculate rates if we have previous values
        if [ -n "$VOL" ] && [ -n "$INVOL" ] && [ -n "${prev_vol[$KEY]}" ] && [ -n "${prev_invol[$KEY]}" ]; then
          VOL_RATE=$(( (VOL - ${prev_vol[$KEY]}) / INTERVAL ))
          INVOL_RATE=$(( (INVOL - ${prev_invol[$KEY]}) / INTERVAL ))
          TOTAL_RATE=$(( VOL_RATE + INVOL_RATE ))

          # Print aligned data using printf
          printf "%-20s | %-6s | %-8s | %-9s | %-9s\n" \
            "$THREAD_NAME" "$TID" "$VOL_RATE" "$INVOL_RATE" "$TOTAL_RATE"
        else
          # First run, no rates available
          printf "%-20s | %-6s | %-8s | %-9s | %-9s\n" \
            "$THREAD_NAME" "$TID" "N/A" "N/A" "N/A"
        fi

        # Store current values for next iteration
        prev_vol[$KEY]=$VOL
        prev_invol[$KEY]=$INVOL
      fi
    fi
  done

  sleep $INTERVAL
  echo ""
done