#!/bin/bash

# OpenSearch Local Cluster Launch Script
# This script sets up and launches a local OpenSearch cluster using Docker

# Set variables
OPENSEARCH_VERSION="2.11.0"
CLUSTER_NAME="opensearch-local-cluster"
NODE_COUNT=3
DATA_DIR="./opensearch-data"
NETWORK_NAME="opensearch-net"

# Display banner
echo "==============================================="
echo "  OpenSearch Local Cluster Launcher"
echo "  Version: $OPENSEARCH_VERSION"
echo "  Nodes: $NODE_COUNT"
echo "==============================================="

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Error: Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create data directory if it doesn't exist
mkdir -p $DATA_DIR
# Set proper permissions for data directories
mkdir -p $DATA_DIR/node1 $DATA_DIR/node2 $DATA_DIR/node3
chmod -R 777 $DATA_DIR

# Create Docker network if it doesn't exist
if ! docker network inspect $NETWORK_NAME &> /dev/null; then
    echo "Creating Docker network: $NETWORK_NAME"
    docker network create $NETWORK_NAME
fi

# Generate docker-compose.yml
cat > docker-compose.yml << EOF
version: '3'
services:
  opensearch-node1:
    image: opensearchproject/opensearch:${OPENSEARCH_VERSION}
    container_name: opensearch-node1
    user: "1000:1000"
    environment:
      - cluster.name=${CLUSTER_NAME}
      - node.name=opensearch-node1
      - discovery.seed_hosts=opensearch-node1,opensearch-node2,opensearch-node3
      - cluster.initial_master_nodes=opensearch-node1,opensearch-node2,opensearch-node3
      - bootstrap.memory_lock=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
      - "DISABLE_INSTALL_DEMO_CONFIG=true"
      - "DISABLE_SECURITY_PLUGIN=true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - ${DATA_DIR}/node1:/usr/share/opensearch/data
    ports:
      - 9200:9200
      - 9600:9600
    networks:
      - ${NETWORK_NAME}

  opensearch-node2:
    image: opensearchproject/opensearch:${OPENSEARCH_VERSION}
    container_name: opensearch-node2
    user: "1000:1000"
    environment:
      - cluster.name=${CLUSTER_NAME}
      - node.name=opensearch-node2
      - discovery.seed_hosts=opensearch-node1,opensearch-node2,opensearch-node3
      - cluster.initial_master_nodes=opensearch-node1,opensearch-node2,opensearch-node3
      - bootstrap.memory_lock=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
      - "DISABLE_INSTALL_DEMO_CONFIG=true"
      - "DISABLE_SECURITY_PLUGIN=true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - ${DATA_DIR}/node2:/usr/share/opensearch/data
    networks:
      - ${NETWORK_NAME}

  opensearch-node3:
    image: opensearchproject/opensearch:${OPENSEARCH_VERSION}
    container_name: opensearch-node3
    user: "1000:1000"
    environment:
      - cluster.name=${CLUSTER_NAME}
      - node.name=opensearch-node3
      - discovery.seed_hosts=opensearch-node1,opensearch-node2,opensearch-node3
      - cluster.initial_master_nodes=opensearch-node1,opensearch-node2,opensearch-node3
      - bootstrap.memory_lock=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
      - "DISABLE_INSTALL_DEMO_CONFIG=true"
      - "DISABLE_SECURITY_PLUGIN=true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - ${DATA_DIR}/node3:/usr/share/opensearch/data
    networks:
      - ${NETWORK_NAME}

  opensearch-dashboards:
    image: opensearchproject/opensearch-dashboards:${OPENSEARCH_VERSION}
    container_name: opensearch-dashboards
    ports:
      - 5601:5601
    environment:
      - 'OPENSEARCH_HOSTS=["http://opensearch-node1:9200"]'
      - "DISABLE_SECURITY_DASHBOARDS_PLUGIN=true"
    networks:
      - ${NETWORK_NAME}

networks:
  ${NETWORK_NAME}:
    external: true
EOF

