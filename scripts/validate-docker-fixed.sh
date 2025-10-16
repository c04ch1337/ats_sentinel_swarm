#!/usr/bin/env bash
# Blue Team Swarm Docker Validation Script
# Comprehensive validation of Docker configuration, security, reliability, and deployment

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VALIDATION_REPORT="$PROJECT_DIR/validation-report-$(date +%Y%m%d_%H%M%S).json"

# Create temp directory (cross-platform)
if command -v mktemp &> /dev/null; then
    TEMP_DIR=$(mktemp -d)
else
    TEMP_DIR="$PROJECT_DIR/temp-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$TEMP_DIR"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation results
declare -A VALIDATION_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ((WARNINGS++))
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
}

# Test result recording
record_test() {
    local test_name=$1
    local result=$2
    local message=${3:-""}
    
    ((TOTAL_TESTS++))
    
    if [[ "$result" == "PASS" ]]; then
        ((PASSED_TESTS++))
        log "INFO" "✓ PASS: $test_name"
        VALIDATION_RESULTS["$test_name"]="PASS:$message"
    elif [[ "$result" == "FAIL" ]]; then
        ((FAILED_TESTS++))
        log "ERROR" "✗ FAIL: $test_name - $message"
        VALIDATION_RESULTS["$test_name"]="FAIL:$message"
    elif [[ "$result" == "WARN" ]]; then
        log "WARN" "⚠ WARN: $test_name - $message"
        VALIDATION_RESULTS["$test_name"]="WARN:$message"
    elif [[ "$result" == "SKIP" ]]; then
        log "INFO" "- SKIP: $test_name - $message"
        VALIDATION_RESULTS["$test_name"]="SKIP:$message"
    fi
}

# Display usage information
usage() {
    cat << EOF
Blue Team Swarm Docker Validation Script

Usage: $0 [OPTIONS]

OPTIONS:
    -q, --quiet              Only show errors and final summary
    -r, --report-file FILE   Custom report file path
    -s, --skip-integration   Skip integration tests (requires running containers)
    -d, --dry-run            Skip Docker-dependent validations (for systems without Docker)
    -h, --help               Show this help message

EXAMPLES:
    $0                       # Run all validations
    $0 -s                    # Run validations without integration tests
    $0 -d                    # Run dry-run validation (no Docker required)
    $0 -r /tmp/report.json   # Save report to custom location

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    QUIET=false
    SKIP_INTEGRATION=false
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -r|--report-file)
                VALIDATION_REPORT="$2"
                shift 2
                ;;
            -s|--skip-integration)
                SKIP_INTEGRATION=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                SKIP_INTEGRATION=true
                shift
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

# =============================================================================
# DOCKER CONFIGURATION VALIDATION
# =============================================================================

validate_docker_compose_syntax() {
    log "INFO" "Validating docker-compose.yml syntax..."
    
    cd "$PROJECT_DIR"
    
    # Check if docker-compose.yml exists
    if [[ ! -f "docker-compose.yml" ]]; then
        record_test "docker-compose.yml exists" "FAIL" "docker-compose.yml file not found"
        return 1
    fi
    record_test "docker-compose.yml exists" "PASS"
    
    # Check if Docker is available
    if [[ "$DRY_RUN" == "true" ]] || ! command -v docker &> /dev/null; then
        record_test "docker-compose.yml syntax" "SKIP" "Docker not available (use -d for dry-run)"
        
        # Basic YAML syntax check using python if available
        local python_cmd=""
        if command -v python3 &> /dev/null; then
            python_cmd="python3"
        elif command -v python &> /dev/null; then
            python_cmd="python"
        fi
        
        if [[ -n "$python_cmd" ]]; then
            if $python_cmd -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" 2>/dev/null; then
                record_test "docker-compose.yml YAML syntax" "PASS"
            else
                record_test "docker-compose.yml YAML syntax" "FAIL" "Invalid YAML syntax"
            fi
        else
            record_test "docker-compose.yml YAML syntax" "SKIP" "Python not available for YAML validation"
        fi
        return 0
    fi
    
    # Validate syntax
    if docker-compose -f docker-compose.yml config > /dev/null 2>&1; then
        record_test "docker-compose.yml syntax" "PASS"
    else
        record_test "docker-compose.yml syntax" "FAIL" "Invalid YAML syntax"
        return 1
    fi
    
    # Check override file if it exists
    if [[ -f "docker-compose.override.yml" ]]; then
        if docker-compose -f docker-compose.yml -f docker-compose.override.yml config > /dev/null 2>&1; then
            record_test "docker-compose.override.yml syntax" "PASS"
        else
            record_test "docker-compose.override.yml syntax" "FAIL" "Invalid YAML syntax"
        fi
    fi
}

