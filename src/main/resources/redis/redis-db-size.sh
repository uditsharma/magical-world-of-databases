#!/bin/bash

# Configuration
REDIS_HOST="localhost"
REDIS_PORT="6379"
CONTAINER_NAME="redis-instance"
CONNECTION_METHOD="direct"
DEFAULT_TOP_COUNT=10

# Function to execute Redis command
exec_redis_cmd() {
    if [ "$CONNECTION_METHOD" = "docker" ]; then
        docker exec $CONTAINER_NAME redis-cli "$@"
    else
        redis-cli -h $REDIS_HOST -p $REDIS_PORT "$@"
    fi
}

# Function to convert bytes to human readable format
format_size() {
    local total_size=$1
    if [ $total_size -gt 1073741824 ]; then
        echo "$(echo "scale=2; $total_size/1024/1024/1024" | bc)GB"
    elif [ $total_size -gt 1048576 ]; then
        echo "$(echo "scale=2; $total_size/1024/1024" | bc)MB"
    elif [ $total_size -gt 1024 ]; then
        echo "$(echo "scale=2; $total_size/1024" | bc)KB"
    else
        echo "${total_size}B"
    fi
}

# Function to check if input is a valid number
is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

# Function to handle the calculation safely
calculate_average() {
    local total=$1
    local count=$2

    if [ "$count" -eq 0 ]; then
        echo "0"
    else
        # Use awk for better floating point handling
        echo $(awk "BEGIN {printf \"%.2f\", $total / $count}")
    fi
}

analyze_hash() {
    local hash_key=$1
    local db=$2

    # Check if the key exists and is a hash
    local type=$(exec_redis_cmd TYPE "$hash_key")
    if [ "$type" != "hash" ]; then
        echo "Error: '$hash_key' is not a hash or doesn't exist"
        return 1
    fi

    echo "Analyzing Hash: $hash_key"
    echo "------------------------"

    # Get number of fields
    local field_count=$(exec_redis_cmd HLEN "$hash_key")
    echo "Total Fields: $field_count"

    if [ "$field_count" -eq 0 ]; then
        echo "Hash is empty"
        return 0
    fi

    # Initialize variables for statistics
    local total_size=0
    local min_size=999999999999
    local max_size=0
    local min_field=""
    local max_field=""
    local temp_file=$(mktemp)

    # Analyze each field
    while IFS= read -r field; do
        if [ ! -z "$field" ]; then
            local size=$(exec_redis_cmd MEMORY USAGE "$hash_key" "$field")
            if [[ "$size" =~ ^[0-9]+$ ]]; then
                echo "$size|$field" >> "$temp_file"

                # Update statistics
                total_size=$((total_size + size))

                if [ $size -lt $min_size ]; then
                    min_size=$size
                    min_field=$field
                fi

                if [ $size -gt $max_size ]; then
                    max_size=$size
                    max_field=$field
                fi
            fi
        fi
    done < <(exec_redis_cmd HKEYS "$hash_key")

    # Calculate average using the new function
    local avg_size=$(calculate_average $total_size $field_count)

    # Print statistics
    echo
    echo "Hash Statistics:"
    echo "------------------------"
    echo "Total Size: $(format_size $total_size)"
    if [ "$field_count" -gt 0 ]; then
        echo "Average Entry Size: $(format_size $avg_size)"
        echo "Minimum Entry Size: $(format_size $min_size) (Field: $min_field)"
        echo "Maximum Entry Size: $(format_size $max_size) (Field: $max_field)"

        echo
        echo "Size Distribution:"
        echo "------------------------"
        # Show distribution in size ranges
        local range1=0  # 0-1KB
        local range2=0  # 1KB-10KB
        local range3=0  # 10KB-100KB
        local range4=0  # >100KB

        while IFS='|' read -r size field; do
            if [ $size -lt 1024 ]; then
                range1=$((range1 + 1))
            elif [ $size -lt 10240 ]; then
                range2=$((range2 + 1))
            elif [ $size -lt 102400 ]; then
                range3=$((range3 + 1))
            else
                range4=$((range4 + 1))
            fi
        done < "$temp_file"

        echo "0-1KB: $range1 entries"
        echo "1KB-10KB: $range2 entries"
        echo "10KB-100KB: $range3 entries"
        echo ">100KB: $range4 entries"
    fi

    # Cleanup
    rm -f "$temp_file"
}

