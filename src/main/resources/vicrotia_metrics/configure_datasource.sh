#!/bin/bash

# Configuration variables
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"
DATASOURCE_NAME="VictoriaMetrics"
VICTORIA_METRICS_URL="http://victoriametrics:8090"

# Wait for Grafana to be ready
wait_for_grafana() {
    echo "Waiting for Grafana to be ready..."
    local max_attempts=30
    local attempt=1
    while ! curl -s "$GRAFANA_URL/api/health" > /dev/null; do
        if [ $attempt -gt $max_attempts ]; then
            echo "Grafana did not become ready in time"
            exit 1
        fi
        echo "Attempt $attempt of $max_attempts: Waiting for Grafana..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "Grafana is ready"
}

# Create API token
create_api_token() {
    echo "Creating API token..."
    local response=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "name": "datasource-token",
        "role": "Admin"
    }' -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/auth/keys")

    local token=$(echo "$response" | jq -r .key 2>/dev/null)
    if [ "$token" = "null" ] || [ -z "$token" ]; then
        echo "Failed to create API token. Response: $response"
        exit 1
    fi
    echo "$token"
}

# Get datasource ID
get_datasource_id() {
    local token=$1
    local response=$(curl -s \
        -H "Authorization: Bearer $token" \
        "$GRAFANA_URL/api/datasources/name/$DATASOURCE_NAME")

    echo "$response" | jq -r '.id' 2>/dev/null
}

# Update datasource
update_datasource() {
    local token=$1
    local datasource_id=$2
    echo "Updating VictoriaMetrics datasource..."

    local response=$(curl -s -X PUT \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d '{
            "name": "'"$DATASOURCE_NAME"'",
            "type": "prometheus",
            "url": "'"$VICTORIA_METRICS_URL"'",
            "access": "server",
            "basicAuth": false,
            "isDefault": true,
            "jsonData": {
                "timeInterval": "15s"
            }
        }' \
        "$GRAFANA_URL/api/datasources/$datasource_id")

    if [ $? -ne 0 ]; then
        echo "Failed to update datasource"
        exit 1
    fi
    echo "Datasource updated successfully"
}

# Add datasource
add_datasource() {
    local token=$1
    echo "Adding VictoriaMetrics datasource..."

    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d '{
            "name": "'"$DATASOURCE_NAME"'",
            "type": "prometheus",
            "url": "'"$VICTORIA_METRICS_URL"'",
            "access": "server",
            "basicAuth": false,
            "isDefault": true,
            "jsonData": {
                "timeInterval": "15s"
            }
        }' \
        "$GRAFANA_URL/api/datasources")

    if [ $? -ne 0 ]; then
        echo "Failed to add datasource"
        exit 1
    fi
    echo "Datasource added successfully"
}

# Verify datasource
# Verify datasource
verify_datasource() {
    local token=$1
    echo "Verifying datasource..."

    # Get full response with headers
    local response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $token" \
        "$GRAFANA_URL/api/datasources/name/$DATASOURCE_NAME")

    # Split response into body and status code
    local body=$(echo "$response" | sed -n '1p')
    local status_code=$(echo "$response" | sed -n '2p')

    echo "Response status code: $status_code"
    echo "Response body: $body"

    if [ "$status_code" != "200" ]; then
        echo "Failed to verify datasource. Status code: $status_code"
        return 1
    fi

    if [ -n "$body" ]; then
        local is_default=$(echo "$body" | jq -r '.isDefault // false')
        if [ "$is_default" = "true" ]; then
            echo "Datasource is configured as default"
            return 0
        else
            echo "Warning: Datasource is not set as default"
            return 1
        fi
    else
        echo "Warning: Empty response body"
        return 1
    fi
}

# Main execution
echo "Starting Grafana datasource configuration..."

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Please install jq first:"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  CentOS/RHEL: sudo yum install jq"
    echo "  macOS: brew install jq"
    exit 1
fi

# Wait for Grafana to be ready
wait_for_grafana

# Create API token
TOKEN=$(create_api_token)

# Get datasource ID
DATASOURCE_ID=$(get_datasource_id "$TOKEN")

if [ -n "$DATASOURCE_ID" ] && [ "$DATASOURCE_ID" != "null" ]; then
    echo "Updating existing datasource..."
    update_datasource "$TOKEN" "$DATASOURCE_ID"
else
    echo "Adding new datasource..."
    add_datasource "$TOKEN"
fi

# Verify configuration
if verify_datasource "$TOKEN"; then
    echo "Configuration completed successfully!"
else
    echo "Configuration completed with warnings!"
fi