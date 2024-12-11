#!/bin/bash

CONTAINER_NAME="redis-instance"
EXPORTER_CONTAINER_NAME="redis-exporter"
DEFAULT_PORT=6379
DEFAULT_METRICS_PORT=9121

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Please install jq first:"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  CentOS/RHEL: sudo yum install jq"
    echo "  macOS: brew install jq"
    exit 1
fi

# Function to check if a port is in use
is_port_in_use() {
    if command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":$1 "
        return $?
    elif command -v ss &> /dev/null; then
        ss -tuln | grep -q ":$1 "
        return $?
    else
        return 1
    fi
}

# Function to find next available port
find_available_port() {
    local port=$(($1))
    until ! is_port_in_use "$port"; do
        port=$((port + 1))
    done
    echo "$port"
}

# Function to list available Redis versions
list_versions() {
    echo "Available Redis versions:"
    curl -s https://hub.docker.com/v2/repositories/library/redis/tags?page_size=100 \
        | jq -r '.results[].name' \
        | grep -E '^[0-9]+\.[0-9]+$' \
        | sort -V \
        | head -8
}

# Function to validate Redis version
validate_version() {
    local version=$1
    if ! curl -s https://hub.docker.com/v2/repositories/library/redis/tags?page_size=100 \
        | jq -r '.results[].name' \
        | grep -E '^[0-9]+\.[0-9]+$' \
        | grep -q "^$version$"; then
        echo "Error: Invalid Redis version"
        exit 1
    fi
}

# Function to launch Redis container with metrics
launch_redis() {
    local version=$1
    validate_version "$version"

    # Check if containers already exist
    if docker ps -a | grep -q "$CONTAINER_NAME\|$EXPORTER_CONTAINER_NAME"; then
        echo "Error: Redis container or exporter already exists. Stop and remove them first."
        exit 1
    fi

    # Create Docker network if it doesn't exist
    if ! docker network inspect redis-net >/dev/null 2>&1; then
        docker network create redis-net
    fi

    # Find available ports
    local redis_port
    local metrics_port
    redis_port=$(find_available_port $DEFAULT_PORT)
    metrics_port=$(find_available_port $DEFAULT_METRICS_PORT)

    echo "Launching Redis version $version..."

    # Launch Redis container
    if docker run -d \
        --name "$CONTAINER_NAME" \
        --network redis-net \
        -p "${redis_port}:6379" \
        "redis:$version"; then

        echo "Redis container launched successfully!"
        echo "Redis Port: $redis_port"

        # Launch Redis Exporter container
        echo "Launching Redis Exporter..."
        if docker run -d \
            --name "$EXPORTER_CONTAINER_NAME" \
            --network redis-net \
            -p "${metrics_port}:9121" \
            -e "REDIS_ADDR=redis://${CONTAINER_NAME}:6379" \
            oliver006/redis_exporter:latest; then

            echo "Redis Exporter launched successfully!"
            echo "Metrics available at: http://localhost:${metrics_port}/metrics"

            # Save port mappings
            echo "$redis_port" > "/tmp/${CONTAINER_NAME}_port"
            echo "$metrics_port" > "/tmp/${CONTAINER_NAME}_metrics_port"

            echo -e "\nContainer Details:"
            echo "Redis Container ID: $(docker ps -q -f name=$CONTAINER_NAME)"
            echo "Redis Port: $redis_port"
            echo "Metrics Port: $metrics_port"
            echo -e "\nMetrics URL: http://localhost:${metrics_port}/metrics"
            echo "Prometheus Configuration:"
            echo -e "  - job_name: redis\n    static_configs:\n      - targets: ['localhost:${metrics_port}']"
        else
            echo "Error: Failed to launch Redis Exporter"
            cleanup_redis
            exit 1
        fi
    else
        echo "Error: Failed to launch Redis container"
        exit 1
    fi
}

# Function to connect to Redis
connect_redis() {
    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo "Error: Redis container is not running"
        exit 1
    fi

    local port=$DEFAULT_PORT
    if [ -f "/tmp/${CONTAINER_NAME}_port" ]; then
        port=$(cat "/tmp/${CONTAINER_NAME}_port")
    fi

    echo "Connecting to Redis container on port $port..."
    docker exec -it $CONTAINER_NAME redis-cli
}

# Function to show metrics status
show_metrics() {
    if ! docker ps | grep -q $EXPORTER_CONTAINER_NAME; then
        echo "Error: Redis Exporter is not running"
        exit 1
    fi

    local metrics_port
    if [ -f "/tmp/${CONTAINER_NAME}_metrics_port" ]; then
        metrics_port=$(cat "/tmp/${CONTAINER_NAME}_metrics_port")
        echo "Redis Metrics available at: http://localhost:${metrics_port}/metrics"
        echo -e "\nSample metrics you can monitor:"
        echo "- redis_up: Redis instance availability"
        echo "- redis_connected_clients: Number of client connections"
        echo "- redis_memory_used_bytes: Memory usage"
        echo "- redis_commands_total: Total number of commands processed"
        echo "- redis_keyspace_keys_total: Total number of keys by database"
    else
        echo "Error: Cannot find metrics port information"
    fi
}

# Function to stop and remove Redis containers
cleanup_redis() {
    for container in "$CONTAINER_NAME" "$EXPORTER_CONTAINER_NAME"; do
        if docker ps -a | grep -q $container; then
            echo "Stopping $container..."
            docker stop $container
            echo "Removing $container..."
            docker rm $container
        fi
    done

    # Remove port mapping files
    rm -f "/tmp/${CONTAINER_NAME}_port"
    rm -f "/tmp/${CONTAINER_NAME}_metrics_port"

    # Remove network if it exists
    if docker network inspect redis-net >/dev/null 2>&1; then
        docker network rm redis-net
    fi

    echo "Cleanup completed successfully!"
}

# Help message
show_help() {
    echo "Redis Docker Manager"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  list     - List available Redis versions"
    echo "  launch   - Launch Redis container with metrics exporter (requires version argument)"
    echo "  connect  - Connect to running Redis container"
    echo "  metrics  - Show metrics information and status"
    echo "  cleanup  - Stop and remove Redis containers"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 launch 7.2"
    echo "  $0 connect"
    echo "  $0 metrics"
    echo "  $0 cleanup"
}

# Main script logic
case "$1" in
    "list")
        list_versions
        ;;
    "launch")
        if [ -z "$2" ]; then
            echo "Error: Version argument required"
            echo "Usage: $0 launch <version>"
            exit 1
        fi
        launch_redis "$2"
        ;;
    "connect")
        connect_redis
        ;;
    "metrics")
        show_metrics
        ;;
    "cleanup")
        cleanup_redis
        ;;
    "help"|*)
        show_help
        ;;
esac