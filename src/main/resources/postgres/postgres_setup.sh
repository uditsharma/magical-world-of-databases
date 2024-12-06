#!/bin/bash

# Default values
DEFAULT_PORT=5432
DEFAULT_PASSWORD="password123"

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

check_port_availability() {
    local port=$1
    echo "Checking port availability..."
    if lsof -i :$port > /dev/null 2>&1 || nc -z localhost $port > /dev/null 2>&1; then
        echo -e "\nWarning: Port $port is already in use!"
        echo "Current process using port $port:"
        lsof -i :$port || netstat -an | grep $port

        local next_port=$(find_next_available_port $((port + 1)))

        echo -e "\nWould you like to:"
        echo "1) Use next available port: $next_port"
        echo "2) Specify a different port"
        echo "3) Exit"
        read -p "Choose an option (1-3): " choice

        case $choice in
            1)
                echo "$next_port"
                return 0
                ;;
            2)
                while true; do
                    read -p "Enter port number: " custom_port
                    if ! lsof -i :$custom_port > /dev/null 2>&1 && ! nc -z localhost $custom_port > /dev/null 2>&1; then
                        echo "$custom_port"
                        return 0
                    else
                        echo "Error: Port $custom_port is also in use. Please try another port."
                    fi
                done
                ;;
            3)
                return 1
                ;;
            *)
                echo "Invalid choice. Exiting."
                return 1
                ;;
        esac
    else
        echo "$port"
        return 0
    fi
}

get_postgres_versions() {
    # Get major versions only (no minor/patch) and limit to last 6
    curl -s https://registry.hub.docker.com/v2/repositories/library/postgres/tags?page_size=100 \
        | grep -o '"name":"[^"]*' \
        | grep -o '[^"]*$' \
        | grep '^[0-9][0-9]*$' \
        | sort -rn \
        | head -6
}

show_running_instances() {
    echo -e "\nRunning PostgreSQL instances:"
    echo "----------------------------"
    if docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep -q postgres; then
        docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep postgres
    else
        echo "No PostgreSQL instances currently running."
    fi
    echo "----------------------------"
}

list_versions() {
    echo -e "\nAvailable PostgreSQL versions:"
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

if [ $# -lt 1 ]; then
    usage
fi

ACTION=$1
case $ACTION in
    ps)
        show_running_instances
        ;;

    list)
        list_versions
        ;;

    start)
        if [ $# -lt 2 ]; then
            echo "Error: Version required for start command"
            usage
        fi
        VERSION=$2
        REQUESTED_PORT=${3:-$DEFAULT_PORT}

        # Validate version before checking port
        validate_version $VERSION

        # Get available port (store result)
        PORT=$(check_port_availability "$REQUESTED_PORT")
        if [ $? -ne 0 ]; then
            exit 1
        fi

        CONTAINER_NAME="postgres${VERSION}"
        echo -e "\nStarting PostgreSQL $VERSION on port $PORT..."

        if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
            echo "Container $CONTAINER_NAME already exists. Removing it..."
            docker rm -f $CONTAINER_NAME
        fi

        docker run -d \
            --name "$CONTAINER_NAME" \
            -p "$PORT:5432" \
            -e POSTGRES_PASSWORD="$DEFAULT_PASSWORD" \
            "postgres:$VERSION"

        echo -e "\nWaiting for PostgreSQL to start..."
        sleep 3

        echo -e "\nPostgreSQL $VERSION is running on port $PORT"
        echo "Password: $DEFAULT_PASSWORD"
        show_running_instances
        ;;

    connect)
        if [ $# -lt 2 ]; then
            echo "Error: Version required for connect command"
            usage
        fi
        VERSION=$2
        CONTAINER_NAME="postgres${VERSION}"

        # Get the actual port from docker
        PORT=$(docker port "$CONTAINER_NAME" 5432 2>/dev/null | cut -d ':' -f2)

        if [ -z "$PORT" ]; then
            echo "Container $CONTAINER_NAME is not running!"
            show_running_instances
            exit 1
        fi

        echo -e "\nConnecting to PostgreSQL $VERSION on port $PORT..."
        PGPASSWORD="$DEFAULT_PASSWORD" psql -h localhost -p "$PORT" -U postgres
        ;;

    stop)
        if [ $# -lt 2 ]; then
            echo "Error: Version required for stop command"
            usage
        fi
        VERSION=$2
        CONTAINER_NAME="postgres${VERSION}"

        echo -e "\nStopping PostgreSQL $VERSION..."
        docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
        echo "PostgreSQL $VERSION stopped and container removed"
        show_running_instances
        ;;

    *)
        usage
        ;;
esac