#!/bin/bash

# Default values
DEFAULT_PORT=3306
DEFAULT_PASSWORD="password123"
DEFAULT_ROOT_PASSWORD="root123"

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

    echo "$return_port"
    return 0
}

get_mysql_versions() {
    # Get major versions only (no minor/patch) and limit to last 6
    curl -s https://registry.hub.docker.com/v2/repositories/library/mysql/tags?page_size=100 \
        | grep -o '"name":"[^"]*' \
        | grep -o '[^"]*$' \
        | grep '^[0-9][0-9]*$\|^[0-9]\.[0-9]$' \
        | sort -rV \
        | head -6
}

show_running_instances() {
    echo -e "\nRunning MySQL instances:" >&2
    echo "----------------------------" >&2
    if docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep -q mysql; then
        docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep mysql
    else
        echo "No MySQL instances currently running." >&2
    fi
    echo "----------------------------" >&2
}

cmd_list() {
    echo -e "\nAvailable MySQL versions:" >&2
    echo "----------------------------" >&2
    while read -r version; do
        local container_name="mysql${version}"
        local status=""
        if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
            status="[RUNNING]"
        elif docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
            status="[STOPPED]"
        fi
        echo "$version $status" >&2
    done < <(get_mysql_versions)
    echo "----------------------------" >&2
}

validate_version() {
    local version=$1
    local valid=false

    while read -r available_version; do
        if [[ "$available_version" == "$version"* ]]; then
            valid=true
            break
        fi
    done < <(get_mysql_versions)

    if [ "$valid" = false ]; then
        echo "Error: MySQL version $version not found!" >&2
        echo "Run '$0 list' to see available versions" >&2
        exit 1
    fi
}

wait_for_mysql() {
    local container_name=$1
    local max_attempts=30
    local attempt=1

    echo "Waiting for MySQL to be ready..." >&2
    while [ $attempt -le $max_attempts ]; do
        if docker exec $container_name mysqladmin ping -h localhost -u root -p$DEFAULT_ROOT_PASSWORD &>/dev/null; then
            echo "MySQL is ready!" >&2
            return 0
        fi
        echo "Attempt $attempt of $max_attempts..." >&2
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "MySQL failed to start properly" >&2
    return 1
}