# Function to check if OpenSearch is up
check_opensearch_status() {
    echo "Checking OpenSearch cluster status..."
    for i in {1..3}; do
        if curl -s http://localhost:9200/_cluster/health | grep -q '"status":"green"'; then
            echo "OpenSearch cluster is up and running (green status)!"
            return 0
        elif curl -s http://localhost:9200/_cluster/health | grep -q '"status":"yellow"'; then
            echo "OpenSearch cluster is up with yellow status (some replicas may not be assigned)."
            return 0
        fi
        echo "Waiting for OpenSearch to start... ($i/30)"
        sleep 10
    done
    echo "Error: OpenSearch didn't start properly in the allocated time."

    # Debug information collection
    echo -e "\n===== DEBUGGING INFORMATION ====="
    echo "Collecting logs and diagnostics..."

    # Check container status
    echo -e "\n1. Container Status:"
    docker ps -a | grep opensearch

    # Get container logs
    echo -e "\n2. OpenSearch Node 1 Logs (last 50 lines):"
    docker logs opensearch-node1 --tail 50

    # Check if ports are in use
    echo -e "\n3. Checking if port 9200 is already in use:"
    netstat -tuln | grep 9200 || echo "Port 9200 is not in use by other processes."

    # Check system resources
    echo -e "\n4. System Resources:"
    echo "Available memory:"
    free -h
    echo "Available disk space:"
    df -h | grep -E '/$|/home'

    # Check Docker settings
    echo -e "\n5. Docker Settings:"
    echo "Docker info:"
    docker info | grep -E "Total Memory|Memory Limit"

    # Check max virtual memory areas
    echo -e "\n6. Virtual Memory Settings:"
    echo "Current max_map_count value (should be at least 262144):"
    cat /proc/sys/vm/max_map_count || echo "Unable to read max_map_count"

    # Provide troubleshooting suggestions
    echo -e "\n===== TROUBLESHOOTING SUGGESTIONS ====="
    echo "1. Check if your system has enough memory (Docker should have at least 4GB allocated)"
    echo "2. Increase virtual memory limits: sudo sysctl -w vm.max_map_count=262144"
    echo "3. Check for port conflicts on 9200 and 5601"
    echo "4. Try using 'docker-compose down -v' to clean up volumes and try again"
    echo "5. Reduce the heap size in the script if your system has limited memory"
    echo "6. Check the docker logs above for specific error messages"
    echo "7. Fix permission issues with: sudo chown -R 1000:1000 $DATA_DIR"
    echo "======================================"

    return 1
}

# Function to clean up on script termination
cleanup() {
    echo "Stopping OpenSearch cluster..."
    docker-compose down
    echo "Cleanup complete."
}

# Set up trap for cleanup on script termination
trap cleanup EXIT INT TERM

# Start OpenSearch cluster
echo "Starting OpenSearch cluster with $NODE_COUNT nodes..."
docker-compose up -d

# Check if OpenSearch is up
check_opensearch_status

# Display cluster information
if [ $? -eq 0 ]; then
    echo "===== OpenSearch Cluster Information ====="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Number of Nodes: $NODE_COUNT"
    echo "======================================"

    # Check cluster status
    echo -e "\nCluster Health:"
    curl -s -X GET "http://localhost:9200/_cluster/health?pretty"

    echo -e "\nNodes Information:"
    curl -s -X GET "http://localhost:9200/_cat/nodes?v"

    echo -e "\n===== OpenSearch Endpoints ====="
    echo "REST API Base URL: http://localhost:9200"
    echo "Dashboards URL: http://localhost:5601"
    echo ""
    echo "Useful REST API Endpoints:"
    echo "  Cluster Health: http://localhost:9200/_cluster/health"
    echo "  Cluster Stats: http://localhost:9200/_cluster/stats"
    echo "  Nodes Info: http://localhost:9200/_nodes/stats"
    echo "  Create Index: curl -X PUT \"http://localhost:9200/my-index\""
    echo "  Add Document: curl -X POST \"http://localhost:9200/my-index/_doc\" -H \"Content-Type: application/json\" -d '{\"field\":\"value\"}'"
    echo "  Search: curl -X GET \"http://localhost:9200/my-index/_search?q=field:value\""
    echo "  Get All Indices: http://localhost:9200/_cat/indices?v"
    echo ""
    echo "===== OpenSearch Dashboards ====="
    echo "Main Dashboard: http://localhost:5601"
    echo "Dev Tools (query interface): http://localhost:5601/app/dev_tools#/console"
    echo "Discover (search interface): http://localhost:5601/app/discover"
    echo "======================================"

    echo -e "\nTo stop the cluster, press Ctrl+C or run: docker-compose down"

    # Keep script running to allow for Ctrl+C cleanup
    while true; do
        sleep 1
    done
else
    echo "Failed to start OpenSearch cluster. See debugging information above."
    echo "You can also check full logs with: docker-compose logs"
    echo "To clean up and try again, run: docker-compose down -v && ./$(basename $0)"
    exit 1
fi