#!/bin/bash

CONTAINER_NAME="redis-instance"
DEFAULT_PORT=6379

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

# Function to launch Redis container
launch_redis() {
    local version=$1
    validate_version "$version"

    # Check if container already exists
    if docker ps -a | grep -q $CONTAINER_NAME; then
        echo "Error: Redis container already exists. Stop and remove it first."
        exit 1
    fi

    # Find available port
    local port=$(find_available_port "$DEFAULT_PORT")
    echo $port

    echo "Launching Redis version $version on port $port..."

    # Launch container with proper port mapping
    if docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${port}:6379" \
        "redis:$version"; then

        echo "Redis container launched successfully!"
        echo "Container ID: $(docker ps -q -f name=$CONTAINER_NAME)"
        echo "Port: $port"

        # Save the port mapping for future reference
        echo "$port" > "/tmp/${CONTAINER_NAME}_port"
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

    # Get the port from saved mapping
    local port=$DEFAULT_PORT
    if [ -f "/tmp/${CONTAINER_NAME}_port" ]; then
        port=$(cat "/tmp/${CONTAINER_NAME}_port")
    fi

    echo "Connecting to Redis container on port $port..."
    docker exec -it $CONTAINER_NAME redis-cli
}

# Function to stop and remove Redis container
cleanup_redis() {
    if docker ps -a | grep -q $CONTAINER_NAME; then
        echo "Stopping Redis container..."
        docker stop $CONTAINER_NAME
        echo "Removing Redis container..."
        docker rm $CONTAINER_NAME

        # Remove port mapping file
        rm -f "/tmp/${CONTAINER_NAME}_port"

        echo "Redis container cleaned up successfully!"
    else
        echo "No Redis container found"
    fi
}

# Help message
show_help() {
    echo "Redis Docker Manager"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  list     - List available Redis versions"
    echo "  launch   - Launch Redis container (requires version argument)"
    echo "  connect  - Connect to running Redis container"
    echo "  cleanup  - Stop and remove Redis container"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 launch 7.2"
    echo "  $0 connect"
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
    "cleanup")
        cleanup_redis
        ;;
    "help"|*)
        show_help
        ;;
esac