validate_dockerfile_best_practices() {
    log "INFO" "Validating Dockerfile best practices..."
    
    local dockerfile="$PROJECT_DIR/orchestrator/Dockerfile"
    
    if [[ ! -f "$dockerfile" ]]; then
        record_test "Dockerfile exists" "FAIL" "Dockerfile not found in orchestrator directory"
        return 1
    fi
    record_test "Dockerfile exists" "PASS"
    
    # Check for multi-stage build
    if grep -q "FROM.*as.*builder" "$dockerfile"; then
        record_test "Multi-stage build" "PASS"
    else
        record_test "Multi-stage build" "WARN" "Consider using multi-stage builds for smaller images"
    fi
    
    # Check for non-root user
    if grep -q "USER.*orchestrator" "$dockerfile"; then
        record_test "Non-root user" "PASS"
    else
        record_test "Non-root user" "FAIL" "Container should run as non-root user"
    fi
    
    # Check for health check
    if grep -q "HEALTHCHECK" "$dockerfile"; then
        record_test "Dockerfile health check" "PASS"
    else
        record_test "Dockerfile health check" "WARN" "Consider adding HEALTHCHECK instruction"
    fi
    
    # Check for specific version tags
    if grep -q "FROM.*:latest" "$dockerfile"; then
        record_test "Specific version tags" "WARN" "Avoid using 'latest' tag in production"
    else
        record_test "Specific version tags" "PASS"
    fi
    
    # Check for .dockerignore
    if [[ -f "$PROJECT_DIR/.dockerignore" ]]; then
        record_test ".dockerignore exists" "PASS"
    else
        record_test ".dockerignore exists" "WARN" "Consider adding .dockerignore file"
    fi
}

validate_env_completeness() {
    log "INFO" "Validating .env.example completeness..."
    
    local env_example="$PROJECT_DIR/.env.example"
    local env_file="$PROJECT_DIR/.env"
    
    if [[ ! -f "$env_example" ]]; then
        record_test ".env.example exists" "FAIL" ".env.example file not found"
        return 1
    fi
    record_test ".env.example exists" "PASS"
    
    # Check if .env exists
    if [[ ! -f "$env_file" ]]; then
        record_test ".env exists" "WARN" ".env file not found (copy from .env.example)"
    else
        record_test ".env exists" "PASS"
        
        # Check for required variables
        local required_vars=("LLM_PROVIDER")
        for var in "${required_vars[@]}"; do
            if grep -q "^$var=" "$env_file"; then
                record_test "Required variable $var" "PASS"
            else
                record_test "Required variable $var" "FAIL" "Required environment variable not set"
            fi
        done
    fi
    
    # Check for documentation
    local comment_lines=$(grep -c "^#" "$env_example" || true)
    if [[ $comment_lines -gt 10 ]]; then
        record_test ".env.example documentation" "PASS"
    else
        record_test ".env.example documentation" "WARN" "Add more documentation to .env.example"
    fi
}

# =============================================================================
# SECURITY VALIDATION
# =============================================================================