get_top_keys() {
    local db=$1
    local count=$2
    echo "Top $count Largest Keys in Database $db:"
    echo "------------------------"

    # Select the database
    if ! exec_redis_cmd SELECT $db > /dev/null 2>&1; then
        echo "Error: Database $db does not exist or connection failed"
        return 1
    fi

    # Create temporary file for storing key sizes
    local temp_file=$(mktemp)

    # Get all keys and their sizes
    while IFS= read -r key; do
        if [ ! -z "$key" ]; then
            local size=$(exec_redis_cmd MEMORY USAGE "$key")
            if [[ "$size" =~ ^[0-9]+$ ]]; then
                local type=$(exec_redis_cmd TYPE "$key")
                echo "$size|$type|$key" >> "$temp_file"
            fi
        fi
    done < <(exec_redis_cmd --raw KEYS '*')

    # Sort by size and get top N
    echo "Size | Type | Key"
    echo "------------------------"
    sort -t'|' -k1 -nr "$temp_file" | head -n "$count" | while IFS='|' read -r size type key; do
        echo "$(format_size $size) | $type | $key"
    done

    # Cleanup
    rm -f "$temp_file"
    echo "------------------------"
}

get_db_size() {
    local db=$1
    echo "Analyzing Database $db:"

    # Select the database
    if ! exec_redis_cmd SELECT $db > /dev/null 2>&1; then
        echo "Error: Database $db does not exist or connection failed"
        return 1
    fi

    # Get total number of keys
    local keys=$(exec_redis_cmd DBSIZE)
    echo "Total Keys: $keys"

    # Get memory usage if keys exist
    if [ "$keys" -gt 0 ]; then
        local total_size=0

        # Get all keys and process them
        while IFS= read -r key; do
            if [ ! -z "$key" ]; then
                # Get memory usage for each key
                local size=$(exec_redis_cmd MEMORY USAGE "$key")
                if [[ "$size" =~ ^[0-9]+$ ]]; then
                    total_size=$((total_size + size))
                fi
            fi
        done < <(exec_redis_cmd --raw KEYS '*')

        echo "Approximate Size: $(format_size $total_size)"

        # Get key types distribution
        echo "Key Type Distribution:"
        while IFS= read -r key; do
            if [ ! -z "$key" ]; then
                exec_redis_cmd TYPE "$key"
            fi
        done < <(exec_redis_cmd --raw KEYS '*') | sort | uniq -c
    fi
    echo "------------------------"
}

show_usage() {
    echo "Usage: $0 [-d|--docker] [-t|--top [count]] [-a|--analyze hash_key] [db_number]"
    echo "Options:"
    echo "  -d, --docker         Use Docker container connection"
    echo "  -t, --top [N]        Show top N largest keys (default: $DEFAULT_TOP_COUNT)"
    echo "  -a, --analyze KEY    Analyze specific hash key"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $0                   # Show general DB stats (0-2)"
    echo "  $0 -d                # Show general DB stats using Docker"
    echo "  $0 -t 20             # Show top 20 keys"
    echo "  $0 -a myhash         # Analyze hash 'myhash'"
    echo "  $0 -d -a myhash 1    # Analyze hash 'myhash' in DB 1 using Docker"
}

# Initialize variables
SHOW_TOP=false
TOP_COUNT=$DEFAULT_TOP_COUNT
ANALYZE_HASH=""
DB_NUMBER=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--docker)
            CONNECTION_METHOD="docker"
            shift
            ;;
        -t|--top)
            SHOW_TOP=true
            shift
            if [[ $# -gt 0 ]] && is_number "$1"; then
                TOP_COUNT="$1"
                shift
            fi
            ;;
        -a|--analyze)
            shift
            if [[ $# -gt 0 ]]; then
                ANALYZE_HASH="$1"
                shift
            else
                echo "Error: Hash key required for analysis"
                show_usage
                exit 1
            fi
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if is_number "$1"; then
                DB_NUMBER="$1"
            else
                echo "Error: Invalid argument '$1'"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check connection requirements
if [ "$CONNECTION_METHOD" = "docker" ]; then
    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo "Error: Redis container '$CONTAINER_NAME' is not running"
        exit 1
    fi
else
    if ! command -v redis-cli &> /dev/null; then
        echo "Error: redis-cli is not installed"
        exit 1
    fi
fi

# Execute requested operation
if [ ! -z "$ANALYZE_HASH" ]; then
    # Analyze specific hash
    analyze_hash "$ANALYZE_HASH" "$DB_NUMBER"
elif [ "$SHOW_TOP" = true ]; then
    # Show top keys
    if [ ! -z "$DB_NUMBER" ]; then
        get_db_size "$DB_NUMBER"
        get_top_keys "$DB_NUMBER" "$TOP_COUNT"
    else
        for db in {0..2}; do
            get_db_size $db
            get_top_keys $db "$TOP_COUNT"
        done
    fi
else
    # Show general DB stats
    if [ ! -z "$DB_NUMBER" ]; then
        get_db_size "$DB_NUMBER"
    else
        for db in {0..2}; do
            get_db_size $db
        done
    fi
fi