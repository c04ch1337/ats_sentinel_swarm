#!/usr/bin/env bash
# Blue Team Swarm Deployment Script
# Handles deployment for both development and production environments

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
LOG_FILE="$PROJECT_DIR/logs/deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
SKIP_BACKUP=false
SKIP_VALIDATION=false
COMPOSE_FILE="docker-compose.yml"
COMPOSE_OVERRIDE=""
PERFORM_RESTORE=false
RESTORE_FILE=""

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

# Display usage information
usage() {
    cat << EOF
Blue Team Swarm Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    -e, --environment ENV     Set environment (development|production) [default: production]
    -b, --backup              Create backup before deployment
    -s, --skip-backup         Skip backup creation
    -v, --skip-validation     Skip environment validation
    -r, --restore FILE        Restore from backup file
    -h, --help                Show this help message

EXAMPLES:
    $0                        # Deploy to production
    $0 -e development         # Deploy to development
    $0 -b                     # Deploy to production with backup
    $0 -r backup_20231015.tar.gz  # Restore from backup

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -b|--backup)
                SKIP_BACKUP=false
                shift
                ;;
            -s|--skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            -v|--skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            -r|--restore)
                PERFORM_RESTORE=true
                RESTORE_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Validate environment
validate_environment() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log "WARN" "Skipping environment validation"
        return 0
    fi
    
    log "INFO" "Validating environment..."
    
    # Check if .env file exists
    if [[ ! -f "$PROJECT_DIR/.env" ]]; then
        log "ERROR" ".env file not found. Please copy .env.example to .env and configure it."
        exit 1
    fi
    
    # Check Docker and Docker Compose
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log "ERROR" "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    # Validate environment variables
    source "$PROJECT_DIR/.env"
    
    # Check required variables
    local required_vars=("LLM_PROVIDER")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR" "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    # Check LLM provider specific variables
    case "$LLM_PROVIDER" in
        "OPENAI")
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                log "ERROR" "OPENAI_API_KEY is required when using OpenAI provider"
                exit 1
            fi
            ;;
        "ANTHROPIC")
            if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
                log "ERROR" "ANTHROPIC_API_KEY is required when using Anthropic provider"
                exit 1
            fi
            ;;
        "AZURE_OPENAI")
            if [[ -z "${AZURE_OPENAI_API_KEY:-}" || -z "${AZURE_OPENAI_ENDPOINT:-}" || -z "${AZURE_OPENAI_DEPLOYMENT:-}" ]]; then
                log "ERROR" "AZURE_OPENAI_API_KEY, AZURE_OPENAI_ENDPOINT, and AZURE_OPENAI_DEPLOYMENT are required when using Azure OpenAI provider"
                exit 1
            fi
            ;;
        "OLLAMA")
            if [[ -z "${OLLAMA_BASE_URL:-}" ]]; then
                log "WARN" "OLLAMA_BASE_URL is not set, using default http://host.docker.internal:11434"
            fi
            ;;
        *)
            log "ERROR" "Invalid LLM_PROVIDER: $LLM_PROVIDER. Must be one of: OPENAI, ANTHROPIC, AZURE_OPENAI, OLLAMA"
            exit 1
            ;;
    esac
    
    log "INFO" "Environment validation completed successfully"
}

# Set up proper permissions for volumes
setup_permissions() {
    log "INFO" "Setting up permissions for volumes..."
    
    # Create necessary directories
    mkdir -p "$PROJECT_DIR/logs"
    mkdir -p "$PROJECT_DIR/uploads"
    mkdir -p "$BACKUP_DIR"
    
    # Set permissions
    chmod 755 "$PROJECT_DIR/logs"
    chmod 755 "$PROJECT_DIR/uploads"
    chmod 700 "$BACKUP_DIR"
    
    # If running on Linux, set proper ownership
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Get current user ID and group ID
        local uid=$(id -u)
        local gid=$(id -g)
        
        # Create a .dockerenv file with user info for containers
        echo "UID=$uid" > "$PROJECT_DIR/.dockerenv"
        echo "GID=$gid" >> "$PROJECT_DIR/.dockerenv"
    fi
    
    log "INFO" "Permissions setup completed"
}