validate_non_root_user() {
    log "INFO" "Validating non-root user configuration..."
    
    local dockerfile="$PROJECT_DIR/orchestrator/Dockerfile"
    
    # Check Dockerfile for non-root user
    if grep -q "USER.*orchestrator" "$dockerfile"; then
        record_test "Dockerfile non-root user" "PASS"
    else
        record_test "Dockerfile non-root user" "FAIL" "Container should run as non-root user"
    fi
    
    # Check docker-compose for user specification
    if grep -q "user:" "$PROJECT_DIR/docker-compose.yml"; then
        record_test "docker-compose user specification" "PASS"
    else
        record_test "docker-compose user specification" "WARN" "Consider specifying user in docker-compose"
    fi
}

validate_network_isolation() {
    log "INFO" "Validating network isolation..."
    
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    
    # Check for custom networks
    if grep -q "networks:" "$compose_file"; then
        record_test "Custom networks defined" "PASS"
    else
        record_test "Custom networks defined" "FAIL" "Custom networks should be defined"
    fi
    
    # Check for internal network
    if grep -q "internal: true" "$compose_file"; then
        record_test "Internal network" "PASS"
    else
        record_test "Internal network" "WARN" "Consider using internal networks for sensitive services"
    fi
    
    # Check if services are attached to appropriate networks
    if grep -q "blue-swarm-internal" "$compose_file"; then
        record_test "Services attached to internal network" "PASS"
    else
        record_test "Services attached to internal network" "FAIL" "Services should use internal networks"
    fi
}

validate_exposed_ports() {
    log "INFO" "Validating exposed ports..."
    
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    
    # Check for unnecessary port exposures
    local exposed_ports=$(grep -c "ports:" "$compose_file" || true)
    if [[ $exposed_ports -gt 0 ]]; then
        record_test "Port exposure review" "WARN" "Review exposed ports for necessity"
    else
        record_test "Port exposure review" "PASS"
    fi
    
    # Check if sensitive services are only exposed internally
    if grep -A 10 -B 2 "redis:" "$compose_file" | grep -q "ports:"; then
        record_test "Redis port exposure" "WARN" "Redis should not be exposed externally"
    else
        record_test "Redis port exposure" "PASS"
    fi
}

# =============================================================================
# RELIABILITY VALIDATION
# =============================================================================

validate_health_checks() {
    log "INFO" "Validating health check configuration..."
    
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    
    # Check if services have health checks
    local services_with_health=$(grep -c "healthcheck:" "$compose_file" || true)
    local total_services=$(grep -c "^[[:space:]]*[a-z][a-z0-9_-]*:" "$compose_file" || true)
    
    if [[ $services_with_health -gt 0 ]]; then
        record_test "Health checks configured" "PASS" "$services_with_health/$total_services services have health checks"
    else
        record_test "Health checks configured" "FAIL" "No health checks found"
    fi
    
    # Check health check intervals
    if grep -q "interval:.*30s" "$compose_file"; then
        record_test "Health check intervals" "PASS"
    else
        record_test "Health check intervals" "WARN" "Review health check intervals"
    fi
    
    # Check health check script
    if [[ -f "$PROJECT_DIR/orchestrator/healthcheck.sh" ]]; then
        record_test "Health check script exists" "PASS"
        
        # Check if script is executable
        if [[ -x "$PROJECT_DIR/orchestrator/healthcheck.sh" ]]; then
            record_test "Health check script executable" "PASS"
        else
            record_test "Health check script executable" "FAIL" "Health check script should be executable"
        fi
    else
        record_test "Health check script exists" "FAIL" "Health check script not found"
    fi
}

validate_restart_policies() {
    log "INFO" "Validating restart policies..."
    
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    
    # Check if services have restart policies
    if grep -q "restart:" "$compose_file"; then
        record_test "Restart policies configured" "PASS"
    else
        record_test "Restart policies configured" "FAIL" "Services should have restart policies"
    fi
    
    # Check for appropriate restart policy
    if grep -q "restart:.*unless-stopped" "$compose_file"; then
        record_test "Appropriate restart policy" "PASS"
    else
        record_test "Appropriate restart policy" "WARN" "Consider using 'unless-stopped' restart policy"
    fi
}

