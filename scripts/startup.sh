#!/usr/bin/env bash
# Blue Team Swarm Startup Script
# Handles dependency waiting, signal forwarding, and graceful shutdown

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WAIT_FOR_IT_SCRIPT="$SCRIPT_DIR/wait-for-it.sh"
LOG_FILE="$PROJECT_DIR/logs/startup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Service configuration
SERVICES=(
    "redis:6379"
    "qdrant:6333"
    "prometheus:9090"
)
TIMEOUT=60
HEALTH_CHECK_INTERVAL=10

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Signal handling
cleanup() {
    log "INFO" "Received shutdown signal, initiating graceful shutdown..."
    
    # Send SIGTERM to child processes
    if [[ -n "${MAIN_PID:-}" ]]; then
        log "INFO" "Sending SIGTERM to main process (PID: $MAIN_PID)"
        kill -TERM "$MAIN_PID" 2>/dev/null || true
        
        # Wait for graceful shutdown or force kill after timeout
        local wait_time=0
        while kill -0 "$MAIN_PID" 2>/dev/null && [[ $wait_time -lt 30 ]]; do
            sleep 1
            wait_time=$((wait_time + 1))
        done
        
        # Force kill if still running
        if kill -0 "$MAIN_PID" 2>/dev/null; then
            log "WARN" "Process did not terminate gracefully, forcing shutdown"
            kill -KILL "$MAIN_PID" 2>/dev/null || true
        fi
    fi
    
    log "INFO" "Graceful shutdown completed"
    exit 0
}

# Set up signal handlers
setup_signal_handlers() {
    trap cleanup SIGTERM SIGINT SIGQUIT
}

# Check if wait-for-it.sh script exists
check_wait_script() {
    if [[ ! -f "$WAIT_FOR_IT_SCRIPT" ]]; then
        log "ERROR" "wait-for-it.sh script not found at $WAIT_FOR_IT_SCRIPT"
        exit 1
    fi
    
    # Make it executable
    chmod +x "$WAIT_FOR_IT_SCRIPT"
}

# Wait for dependencies
wait_for_dependencies() {
    log "INFO" "Waiting for dependencies to be ready..."
    
    for service in "${SERVICES[@]}"; do
        local host=$(echo "$service" | cut -d: -f1)
        local port=$(echo "$service" | cut -d: -f2)
        
        log "INFO" "Waiting for $host:$port..."
        
        if ! "$WAIT_FOR_IT_SCRIPT" -h "$host" -p "$port" -t "$TIMEOUT" --strict --quiet; then
            log "ERROR" "Timeout waiting for $host:$port"
            exit 1
        fi
        
        log "INFO" "$host:$port is ready"
    done
    
    log "INFO" "All dependencies are ready"
}

# Health check for services
health_check() {
    local service_name=$1
    local health_url=$2
    local max_attempts=30
    local attempt=0
    
    log "INFO" "Performing health check for $service_name..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f -s "$health_url" > /dev/null 2>&1; then
            log "INFO" "$service_name is healthy"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log "DEBUG" "Health check attempt $attempt/$max_attempts for $service_name failed"
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    log "ERROR" "Health check failed for $service_name after $max_attempts attempts"
    return 1
}

# Perform comprehensive health checks
perform_health_checks() {
    log "INFO" "Performing comprehensive health checks..."
    
    # Check Redis
    if ! health_check "Redis" "http://redis:6379"; then
        log "WARN" "Redis health check failed, but continuing..."
    fi
    
    # Check Qdrant
    if ! health_check "Qdrant" "http://qdrant:6333/health"; then
        log "WARN" "Qdrant health check failed, but continuing..."
    fi
    
    # Check Prometheus
    if ! health_check "Prometheus" "http://prometheus:9090/-/healthy"; then
        log "WARN" "Prometheus health check failed, but continuing..."
    fi
    
    log "INFO" "Health checks completed"
}

# Start the main application
start_application() {
    log "INFO" "Starting the main application..."
    
    # Change to the application directory
    cd "$PROJECT_DIR"
    
    # Start the application in the background
    if [[ -n "${1:-}" ]]; then
        # If a command is provided, execute it
        log "INFO" "Executing command: $*"
        exec "$@" &
    else
        # Default: start the orchestrator
        log "INFO" "Starting orchestrator..."
        cd orchestrator
        python app.py &
    fi
    
    # Store the PID of the main process
    MAIN_PID=$!
    log "INFO" "Main application started with PID: $MAIN_PID"
    
    # Wait for the main process
    wait "$MAIN_PID"
    local exit_code=$?
    
    log "INFO" "Main application exited with code: $exit_code"
    exit $exit_code
}

# Display startup banner
display_banner() {
    cat << 'EOF'
 ____              _    _               _____ _ _            
|  _ \            | |  (_)             |  ___(_) |           
| |_) | __ _ _ __ | | ___ _ __   __ _  | |__  _| | ___  _ __ 
|  _ < / _` | '_ \| |/ / | '_ \ / _` | |  __| | |/ _ \| '__|
| |_) | (_| | | | |   <| | | | | (_| | | |    | | (_) | |   
|____/ \__,_|_| |_|_|\_\_|_| |_|\__, | \_|    |_|\___/|_|   
                                 __/ |                      
                                |___/                       
EOF
    echo ""
    log "INFO" "Blue Team Swarm Startup Script"
    log "INFO" "Version: 1.5.0"
    echo ""
}

# Display environment information
display_environment_info() {
    log "INFO" "Environment Information:"
    echo "  Hostname: $(hostname)"
    echo "  User: $(whoami)"
    echo "  Working Directory: $(pwd)"
    echo "  Shell: $SHELL"
    echo "  Docker Compose Version: $(docker-compose --version 2>/dev/null || docker compose version 2>/dev/null || echo 'Not found')"
    echo ""
}

# Main execution
main() {
    # Display startup banner
    display_banner
    
    # Display environment information
    display_environment_info
    
    # Set up signal handlers
    setup_signal_handlers
    
    # Check if wait-for-it.sh script exists
    check_wait_script
    
    # Wait for dependencies
    wait_for_dependencies
    
    # Perform health checks
    perform_health_checks
    
    # Start the application
    log "INFO" "Starting application..."
    start_application "$@"
}

# Run main function with all arguments
main "$@"