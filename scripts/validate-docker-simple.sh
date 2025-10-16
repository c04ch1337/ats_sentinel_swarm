#!/usr/bin/env bash
# Blue Team Swarm Docker Validation Script (Simple Version)
# Comprehensive validation of Docker configuration, security, reliability, and deployment

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

echo "=================================="
echo "BLUE TEAM SWARM DOCKER VALIDATION"
echo "=================================="
echo ""

# Test 1: Check docker-compose.yml exists
echo "Testing docker-compose.yml existence..."
((TOTAL_TESTS++))
if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: docker-compose.yml exists"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: docker-compose.yml not found"
    ((FAILED_TESTS++))
fi

# Test 2: Check Dockerfile exists
echo "Testing Dockerfile existence..."
((TOTAL_TESTS++))
if [[ -f "$PROJECT_DIR/orchestrator/Dockerfile" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: Dockerfile exists"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: Dockerfile not found"
    ((FAILED_TESTS++))
fi

# Test 3: Check .env.example exists
echo "Testing .env.example existence..."
((TOTAL_TESTS++))
if [[ -f "$PROJECT_DIR/.env.example" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: .env.example exists"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: .env.example not found"
    ((FAILED_TESTS++))
fi

# Test 4: Check deployment scripts exist
echo "Testing deployment scripts..."
for script in "deploy.sh" "startup.sh" "wait-for-it.sh"; do
    ((TOTAL_TESTS++))
    if [[ -f "$PROJECT_DIR/scripts/$script" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $script exists"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗ FAIL${NC}: $script not found"
        ((FAILED_TESTS++))
    fi
done

# Test 5: Check health check script
echo "Testing health check script..."
((TOTAL_TESTS++))
if [[ -f "$PROJECT_DIR/orchestrator/healthcheck.sh" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: healthcheck.sh exists"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: healthcheck.sh not found"
    ((FAILED_TESTS++))
fi

# Test 6: Check .dockerignore exists
echo "Testing .dockerignore existence..."
((TOTAL_TESTS++))
if [[ -f "$PROJECT_DIR/.dockerignore" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: .dockerignore exists"
    ((PASSED_TESTS++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: .dockerignore not found"
    ((WARNINGS++))
fi

# Test 7: Check docker-compose.yml for health checks
echo "Testing health check configuration..."
((TOTAL_TESTS++))
if grep -q "healthcheck:" "$PROJECT_DIR/docker-compose.yml"; then
    echo -e "${GREEN}✓ PASS${NC}: Health checks configured"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: No health checks found"
    ((FAILED_TESTS++))
fi

# Test 8: Check docker-compose.yml for restart policies
echo "Testing restart policies..."
((TOTAL_TESTS++))
if grep -q "restart:" "$PROJECT_DIR/docker-compose.yml"; then
    echo -e "${GREEN}✓ PASS${NC}: Restart policies configured"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: No restart policies found"
    ((FAILED_TESTS++))
fi

# Test 9: Check docker-compose.yml for networks
echo "Testing network configuration..."
((TOTAL_TESTS++))
if grep -q "networks:" "$PROJECT_DIR/docker-compose.yml"; then
    echo -e "${GREEN}✓ PASS${NC}: Networks configured"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: No networks found"
    ((FAILED_TESTS++))
fi

# Test 10: Check Dockerfile for non-root user
echo "Testing non-root user configuration..."
((TOTAL_TESTS++))
if grep -q "USER.*orchestrator" "$PROJECT_DIR/orchestrator/Dockerfile"; then
    echo -e "${GREEN}✓ PASS${NC}: Non-root user configured"
    ((PASSED_TESTS++))
else
    echo -e "${RED}✗ FAIL${NC}: Non-root user not configured"
    ((FAILED_TESTS++))
fi

# Test 11: Check Dockerfile for multi-stage build
echo "Testing multi-stage build..."
((TOTAL_TESTS++))
if grep -q "FROM.*as.*builder" "$PROJECT_DIR/orchestrator/Dockerfile"; then
    echo -e "${GREEN}✓ PASS${NC}: Multi-stage build configured"
    ((PASSED_TESTS++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: Multi-stage build not configured"
    ((WARNINGS++))
fi

# Test 12: Check for named volumes
echo "Testing volume configuration..."
((TOTAL_TESTS++))
if grep -q "volumes:" "$PROJECT_DIR/docker-compose.yml"; then
    echo -e "${GREEN}✓ PASS${NC}: Volumes configured"
    ((PASSED_TESTS++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: No volumes found"
    ((WARNINGS++))
fi

# Summary
echo ""
echo "=================================="
echo "VALIDATION SUMMARY"
echo "=================================="
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

if [[ $TOTAL_TESTS -gt 0 ]]; then
    success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "Success Rate: ${success_rate}%"
fi

echo ""
echo "Validation completed!"

# Exit with appropriate code
if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    exit 2
else
    exit 0
fi