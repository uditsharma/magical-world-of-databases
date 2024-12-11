#!/bin/bash

COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

# Function to list available Redis versions
list_versions() {
    echo "Available Redis versions:"
    curl -s https://hub.docker.com/v2/repositories/library/redis/tags?page_size=100 \
        | jq -r '.results[].name' \
        | grep -E '^[0-9]+\.[0-9]+$' \
        | sort -V \
        | head -8
}

# Function to check if a port is in use
is_port_in_use() {
    if lsof -i ":$1" >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is available
    fi
}

# Function to find next available port
find_available_port() {
    local port=$1
    while is_port_in_use "$port"; do
        echo "Port $port is in use, trying next port..."  >&2
        port=$((port + 1))
    done
    printf "%d" "$port"  # Return only the number without any extra text
}

# Function to launch Redis
launch_redis() {
    local version=$1
    local memory=${2:-256mb}
    local policy=${3:-allkeys-lru}

    # Create .env file
    cat > $ENV_FILE << EOF
REDIS_VERSION=$version
REDIS_PORT=$(find_available_port 6379)
METRICS_PORT=$(find_available_port 9121)
REDIS_MEMORY=$memory
REDIS_POLICY=$policy
EOF

    echo "Launching Redis version $version at port $REDIS_PORT metric_port $METRICS_PORT with memory limit $memory and policy $policy..."
    docker-compose up -d
}

# Function to connect to Redis
connect_redis() {
    docker-compose exec redis redis-cli
}

# Function to show metrics
show_metrics() {
    local metrics_port=$(grep METRICS_PORT $ENV_FILE | cut -d= -f2)
    echo "Redis Metrics available at: http://localhost:${metrics_port}/metrics"
}

# Function to cleanup
cleanup_redis() {
    docker-compose down -v
    rm -f $ENV_FILE
}

case "$1" in
    "list")
        list_versions
        ;;
    "launch")
        if [ -z "$2" ]; then
            echo "Error: Version argument required"
            echo "Usage: $0 launch <version> [memory_limit] [memory_policy]"
            exit 1
        fi
        launch_redis "$2" "$3" "$4"
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
    *)
        echo "Usage: $0 {list|launch|connect|metrics|cleanup}"
        ;;
esac