# Create backup
create_backup() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log "INFO" "Skipping backup creation"
        return 0
    fi
    
    log "INFO" "Creating backup..."
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$BACKUP_DIR/backup_$timestamp.tar.gz"
    
    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR"
    
    # Stop services
    log "INFO" "Stopping services for backup..."
    cd "$PROJECT_DIR"
    docker-compose down
    
    # Create backup
    tar -czf "$backup_file" \
        --exclude="$BACKUP_DIR" \
        --exclude="$PROJECT_DIR/logs/*.log" \
        -C "$PROJECT_DIR" \
        .env \
        uploads/ \
        logs/ \
        grafana_data/ \
        prometheus_data/ \
        redis_data/ \
        n8n_data/ \
        qdrant_storage/ 2>/dev/null || true
    
    log "INFO" "Backup created: $backup_file"
    
    # Clean old backups (keep last 7)
    find "$BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime +7 -delete 2>/dev/null || true
    
    # Restart services
    log "INFO" "Restarting services after backup..."
    docker-compose up -d
}

# Restore from backup
restore_backup() {
    if [[ "$PERFORM_RESTORE" != "true" ]]; then
        return 0
    fi
    
    if [[ ! -f "$RESTORE_FILE" ]]; then
        log "ERROR" "Backup file not found: $RESTORE_FILE"
        exit 1
    fi
    
    log "INFO" "Restoring from backup: $RESTORE_FILE"
    
    # Stop services
    log "INFO" "Stopping services for restore..."
    cd "$PROJECT_DIR"
    docker-compose down -v
    
    # Extract backup
    tar -xzf "$RESTORE_FILE" -C "$PROJECT_DIR"
    
    # Start services
    log "INFO" "Starting services after restore..."
    docker-compose up -d
    
    log "INFO" "Restore completed successfully"
}

# Deploy application
deploy_application() {
    log "INFO" "Deploying Blue Team Swarm to $ENVIRONMENT environment..."
    
    cd "$PROJECT_DIR"
    
    # Set compose files based on environment
    if [[ "$ENVIRONMENT" == "development" ]]; then
        COMPOSE_OVERRIDE="-f docker-compose.override.yml"
        log "INFO" "Using development configuration"
    else
        log "INFO" "Using production configuration"
    fi
    
    # Pull latest images
    log "INFO" "Pulling latest Docker images..."
    docker-compose $COMPOSE_OVERRIDE pull
    
    # Build custom images
    log "INFO" "Building custom Docker images..."
    docker-compose $COMPOSE_OVERRIDE build
    
    # Start services
    log "INFO" "Starting services..."
    docker-compose $COMPOSE_OVERRIDE up -d
    
    # Wait for services to be healthy
    log "INFO" "Waiting for services to be healthy..."
    sleep 30
    
    # Check service health
    local unhealthy_services=$(docker-compose $COMPOSE_OVERRIDE ps --format "table {{.Service}}\t{{.Status}}" | grep -E "(unhealthy|exited)" | wc -l)
    if [[ $unhealthy_services -gt 0 ]]; then
        log "WARN" "Some services may not be healthy. Check 'docker-compose ps' for details."
    else
        log "INFO" "All services are healthy"
    fi
    
    log "INFO" "Deployment completed successfully"
}

# Display service information
display_service_info() {
    log "INFO" "Service Information:"
    echo ""
    echo "Blue Team Swarm is now running!"
    echo ""
    echo "Access URLs:"
    echo "  Web UI:        http://localhost:18080"
    echo "  n8n:           http://localhost:5678"
    echo "  Grafana:       http://localhost:3000"
    echo "  Prometheus:    http://localhost:9090"
    echo "  Qdrant:        http://localhost:6333"
    
    if [[ "$ENVIRONMENT" == "development" ]]; then
        echo "  Redis Commander: http://localhost:8081"
        echo "  File Browser:    http://localhost:8082"
    fi
    
    echo ""
    echo "Default Credentials:"
    echo "  Grafana:       admin / ${GRAFANA_ADMIN_PASSWORD:-admin}"
    echo "  n8n:           ${N8N_BASIC_AUTH_USER:-admin} / ${N8N_BASIC_AUTH_PASSWORD:-password}"
    echo ""
    echo "To check service status: docker-compose ps"
    echo "To view logs:         docker-compose logs -f [service_name]"
    echo "To stop services:     docker-compose down"
    echo ""
}

# Main execution
main() {
    log "INFO" "Starting Blue Team Swarm deployment..."
    
    # Parse arguments
    parse_args "$@"
    
    # Validate environment
    validate_environment
    
    # Set up permissions
    setup_permissions
    
    # Handle restore if requested
    if [[ "$PERFORM_RESTORE" == "true" ]]; then
        restore_backup
        display_service_info
        exit 0
    fi
    
    # Create backup if needed
    create_backup
    
    # Deploy application
    deploy_application
    
    # Display service information
    display_service_info
    
    log "INFO" "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"