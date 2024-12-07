#!/bin/bash

# Default values
DEFAULT_PORT=5432
DEFAULT_PASSWORD="password123"

# Function to find next available port
find_next_available_port() {
    local port=$1
    while true; do
        if ! lsof -i :$port > /dev/null 2>&1 && ! nc -z localhost $port > /dev/null 2>&1; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done
}

# Function to check port availability
check_port_availability() {
    local port=$1
    local return_port=""

    echo "Checking port $port..." >&2
    if lsof -i :$port > /dev/null 2>&1 || nc -z localhost $port > /dev/null 2>&1; then
        echo -e "\nWarning: Port $port is already in use!" >&2
        echo "Current process using port $port:" >&2
        lsof -i :$port || netstat -an | grep $port >&2

        local next_port=$(find_next_available_port $((port + 1)))

        echo -e "\nWould you like to:" >&2
        echo "1) Use next available port: $next_port" >&2
        echo "2) Specify a different port" >&2
        echo "3) Exit" >&2
        read -p "Choose an option (1-3): " choice

        case $choice in
            1)
                return_port="$next_port"
                ;;
            2)
                while true; do
                    read -p "Enter port number: " custom_port
                    if ! lsof -i :$custom_port > /dev/null 2>&1 && ! nc -z localhost $custom_port > /dev/null 2>&1; then
                        return_port="$custom_port"
                        break
                    else
                        echo "Error: Port $custom_port is also in use. Please try another port." >&2
                    fi
                done
                ;;
            3)
                return 1
                ;;
            *)
                echo "Invalid choice. Exiting." >&2
                return 1
                ;;
        esac
    else
        return_port="$port"
    fi

    # Only output the port number, nothing else
    echo "$return_port"
    return 0
}

# Function to get PostgreSQL versions
get_postgres_versions() {
    curl -s https://registry.hub.docker.com/v2/repositories/library/postgres/tags?page_size=100 \
        | grep -o '"name":"[^"]*' \
        | grep -o '[^"]*$' \
        | grep '^[0-9][0-9]*$' \
        | sort -rn \
        | head -6
}

# Function to show running instances
show_running_instances() {
    echo -e "\nRunning PostgreSQL instances:"  >&2
    echo "----------------------------"
    if docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep -q postgres; then
        docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep postgres
    else
        echo "No PostgreSQL instances currently running."  >&2
    fi
    echo "----------------------------"
}

# Function to list available versions
cmd_list() {
    echo -e "\nAvailable PostgreSQL versions:"  >&2
    echo "----------------------------"
    while read -r version; do
        local container_name="postgres${version}"
        local status=""
        if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
            status="[RUNNING]"
        elif docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
            status="[STOPPED]"
        fi
        echo "$version $status"
    done < <(get_postgres_versions)
    echo "----------------------------"
}

# Function to validate version
validate_version() {
    local version=$1
    local valid=false

    while read -r available_version; do
        if [[ "$available_version" == "$version"* ]]; then
            valid=true
            break
        fi
    done < <(get_postgres_versions)

    if [ "$valid" = false ]; then
        echo "Error: PostgreSQL version $version not found!"
        echo "Run '$0 list' to see available versions"
        exit 1
    fi
}

# Function to start PostgreSQL
cmd_start() {
    if [ $# -lt 1 ]; then
        echo "Error: Version required for start command"
        usage
    fi
    local VERSION=$1
    local REQUESTED_PORT=${2:-$DEFAULT_PORT}

    validate_version $VERSION
    echo "Starting PostgreSQL $VERSION..."  >&2
    local PORT=$(check_port_availability "$REQUESTED_PORT")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    local CONTAINER_NAME="postgres${VERSION}"
    echo -e "\nStarting PostgreSQL $VERSION on port $PORT..."  >&2

    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo "Container $CONTAINER_NAME already exists. Removing it..."  >&2
        docker rm -f $CONTAINER_NAME
    fi

    if ! docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PORT:5432" \
        -e POSTGRES_PASSWORD="$DEFAULT_PASSWORD" \
        "postgres:$VERSION"; then
        echo "Failed to start PostgreSQL container"
        exit 1
    fi

    echo -e "\nWaiting for PostgreSQL to start..."
    sleep 3

    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        echo "Container failed to start. Checking logs:"  >&2
        docker logs "$CONTAINER_NAME"
        exit 1
    fi

    echo -e "\nPostgreSQL $VERSION is running on port $PORT"
    echo "Password: $DEFAULT_PASSWORD"
    show_running_instances
}

# Function to connect to PostgreSQL
cmd_connect() {
    if [ $# -lt 1 ]; then
        echo "Error: Version required for connect command"  >&2
        usage
    fi
    local VERSION=$1
    local CONTAINER_NAME="postgres${VERSION}"

    local PORT=$(docker port "$CONTAINER_NAME" 5432 2>/dev/null | cut -d ':' -f2)

    if [ -z "$PORT" ]; then
        echo "Container $CONTAINER_NAME is not running!"  >&2
        show_running_instances
        exit 1
    fi

    echo -e "\nConnecting to PostgreSQL $VERSION on port $PORT..."  >&2
    PGPASSWORD="$DEFAULT_PASSWORD" psql -h localhost -p "$PORT" -U postgres
}

# Function to stop PostgreSQL
cmd_stop() {
    if [ $# -lt 1 ]; then
        echo "Error: Version required for stop command"
        usage
    fi
    local VERSION=$1
    local CONTAINER_NAME="postgres${VERSION}"

    echo -e "\nStopping PostgreSQL $VERSION..."
    docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
    echo "PostgreSQL $VERSION stopped and container removed"
    show_running_instances
}

# Function to show help
usage() {
    echo "Usage: $0 [start|stop|connect|list|ps] [VERSION] [PORT]"
    echo "Commands:"
    echo "  list              # List available PostgreSQL versions"
    echo "  ps                # Show running PostgreSQL instances"
    echo "  start VERSION     # Start PostgreSQL container"
    echo "  connect VERSION   # Connect to PostgreSQL container"
    echo "  stop VERSION      # Stop and remove PostgreSQL container"
    echo
    echo "Examples:"
    echo "  $0 list          # Show available versions"
    echo "  $0 ps            # Show running instances"
    echo "  $0 start 14      # Start PostgreSQL 14 on default port 5432"
    echo "  $0 start 15 5433 # Start PostgreSQL 15 on port 5433"
    echo "  $0 connect 14    # Connect to PostgreSQL 14"
    echo "  $0 stop 14       # Stop PostgreSQL 14"
    exit 1
}

# Main command processing
if [ $# -lt 1 ]; then
    usage
fi

ACTION=$1
shift  # Remove the action argument

case $ACTION in
    ps)
        show_running_instances
        ;;
    list)
        cmd_list
        ;;
    start)
        cmd_start "$@"
        ;;
    connect)
        cmd_connect "$@"
        ;;
    stop)
        cmd_stop "$@"
        ;;
    *)
        usage
        ;;
esac