cmd_start() {
    if [ $# -lt 1 ]; then
        echo "Error: Version required for start command" >&2
        usage
    fi
    local VERSION=$1
    local REQUESTED_PORT=${2:-$DEFAULT_PORT}

    validate_version $VERSION

    local PORT=$(check_port_availability "$REQUESTED_PORT")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    local CONTAINER_NAME="mysql${VERSION}"
    echo -e "\nStarting MySQL $VERSION on port $PORT..." >&2

    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo "Container $CONTAINER_NAME already exists. Removing it..." >&2
        docker rm -f $CONTAINER_NAME
    fi

    if ! docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PORT:3306" \
        -e MYSQL_ROOT_PASSWORD="$DEFAULT_ROOT_PASSWORD" \
        -e MYSQL_DATABASE=testdb \
        "mysql:$VERSION"; then
        echo "Failed to start MySQL container" >&2
        exit 1
    fi

    if ! wait_for_mysql "$CONTAINER_NAME"; then
        echo "Failed to initialize MySQL. Checking logs:" >&2
        docker logs "$CONTAINER_NAME"
        exit 1
    fi

    # Set up user after container is ready
    echo "Setting up MySQL user..." >&2
    # Set up user after container is ready
    echo "Setting up MySQL user..." >&2
    docker exec $CONTAINER_NAME mysql -uroot -p"$DEFAULT_ROOT_PASSWORD" -e "DROP USER IF EXISTS 'mysql'@'%';"
    docker exec $CONTAINER_NAME mysql -uroot -p"$DEFAULT_ROOT_PASSWORD" -e "CREATE USER 'mysql'@'%' IDENTIFIED WITH mysql_native_password BY '$DEFAULT_PASSWORD';"
    docker exec $CONTAINER_NAME mysql -uroot -p"$DEFAULT_ROOT_PASSWORD" -e "CREATE USER 'mysql'@'172.17.0.1' IDENTIFIED WITH mysql_native_password BY '$DEFAULT_PASSWORD';"
    docker exec $CONTAINER_NAME mysql -uroot -p"$DEFAULT_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'mysql'@'%';"
    docker exec $CONTAINER_NAME mysql -uroot -p"$DEFAULT_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'mysql'@'172.17.0.1';"
    docker exec $CONTAINER_NAME mysql -uroot -p"$DEFAULT_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

    echo -e "\nMySQL $VERSION is running on port $PORT" >&2
    echo "Root Password: $DEFAULT_ROOT_PASSWORD" >&2
    echo "User: mysql" >&2
    echo "Password: $DEFAULT_PASSWORD" >&2
    echo "Database: testdb" >&2
    show_running_instances
}

cmd_connect() {
    if [ $# -lt 1 ]; then
        echo "Error: Version required for connect command" >&2
        usage
    fi
    local VERSION=$1
    local CONTAINER_NAME="mysql${VERSION}"

    local PORT=$(docker port "$CONTAINER_NAME" 3306 2>/dev/null | cut -d ':' -f2)

    if [ -z "$PORT" ]; then
        echo "Container $CONTAINER_NAME is not running!" >&2
        show_running_instances
        exit 1
    fi

    echo -e "\nConnecting to MySQL $VERSION on port $PORT..." >&2
    mysql --protocol=TCP -h "127.0.0.1" -P "$PORT" -u mysql -p"$DEFAULT_PASSWORD" testdb
}

cmd_stop() {
    if [ $# -lt 1 ]; then
        echo "Error: Version required for stop command" >&2
        usage
    fi
    local VERSION=$1
    local CONTAINER_NAME="mysql${VERSION}"

    echo -e "\nStopping MySQL $VERSION..." >&2
    docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
    echo "MySQL $VERSION stopped and container removed" >&2
    show_running_instances
}

cmd_destroy() {
    if [ $# -lt 1 ]; then
        echo "Error: Version required for destroy command" >&2
        usage
    fi
    local VERSION=$1
    local CONTAINER_NAME="mysql${VERSION}"

    echo -e "\nDestroying MySQL $VERSION..." >&2

    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo "Container $CONTAINER_NAME does not exist!" >&2
        show_running_instances
        exit 1
    fi

    # Stop and remove the container forcefully
    docker kill "$CONTAINER_NAME" 2>/dev/null
    docker rm -f "$CONTAINER_NAME"

    echo "MySQL $VERSION has been destroyed" >&2
    show_running_instances
}

usage() {
    echo "Usage: $0 [start|stop|connect|list|ps|destroy] [VERSION] [PORT]"
    echo "Commands:"
    echo "  list              # List available MySQL versions"
    echo "  ps                # Show running MySQL instances"
    echo "  start VERSION     # Start MySQL container"
    echo "  connect VERSION   # Connect to MySQL container"
    echo "  stop VERSION      # Stop and remove MySQL container"
    echo "  destroy VERSION   # Forcefully remove MySQL container"
    echo
    echo "Examples:"
    echo "  $0 list          # Show available versions"
    echo "  $0 ps            # Show running instances"
    echo "  $0 start 8       # Start MySQL 8 on default port 3306"
    echo "  $0 start 5.7 3307 # Start MySQL 5.7 on port 3307"
    echo "  $0 connect 8     # Connect to MySQL 8"
    echo "  $0 stop 8        # Stop MySQL 8"
    echo "  $0 destroy 8     # Forcefully remove MySQL 8"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

ACTION=$1
shift

# In the case statement:
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
    destroy)
        cmd_destroy "$@"
        ;;
    *)
        usage
        ;;
esac