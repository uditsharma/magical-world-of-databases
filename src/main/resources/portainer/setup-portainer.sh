#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color
RED='\033[0;31m'
YELLOW='\033[1;33m'

# Default ports
DEFAULT_HTTP_PORT=9000
DEFAULT_HTTPS_PORT=9443
MAX_RETRIES=15  # Reduced from 30 to fail faster
RETRY_INTERVAL=2

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        return 0
    else
        return 1
    fi
}

# Function to find next available port
find_available_port() {
    local port=$1
    while check_port $port; do
        echo -e "${YELLOW}Port $port is in use, trying next port...${NC}" >&2
        port=$((port + 1))
    done
    printf "%d" "$port"
}

# Function to check container status
check_container_status() {
    local status=$(docker inspect -f '{{.State.Status}}' portainer 2>/dev/null)
    local health=$(docker inspect -f '{{.State.Health.Status}}' portainer 2>/dev/null)
    echo -e "${YELLOW}Container Status: $status${NC}"
    if [ ! -z "$health" ]; then
        echo -e "${YELLOW}Health Status: $health${NC}"
    fi
}

# Function to check if service is healthy
check_service_health() {
    local port=$1
    local retry_count=0

    echo -e "Waiting for Portainer to be ready..."
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Check container status every 5 retries
        if [ $((retry_count % 5)) -eq 0 ]; then
            check_container_status
        fi

        if curl -s -f http://localhost:$port/api/system/status > /dev/null 2>&1; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        echo -n "."
        sleep $RETRY_INTERVAL
    done

    echo -e "\n${RED}Service health check failed. Checking container logs:${NC}"
    docker logs portainer --tail 50
    return 1
}

# ... [rest of the script remains the same until the health check] ...

# Wait for service to be healthy
if ! check_service_health $HTTP_PORT; then
    echo -e "\n${RED}Error: Portainer failed to start properly${NC}"
    echo -e "${YELLOW}Troubleshooting steps:${NC}"
    echo "1. Check if Docker socket is accessible:"
    ls -l /var/run/docker.sock
    echo -e "\n2. Check if your user has Docker permissions:"
    groups $(whoami)
    echo -e "\n3. Try removing the container and volume:"
    echo "   docker rm -f portainer"
    echo "   docker volume rm portainer_data"
    rm -f $TMP_COMPOSE
    exit 1
fi

# ... [rest of the script remains the same] ...