validate_volume_mounts() {
    log "INFO" "Validating volume mounts..."
    
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    
    # Check for named volumes
    if grep -q "volumes:" "$compose_file" && grep -q "driver: local" "$compose_file"; then
        record_test "Named volumes configured" "PASS"
    else
        record_test "Named volumes configured" "WARN" "Consider using named volumes for persistence"
    fi
    
    # Check for read-only mounts where appropriate
    if grep -q ":ro" "$compose_file"; then
        record_test "Read-only mounts" "PASS"
    else
        record_test "Read-only mounts" "WARN" "Consider using read-only mounts for static data"
    fi
    
    # Check for backup strategy
    if grep -q "backup" "$compose_file" || grep -q "BACKUP" "$PROJECT_DIR/.env.example"; then
        record_test "Backup strategy" "PASS"
    else
        record_test "Backup strategy" "WARN" "Consider implementing backup strategy"
    fi
}

# =============================================================================
# DEPLOYMENT SCRIPT VALIDATION
# =============================================================================

validate_deploy_script() {
    log "INFO" "Validating deploy.sh script..."
    
    local deploy_script="$PROJECT_DIR/scripts/deploy.sh"
    
    if [[ ! -f "$deploy_script" ]]; then
        record_test "deploy.sh exists" "FAIL" "deploy.sh script not found"
        return 1
    fi
    record_test "deploy.sh exists" "PASS"
    
    # Check if script is executable
    if [[ -x "$deploy_script" ]]; then
        record_test "deploy.sh executable" "PASS"
    else
        record_test "deploy.sh executable" "FAIL" "deploy.sh should be executable"
    fi
    
    # Check for error handling
    if grep -q "set -euo pipefail" "$deploy_script"; then
        record_test "deploy.sh error handling" "PASS"
    else
        record_test "deploy.sh error handling" "WARN" "Script should use proper error handling"
    fi
    
    # Check for backup functionality
    if grep -q "backup" "$deploy_script"; then
        record_test "deploy.sh backup functionality" "PASS"
    else
        record_test "deploy.sh backup functionality" "WARN" "Consider adding backup functionality"
    fi
    
    # Check for environment validation
    if grep -q "validate" "$deploy_script"; then
        record_test "deploy.sh environment validation" "PASS"
    else
        record_test "deploy.sh environment validation" "WARN" "Consider adding environment validation"
    fi
}

validate_startup_script() {
    log "INFO" "Validating startup.sh script..."
    
    local startup_script="$PROJECT_DIR/scripts/startup.sh"
    
    if [[ ! -f "$startup_script" ]]; then
        record_test "startup.sh exists" "FAIL" "startup.sh script not found"
        return 1
    fi
    record_test "startup.sh exists" "PASS"
    
    # Check if script is executable
    if [[ -x "$startup_script" ]]; then
        record_test "startup.sh executable" "PASS"
    else
        record_test "startup.sh executable" "FAIL" "startup.sh should be executable"
    fi
    
    # Check for dependency waiting
    if grep -q "wait-for-it" "$startup_script"; then
        record_test "startup.sh dependency waiting" "PASS"
    else
        record_test "startup.sh dependency waiting" "WARN" "Consider adding dependency waiting"
    fi
    
    # Check for signal handling
    if grep -q "trap" "$startup_script"; then
        record_test "startup.sh signal handling" "PASS"
    else
        record_test "startup.sh signal handling" "WARN" "Consider adding signal handling"
    fi
}

