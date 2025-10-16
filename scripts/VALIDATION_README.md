# Blue Team Swarm Docker Validation Script

## Overview

The `validate-docker.sh` script provides comprehensive validation of all Docker improvements implemented in the Blue Team Swarm project. It validates configuration files, security settings, reliability features, and deployment scripts.

## Features

### Docker Configuration Validation
- **docker-compose.yml syntax**: Validates YAML syntax and structure
- **Dockerfile best practices**: Checks for multi-stage builds, non-root users, and health checks
- **Environment configuration**: Validates `.env.example` completeness and required variables

### Security Validation
- **Non-root user configuration**: Ensures containers run as non-root users
- **Network isolation**: Validates custom networks and internal network configuration
- **Port exposure**: Reviews exposed ports for security implications

### Reliability Validation
- **Health checks**: Verifies health check configuration and intervals
- **Restart policies**: Validates appropriate restart policies for services
- **Volume mounts**: Checks named volumes and read-only mounts

### Deployment Script Validation
- **deploy.sh**: Validates deployment script functionality, error handling, and backup features
- **startup.sh**: Checks dependency waiting and signal handling
- **wait-for-it.sh**: Validates timeout functionality

### Integration Tests
- **Service startup order**: Validates service dependencies and health status
- **Service connectivity**: Tests connectivity between services
- **Health endpoints**: Validates health endpoint availability

## Usage

### Basic Usage
```bash
# Run all validations
./scripts/validate-docker.sh

# Run with dry-run mode (no Docker required)
./scripts/validate-docker.sh -d

# Skip integration tests
./scripts/validate-docker.sh -s

# Quiet mode (only show errors and summary)
./scripts/validate-docker.sh -q

# Custom report location
./scripts/validate-docker.sh -r /tmp/custom-report.json
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-q, --quiet` | Only show errors and final summary |
| `-r, --report-file FILE` | Custom report file path |
| `-s, --skip-integration` | Skip integration tests (requires running containers) |
| `-d, --dry-run` | Skip Docker-dependent validations (for systems without Docker) |
| `-h, --help` | Show help message |

## Validation Tests

### Configuration Tests
1. **docker-compose.yml exists** - Checks if the main compose file exists
2. **Dockerfile exists** - Validates presence of orchestrator Dockerfile
3. **.env.example exists** - Checks for environment template
4. **deployment scripts** - Validates all deployment scripts exist
5. **health check script** - Checks for health check script
6. **.dockerignore exists** - Validates Docker ignore file

### Configuration Tests
7. **Health checks configured** - Validates health check configuration
8. **Restart policies configured** - Checks restart policy settings
9. **Network configuration** - Validates network setup
10. **Non-root user configuration** - Checks for non-root user
11. **Multi-stage build** - Validates multi-stage Docker build
12. **Volume configuration** - Checks volume setup

## Output

### Console Output
The script provides color-coded output:
- **Green (✓ PASS)**: Successful validations
- **Red (✗ FAIL)**: Failed validations that must be fixed
- **Yellow (⚠ WARN)**: Warnings that should be addressed

### Exit Codes
- `0`: All tests passed
- `1`: One or more tests failed
- `2`: All tests passed but there are warnings

### JSON Report
The script generates a detailed JSON report containing:
- Test timestamp
- Summary statistics (total, passed, failed, warnings)
- Individual test results with messages
- Recommendations for fixing failures

## Example Output

```
==================================
BLUE TEAM SWARM DOCKER VALIDATION
==================================

Testing docker-compose.yml existence...
✓ PASS: docker-compose.yml exists
Testing Dockerfile existence...
✓ PASS: Dockerfile exists
Testing .env.example exists...
✓ PASS: .env.example exists
Testing deployment scripts...
✓ PASS: deploy.sh exists
✓ PASS: startup.sh exists
✓ PASS: wait-for-it.sh exists
Testing health check script...
✓ PASS: healthcheck.sh exists
Testing .dockerignore exists...
✓ PASS: .dockerignore exists
Testing health check configuration...
✓ PASS: Health checks configured
Testing restart policies...
✓ PASS: Restart policies configured
Testing network configuration...
✓ PASS: Networks configured
Testing non-root user configuration...
✓ PASS: Non-root user configured
Testing multi-stage build...
✓ PASS: Multi-stage build configured
Testing volume configuration...
✓ PASS: Volumes configured

==================================
VALIDATION SUMMARY
==================================
Total Tests: 14
Passed: 14
Failed: 0
Warnings: 0
Success Rate: 100%

Validation completed!
```

## Cross-Platform Compatibility

The script is designed to work on both:
- **Docker Desktop** (Windows/macOS)
- **Ubuntu/Linux** hosts

When Docker is not available, the script automatically switches to dry-run mode and performs file-based validations only.

## Integration with CI/CD

The script is ideal for integration into CI/CD pipelines:

```bash
# Example GitHub Actions step
- name: Validate Docker Configuration
  run: ./scripts/validate-docker.sh -d
  
# Example Jenkins pipeline
sh './scripts/validate-docker.sh -q'
```

## Troubleshooting

### Common Issues

1. **Permission denied**: Make the script executable
   ```bash
   chmod +x scripts/validate-docker.sh
   ```

2. **Docker not found**: Use dry-run mode
   ```bash
   ./scripts/validate-docker.sh -d
   ```

3. **Python not available**: YAML syntax validation will be skipped

### Debug Mode

For detailed debugging, you can modify the script to enable debug logging or run individual test functions.

## Extending the Script

To add new validation tests:

1. Create a new function following the naming pattern `validate_*()`
2. Use `record_test()` to record results
3. Add the function call to the main execution section
4. Update documentation

Example:
```bash
validate_new_feature() {
    if [[ condition ]]; then
        record_test "New feature" "PASS" "Feature is properly configured"
    else
        record_test "New feature" "FAIL" "Feature configuration issue"
    fi
}
```

## Dependencies

### Required
- Bash shell
- Basic Unix utilities (grep, cut, etc.)

### Optional
- Docker (for full validation)
- Python (for YAML syntax validation)
- curl (for connectivity tests)

## License

This script is part of the Blue Team Swarm project and follows the same license terms.