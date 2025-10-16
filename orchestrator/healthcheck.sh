#!/bin/bash

# Health check script for ATS Sentinel Swarm Orchestrator
# This script performs multiple health checks to ensure the service is running properly

set -e

# Configuration
HEALTH_CHECK_URL="http://localhost:8080/health"
TIMEOUT=10
MAX_RETRIES=3

# Function to check if the service is responding
check_service_response() {
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        echo "Attempt $attempt: Checking service response..."
        
        if curl -f -s --max-time $TIMEOUT "$HEALTH_CHECK_URL" > /dev/null; then
            echo "Service is responding correctly"
            return 0
        fi
        
        echo "Service not responding, waiting before retry..."
        sleep 5
        ((attempt++))
    done
    
    echo "Service failed to respond after $MAX_RETRIES attempts"
    return 1
}

# Function to check dependencies
check_dependencies() {
    echo "Checking dependencies..."
    
    # Check Redis connection
    if [ -n "$REDIS_URL" ]; then
        echo "Checking Redis connection..."
        if ! python -c "
import os
import redis
try:
    r = redis.from_url(os.environ.get('REDIS_URL', 'redis://localhost:6379/0'))
    r.ping()
    print('Redis connection: OK')
except Exception as e:
    print(f'Redis connection failed: {e}')
    exit(1)
" 2>/dev/null; then
            echo "Redis health check failed"
            return 1
        fi
    else
        echo "REDIS_URL not set, skipping Redis check"
    fi
    
    # Check Qdrant connection
    if [ -n "$QDRANT_URL" ]; then
        echo "Checking Qdrant connection..."
        if ! curl -f -s --max-time $TIMEOUT "$QDRANT_URL/health" > /dev/null; then
            echo "Qdrant health check failed"
            return 1
        fi
        echo "Qdrant connection: OK"
    else
        echo "QDRANT_URL not set, skipping Qdrant check"
    fi
    
    return 0
}

# Function to check application health
check_application_health() {
    echo "Checking application health..."
    
    # Check critical endpoints
    local endpoints=("/health" "/metrics")
    
    for endpoint in "${endpoints[@]}"; do
        echo "Checking endpoint: $endpoint"
        if ! curl -f -s --max-time $TIMEOUT "http://localhost:8080$endpoint" > /dev/null; then
            echo "Endpoint $endpoint is not responding correctly"
            return 1
        fi
    done
    
    # Check process health
    if ! pgrep -f "uvicorn" > /dev/null; then
        echo "Application process is not running"
        return 1
    fi
    
    echo "Application health: OK"
    return 0
}

# Function to check disk space
check_disk_space() {
    echo "Checking disk space..."
    
    # Check if uploads directory has space
    if [ -d "/app/uploads" ]; then
        local available_space=$(df /app/uploads | awk 'NR==2 {print $4}')
        local required_space=10240  # 10MB in KB
        
        if [ "$available_space" -lt "$required_space" ]; then
            echo "Low disk space in uploads directory"
            return 1
        fi
    fi
    
    # Check if logs directory has space
    if [ -d "/app/logs" ]; then
        local available_space=$(df /app/logs | awk 'NR==2 {print $4}')
        local required_space=10240  # 10MB in KB
        
        if [ "$available_space" -lt "$required_space" ]; then
            echo "Low disk space in logs directory"
            return 1
        fi
    fi
    
    echo "Disk space: OK"
    return 0
}

# Main health check function
main() {
    echo "Starting comprehensive health check..."
    
    # Run all checks
    check_service_response || exit 1
    check_dependencies || exit 1
    check_application_health || exit 1
    check_disk_space || exit 1
    
    echo "All health checks passed successfully"
    exit 0
}

# Execute main function
main "$@"