validate_wait_for_it_script() {
    log "INFO" "Validating wait-for-it.sh script..."
    
    local wait_script="$PROJECT_DIR/scripts/wait-for-it.sh"
    
    if [[ ! -f "$wait_script" ]]; then
        record_test "wait-for-it.sh exists" "FAIL" "wait-for-it.sh script not found"
        return 1
    fi
    record_test "wait-for-it.sh exists" "PASS"
    
    # Check if script is executable
    if [[ -x "$wait_script" ]]; then
        record_test "wait-for-it.sh executable" "PASS"
    else
        record_test "wait-for-it.sh executable" "FAIL" "wait-for-it.sh should be executable"
    fi
    
    # Check for timeout functionality
    if grep -q "timeout" "$wait_script"; then
        record_test "wait-for-it.sh timeout" "PASS"
    else
        record_test "wait-for-it.sh timeout" "WARN" "Script should support timeout"
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

validate_service_startup_order() {
    if [[ "$SKIP_INTEGRATION" == "true" ]]; then
        record_test "Service startup order" "SKIP" "Integration tests skipped"
        return 0
    fi
    
    # Check if Docker is available
    if [[ "$DRY_RUN" == "true" ]] || ! command -v docker &> /dev/null; then
        record_test "Service startup order" "SKIP" "Docker not available (use -d for dry-run)"
        return 0
    fi
    
    log "INFO" "Validating service startup order..."
    
    cd "$PROJECT_DIR"
    
    # Check if containers are running
    local running_containers=$(docker-compose ps -q | wc -l)
    if [[ $running_containers -eq 0 ]]; then
        record_test "Service startup order" "WARN" "No containers running - start services to test"
        return 0
    fi
    
    # Check dependency order
    if docker-compose ps | grep -q "Up (healthy)"; then
        record_test "Service startup order" "PASS" "Services are healthy"
    else
        record_test "Service startup order" "WARN" "Some services may not be healthy"
    fi
}

validate_service_connectivity() {
    if [[ "$SKIP_INTEGRATION" == "true" ]]; then
        record_test "Service connectivity" "SKIP" "Integration tests skipped"
        return 0
    fi
    
    # Check if Docker is available
    if [[ "$DRY_RUN" == "true" ]] || ! command -v docker &> /dev/null; then
        record_test "Service connectivity" "SKIP" "Docker not available (use -d for dry-run)"
        return 0
    fi
    
    log "INFO" "Validating service connectivity..."
    
    cd "$PROJECT_DIR"
    
    # Test Redis connectivity
    if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
        record_test "Redis connectivity" "PASS"
    else
        record_test "Redis connectivity" "FAIL" "Cannot connect to Redis"
    fi
    
    # Test Qdrant connectivity
    if curl -f -s http://localhost:6333/health > /dev/null 2>&1; then
        record_test "Qdrant connectivity" "PASS"
    else
        record_test "Qdrant connectivity" "WARN" "Cannot connect to Qdrant"
    fi
    
    # Test Prometheus connectivity
    if curl -f -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
        record_test "Prometheus connectivity" "PASS"
    else
        record_test "Prometheus connectivity" "WARN" "Cannot connect to Prometheus"
    fi
}

validate_health_endpoints() {
    if [[ "$SKIP_INTEGRATION" == "true" ]]; then
        record_test "Health endpoints" "SKIP" "Integration tests skipped"
        return 0
    fi
    
    # Check if Docker is available
    if [[ "$DRY_RUN" == "true" ]] || ! command -v docker &> /dev/null; then
        record_test "Health endpoints" "SKIP" "Docker not available (use -d for dry-run)"
        return 0
    fi
    
    log "INFO" "Validating health endpoints..."
    
    # Test orchestrator health endpoint
    if curl -f -s http://localhost:18080/health > /dev/null 2>&1; then
        record_test "Orchestrator health endpoint" "PASS"
    else
        record_test "Orchestrator health endpoint" "WARN" "Orchestrator health endpoint not responding"
    fi
    
    # Test Grafana health endpoint
    if curl -f -s http://localhost:3000/api/health > /dev/null 2>&1; then
        record_test "Grafana health endpoint" "PASS"
    else
        record_test "Grafana health endpoint" "WARN" "Grafana health endpoint not responding"
    fi
    
    # Test n8n health endpoint
    if curl -f -s http://localhost:5678/healthz > /dev/null 2>&1; then
        record_test "n8n health endpoint" "PASS"
    else
        record_test "n8n health endpoint" "WARN" "n8n health endpoint not responding"
    fi
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

generate_validation_report() {
    log "INFO" "Generating validation report..."
    
    local report_file="$VALIDATION_REPORT"
    
    # Create JSON report
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "warnings": $WARNINGS,
    "success_rate": 0
  },
  "results": [
EOF
    
    # Add test results
    local first=true
    for test_name in "${!VALIDATION_RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        
        local result="${VALIDATION_RESULTS[$test_name]}"
        local status=$(echo "$result" | cut -d: -f1)
        local message=$(echo "$result" | cut -d: -f2-)
        
        cat >> "$report_file" << EOF
    {
      "test": "$test_name",
      "status": "$status",
      "message": "$message"
    }
EOF
    done
    
    cat >> "$report_file" << EOF
  ],
  "recommendations": [
EOF
    
    # Add recommendations based on failures
    local first=true
    for test_name in "${!VALIDATION_RESULTS[@]}"; do
        local result="${VALIDATION_RESULTS[$test_name]}"
        local status=$(echo "$result" | cut -d: -f1)
        
        if [[ "$status" == "FAIL" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo "," >> "$report_file"
            fi
            
            cat >> "$report_file" << EOF
    "Fix: $test_name"
EOF
        fi
    done
    
    cat >> "$report_file" << EOF
  ]
}
EOF
    
    log "INFO" "Validation report saved to: $report_file"
}

display_summary() {
    echo ""
    echo "=================================="
    echo "VALIDATION SUMMARY"
    echo "=================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local success_rate=0
        if [[ $PASSED_TESTS -gt 0 ]]; then
            success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        fi
        echo "Success Rate: ${success_rate}%"
    fi
    
    echo ""
    echo "Report saved to: $VALIDATION_REPORT"
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo ""
        echo -e "${RED}FAILED TESTS:${NC}"
        for test_name in "${!VALIDATION_RESULTS[@]}"; do
            local result="${VALIDATION_RESULTS[$test_name]}"
            local status=$(echo "$result" | cut -d: -f1)
            if [[ "$status" == "FAIL" ]]; then
                local message=$(echo "$result" | cut -d: -f2-)
                echo -e "  ${RED}✗${NC} $test_name: $message"
            fi
        done
    fi
    
    if [[ $WARNINGS -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}WARNINGS:${NC}"
        for test_name in "${!VALIDATION_RESULTS[@]}"; do
            local result="${VALIDATION_RESULTS[$test_name]}"
            local status=$(echo "$result" | cut -d: -f1)
            if [[ "$status" == "WARN" ]]; then
                local message=$(echo "$result" | cut -d: -f2-)
                echo -e "  ${YELLOW}⚠${NC} $test_name: $message"
            fi
        done
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "=================================="
    echo "BLUE TEAM SWARM DOCKER VALIDATION"
    echo "=================================="
    echo ""
    
    # Parse arguments
    parse_args "$@"
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Run validations
    validate_docker_compose_syntax
    validate_dockerfile_best_practices
    validate_env_completeness
    
    validate_non_root_user
    validate_network_isolation
    validate_exposed_ports
    
    validate_health_checks
    validate_restart_policies
    validate_volume_mounts
    
    validate_deploy_script
    validate_startup_script
    validate_wait_for_it_script
    
    validate_service_startup_order
    validate_service_connectivity
    validate_health_endpoints
    
    # Generate report
    generate_validation_report
    
    # Display summary
    display_summary
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function with all arguments
main "$@"