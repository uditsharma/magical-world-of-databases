#!/bin/bash

# setup.sh
set -e

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. Please install Docker first."
        exit 1
    fi
}

# Function to check if Docker Compose is installed
check_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
}

# Function to check if ports are available
check_ports() {
    local ports=("8090" "8091" "3000")
    for port in "${ports[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
            echo "Port $port is already in use. Please free it up before continuing."
            exit 1
        fi
    done
}

# Main setup function
setup_victoria_metrics() {
    echo "Starting Victoria Metrics setup..."

    # Pull required Docker images
    echo "Pulling Docker images..."
    docker-compose pull

    # Start the services
    echo "Starting services..."
    docker-compose up -d

    # Wait for services to be ready
    echo "Waiting for services to start..."
    sleep 10

    echo "Setup complete! Services are available at:"
    echo "Victoria Metrics: http://localhost:8428"
    echo "Grafana: http://localhost:3000 (login: admin/admin)"
    echo "vmagent: http://localhost:8429"
}

# Function to clean up in case of failure
cleanup() {
    echo "An error occurred. Cleaning up..."
    docker-compose down
    exit 1
}

# Set up error handling
trap cleanup ERR

# Main execution
echo "Checking prerequisites..."
check_docker
check_docker_compose
check_ports

# Run setup
setup_victoria_metrics

echo "
Setup completed successfully!

To manage the setup:
- Start: docker-compose up -d
- Stop:  docker-compose down
- Logs:  docker-compose logs
- Status: docker-compose ps
"