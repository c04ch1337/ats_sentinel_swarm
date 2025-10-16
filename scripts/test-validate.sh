#!/usr/bin/env bash
set -euo pipefail

echo "Starting test validation..."

# Test basic functionality
echo "Testing docker-compose.yml existence..."
if [[ -f "docker-compose.yml" ]]; then
    echo "✓ docker-compose.yml exists"
else
    echo "✗ docker-compose.yml not found"
    exit 1
fi

# Test YAML validation
echo "Testing YAML syntax..."
python -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" 2>&1
if python -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" 2>/dev/null; then
    echo "✓ YAML syntax is valid"
else
    echo "✗ YAML syntax is invalid"
    exit 1
fi

# Test Dockerfile
echo "Testing Dockerfile..."
if [[ -f "orchestrator/Dockerfile" ]]; then
    echo "✓ Dockerfile exists"
else
    echo "✗ Dockerfile not found"
    exit 1
fi

echo "All tests passed!"