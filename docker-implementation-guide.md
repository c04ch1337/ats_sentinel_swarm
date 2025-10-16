
# ATS Sentinel Swarm Docker Configuration Implementation Guide

## Technical Implementation Details

This guide provides specific code examples and configuration files for implementing the Docker improvements outlined in the implementation plan.

## Phase 1: Critical Security Fixes

### 1.1 Enhanced Dockerfile with Multi-Stage Build

Create a new optimized [`orchestrator/Dockerfile`](orchestrator/Dockerfile:1):

```dockerfile
# Build stage
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Production stage
FROM python:3.11-slim as production

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user
RUN groupadd -r swarm && useradd -r -g swarm -u 1001 swarm

# Set up application directory
WORKDIR /app

# Copy Python packages from builder stage
COPY --from=builder /root/.local /home/swarm/.local

# Copy application code
COPY --chown=swarm:swarm . .

# Create necessary directories with proper permissions
RUN mkdir -p /app/uploads && chown -R swarm:swarm /app

# Switch to non-root user
USER swarm

# Set PATH for user-installed packages
ENV PATH=/home/swarm/.local/bin:$PATH
ENV PYTHONPATH=/app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/healthz || exit 1

EXPOSE 8080

# Use gunicorn for production instead of uvicorn directly
CMD ["gunicorn", "app:app", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8080", "--timeout", "120", "--max-requests", "1000", "--max-requests-jitter", "100"]
```

### 1.2 Production-Ready docker-compose.yml

Create an enhanced [`docker-compose.yml`](docker-compose.yml:1):

```yaml
version: "3.9"

# Custom networks for isolation
networks:
  frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
  backend:
    driver: bridge
    internal: true
  monitoring:
    driver: bridge

# Named volumes for persistence
volumes:
  qdrant_storage:
    driver: local
  redis_data:
    driver: local
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
  n8n_data:
    driver: local
  uploads_data:
    driver: local

services:
  orchestrator:
    build: 
      context: ./orchestrator
      target: production
    container_name: blue-swarm-orchestrator
    env_file: .env
    depends_on:
      redis:
        condition: service_healthy
      qdrant:
        condition: service_healthy
    volumes:
      - ./agents:/app/agents:ro
      - ./prompts:/app/prompts:ro
      - ./configs:/app/configs:ro
      - ./orchestrator/static:/app/static:ro
      - uploads_data:/app/uploads
    networks:
      - frontend
      - backend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    ports:
      - "18080:8080"

  n8n:
    image: n8nio/n8n:latest
    container_name: blue-swarm-n8n
    env_file: .env
    environment:
      - N8N_HOST=${N8N_HOST:-localhost}
      - WEBHOOK_URL=${N8N_WEBHOOK_URL:-http://localhost:5678/}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-America/Chicago}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD:-changeme}
    depends_on:
      redis:
        condition: service_healthy
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - frontend
      - backend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    security_opt:
      - no-new-privileges:true
    ports:
      - "5678:5678"

  redis:
    image: redis:7-alpine
    container_name: blue-swarm-redis
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD:-redispassword}
    volumes:
      - redis_data:/data
    networks:
      - backend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 128M
    healthcheck:
      test: ["CMD", "redis-cli", "--no-auth-warning", "-a", "${REDIS_PASSWORD:-redispassword}", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp

  qdrant:
    image: qdrant/qdrant:latest
    container_name: blue-swarm-qdrant
    environment:
      - QDRANT__SERVICE__HTTP_PORT=6333
      - QDRANT__SERVICE__GRPC_PORT=6334
    volumes:
      - qdrant_storage:/qdrant/storage
    networks:
      - backend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    security_opt:
      - no-new-privileges:true
    ports:
      - "6333:6333"

  prometheus:
    image: prom/prometheus:latest
    container_name: blue-swarm-prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-lifecycle'
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - monitoring
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    security_opt:
      - no-new-privileges:true
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: blue-swarm-grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-changeme}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_SECURITY_ALLOW_EMBEDDING=true
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_SECURITY_COOKIE_SECURE=true
      - GF_SECURITY_COOKIE_SAMESITE=strict
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafana_data:/var/lib/grafana
    networks:
      - frontend
      - monitoring
    depends_on:
      prometheus:
        condition: service_healthy
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
        reservations:
          cpus: '0.25'
          memory: 128M
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    security_opt:
      - no-new-privileges:true
    ports:
      - "3000:3000"
```

### 1.3 Enhanced Environment Configuration

Update [`.env.example`](.env.example:1) with additional security and production variables:

```bash
# === .env.example (Blue Team Swarm v1.5) ===

# LLM Provider Configuration
LLM_PROVIDER=OPENAI
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
AZURE_OPENAI_API_KEY=
AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_DEPLOYMENT=
OLLAMA_BASE_URL=http://host.docker.internal:11434

# Service Configuration
N8N_HOST=localhost
N8N_WEBHOOK_URL=http://localhost:5678/
N8N_USER=admin
N8N_PASSWORD=changeme

# Security Configuration
REDIS_PASSWORD=redispassword
GRAFANA_USER=admin
GRAFANA_PASSWORD=changeme

# Service URLs (Internal)
REDIS_URL=redis://:redispassword@blue-swarm-redis:6379/0
QDRANT_URL=http://blue-swarm-qdrant:6333

# External Service Configuration
JIRA_ENABLE_WRITE=false
ZPA_ENABLE_ENFORCE=false

# ZPA Configuration
ZPA_BASE_URL=
ZPA_CLIENT_ID=
ZPA_CLIENT_SECRET=
ZPA_CLOUD=
ZPA_APP_SEGMENTS_PATH=mgmtconfig/v2/admin/applications
ZPA_POLICIES_PATH=mgmtconfig/v2/admin/applications

# Rapid7 IDR Configuration
R7_IDR_BASE=
R7_IDR_API_KEY=
R7_IDR_NOTABLES_PATH=idr/v1/notables

# JIRA Configuration
JIRA_BASE_URL=
JIRA_EMAIL=
JIRA_API_TOKEN=
JIRA_PROJECT_KEY=SEC

# Production Settings
ENVIRONMENT=production
LOG_LEVEL=INFO
MAX_WORKERS=4
```

## Phase 2: Environment-Specific Configurations

### 2.1 Production Override (docker-compose.prod.yml)

```yaml
version: "3.9"
services:
  orchestrator:
    environment:
      - ENVIRONMENT=production
      - LOG_LEVEL=WARNING
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
        reservations:
          cpus: '1.0'
          memory: 512M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  grafana:
    environment:
      - GF_SECURITY_COOKIE_SECURE=true
      - GF_SECURITY_STRICT_TRANSPORT_SECURITY=true
      - GF_SECURITY_X_CONTENT_TYPE_OPTIONS=nosniff
      - GF_SECURITY_X_XSS_PROTECTION=true

  prometheus:
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
```

### 2.2 Development Override (docker-compose.dev.yml)

```yaml
version: "3.9"
services:
  orchestrator:
    build:
      target: base
    environment:
      - ENVIRONMENT=development
      - LOG_LEVEL=DEBUG
    volumes:
      - ./orchestrator:/app
    command: ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080", "--reload"]
    ports:
      - "18080:8080"
      - "5678:5678"  # Debug port

  n8n:
    environment:
      - N8N_BASIC_AUTH_ACTIVE=false
    ports:
      - "5678:5678"

  redis:
    ports:
      - "6379:6379"

  qdrant:
    ports:
      - "6333:6333"
```

### 2.3 Ubuntu Host Override (docker-compose.ubuntu.yml)

```yaml
version: "3.9"
services:
  orchestrator:
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 2G
        reservations:
          cpus: '2.0'
          memory: 1G

  prometheus:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G

  grafana:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
```

## Phase 3: Security and Monitoring Enhancements

### 3.1 Create .dockerignore

Create `.dockerignore` file:

```
.git
.gitignore
README.md
Dockerfile
.dockerignore
.env
.env.*
node_modules
npm-debug.log
coverage
.pytest_cache
.mypy_cache
__pycache__
*.pyc
*.pyo
*.pyd
.Python
.venv
venv
.egg-info
dist
build
*.log
.DS_Store
Thumbs.db
```

### 3.2 Enhanced Prometheus Configuration

Update [`prometheus/prometheus.yml`](prometheus/prometheus.yml:1):

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'blue-swarm-monitor'

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'orchestrator'
    static_configs:
      - targets: ['orchestrator:8080']
    metrics_path: /metrics
    scrape_interval: 15s
    scrape_timeout: 10s

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: /metrics

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']
    metrics_path: /metrics

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
```

### 3.3 Create Alert Rules

Create `prometheus/alert_rules.yml`:

```yaml
groups:
  - name: blue_swarm_alerts
    rules:
      - alert: OrchestratorDown
        expr: up{job="orchestrator"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Orchestrator service is down"
          description: "Orchestrator service has been down for more than 1 minute."

      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Container memory usage is above 80% for more than 5 minutes."

      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "Container CPU usage is above 80% for more than 5 minutes."
```

## Phase 4: Deployment and Operations

### 4.1 Enhanced Bootstrap Script

Update [`scripts/bootstrap.sh`](scripts/bootstrap.sh:1):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
if [ ! -f .env ]; then
    print_error ".env file missing. Please copy .env.example to .env and configure it."
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    print_error "docker-compose is not installed. Please install docker-compose and try again."
    exit 1
fi

# Determine environment
ENVIRONMENT=${1:-development}
print_status "Starting Blue Team Swarm in ${ENVIRONMENT} environment..."

# Validate environment-specific files
case $ENVIRONMENT in
    "production")
        if [ ! -f docker-compose.prod.yml ]; then
            print_error "Production configuration file not found."
            exit 1
        fi
        COMPOSE_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
        ;;
    "ubuntu")
        if [ ! -f docker-compose.ubuntu.yml ]; then
            print_error "Ubuntu configuration file not found."
            exit 1
        fi
        COMPOSE_FILES="-f docker-compose.yml -f docker-compose.ubuntu.yml"
        ;;
    "development"|*)
        COMPOSE_FILES="-f docker-compose.yml"
        if [ -f docker-compose.dev.yml ]; then
            COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.dev.yml"
        fi
        ;;
esac

# Pull latest images
print_status "Pulling latest images..."
docker-compose $COMPOSE_FILES pull

# Build custom images
print_status "Building custom images..."
docker-compose $COMPOSE_FILES build

# Start services
print_status "Starting services..."
docker-compose $COMPOSE_FILES up -d

# Wait for services to be healthy
print_status "Waiting for services to be healthy..."
sleep 30

# Check service health
print_status "Checking service health..."
for service in orchestrator redis qdrant prometheus grafana; do
    if docker-compose $COMPOSE_FILES ps | grep -q "${service}.*Up (healthy)"; then
        print_status "$service is healthy"
    else
        print_warning "$service may not be fully ready yet"
    fi
done

print_status "Blue Team Swarm is now running!"
print_status "Access the following services:"
print_status "  - Web UI: http://localhost:18080"
print_status "  - n8n: http://localhost:5678"
print_status "  - Grafana: http://localhost:3000"
print_status "  - Prometheus: http://localhost:9090"
print_status "  - Qdrant: http://localhost:6333"

if [ "$ENVIRONMENT" = "production" ]; then
    print_warning "Running in production mode. Ensure all security configurations are properly set."
fi
```

### 4.2 Create Backup Script

Create `scripts/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=${1:-"./backups"}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/blue_swarm_backup_$TIMESTAMP"

print_status() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Create backup directory
mkdir -p "$BACKUP_PATH"

print_status "Starting backup of Blue Team Swarm data..."

# Backup volumes
docker run --rm -v blue_swarm_qdrant_storage:/data -v "$BACKUP_PATH":/backup alpine tar czf /backup/qdrant_storage.tar.gz -C /data .
docker run --rm -v blue_swarm_redis_data:/data -v "$BACKUP_PATH":/backup alpine tar czf /backup/redis_data.tar.gz -C /data .
docker run --rm -v blue_swarm_prometheus_data:/prometheus -v "$BACKUP_PATH":/backup alpine tar czf /backup/prometheus_data.tar.gz -C /prometheus .
docker run --rm -v blue_swarm_grafana_data:/var/lib/grafana -v "$BACKUP_PATH":/backup alpine tar czf /backup/grafana_data.tar.gz -C /var/lib/graf
ana .

# Backup configuration files
cp -r ./configs "$BACKUP_PATH/"
cp -r ./prompts "$BACKUP_PATH/"
cp -r ./agents "$BACKUP_PATH/"
cp .env "$BACKUP_PATH/"
cp docker-compose*.yml "$BACKUP_PATH/"

print_status "Backup completed successfully: $BACKUP_PATH"
print_status "Backup size: $(du -sh "$BACKUP_PATH" | cut -f1)"
```

### 4.3 Create Restore Script

Create `scripts/restore.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_path>"
    echo "Example: $0 ./backups/blue_swarm_backup_20231001_120000"
    exit 1
fi

BACKUP_PATH=$1

print_status() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

if [ ! -d "$BACKUP_PATH" ]; then
    print_error "Backup directory not found: $BACKUP_PATH"
    exit 1
fi

print_status "Stopping Blue Team Swarm services..."
docker-compose down

print_status "Restoring volumes from backup..."

# Restore volumes
docker run --rm -v blue_swarm_qdrant_storage:/data -v "$BACKUP_PATH":/backup alpine tar xzf /backup/qdrant_storage.tar.gz -C /data
docker run --rm -v blue_swarm_redis_data:/data -v "$BACKUP_PATH":/backup alpine tar xzf /backup/redis_data.tar.gz -C /data
docker run --rm -v blue_swarm_prometheus_data:/prometheus -v "$BACKUP_PATH":/backup alpine tar xzf /backup/prometheus_data.tar.gz -C /prometheus
docker run --rm -v blue_swarm_grafana_data:/var/lib/grafana -v "$BACKUP_PATH":/backup alpine tar xzf /backup/grafana_data.tar.gz -C /var/lib/grafana

print_status "Starting Blue Team Swarm services..."
docker-compose up -d

print_status "Restore completed successfully!"
```

## Phase 5: Security Hardening

### 5.1 Create Security Scanning Script

Create `scripts/security-scan.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

print_status() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Check if Docker Bench Security is available
if ! command -v docker-bench-security &> /dev/null; then
    print_warning "Docker Bench Security not found. Installing..."
    docker run -it --net host --pid host --userns host --cap-add audit_control \
        -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
        -v /etc:/etc:ro \
        -v /usr/bin/containerd:/usr/bin/containerd:ro \
        -v /usr/bin/runc:/usr/bin/runc:ro \
        -v /usr/lib/systemd:/usr/lib/systemd:ro \
        -v /var/lib:/var/lib:ro \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        --label docker_bench_security \
        docker/docker-bench-security
fi

# Run Docker Bench Security
print_status "Running Docker Bench Security..."
docker-bench-security

# Scan images with Trivy if available
if command -v trivy &> /dev/null; then
    print_status "Scanning Docker images with Trivy..."
    trivy image blue-swarm-orchestrator:latest
    trivy image n8nio/n8n:latest
    trivy image redis:7-alpine
    trivy image qdrant/qdrant:latest
    trivy image prom/prometheus:latest
    trivy image grafana/grafana:latest
else
    print_warning "Trivy not found. Install Trivy for image vulnerability scanning."
fi

print_status "Security scan completed!"
```

### 5.2 Create Security Policy Configuration

Create `docker/security.policy`:

```json
{
  "default": [
    {
      "description": "Run as non-root user",
      "instruction": "USER",
      "pattern": "USER\\s+[^\\s]+",
      "required": true
    },
    {
      "description": "Use specific image tag",
      "instruction": "FROM",
      "pattern": "FROM\\s+[^:]+:[^\\s]+",
      "required": true
    },
    {
      "description": "Add health check",
      "instruction": "HEALTHCHECK",
      "pattern": "HEALTHCHECK",
      "required": true
    }
  ],
  "production": [
    {
      "description": "No root user",
      "instruction": "USER",
      "pattern": "USER\\s+(?!root)",
      "required": true
    },
    {
      "description": "Use specific version tags",
      "instruction": "FROM",
      "pattern": "FROM\\s+[^:]+:[0-9]+\\.[0-9]+",
      "required": true
    }
  ]
}
```

## Phase 6: Performance Optimization

### 6.1 Create Performance Monitoring Dashboard

Create `grafana/dashboards/performance.json`:

```json
{
  "dashboard": {
    "id": null,
    "title": "Blue Swarm Performance",
    "tags": ["blue-swarm", "performance"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Container Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{name=~\"blue-swarm-.*\"}",
            "legendFormat": "{{name}}"
          }
        ],
        "yAxes": [
          {
            "label": "Memory (bytes)",
            "min": 0
          }
        ]
      },
      {
        "id": 2,
        "title": "Container CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{name=~\"blue-swarm-.*\"}[5m])",
            "legendFormat": "{{name}}"
          }
        ],
        "yAxes": [
          {
            "label": "CPU Usage",
            "min": 0,
            "max": 1
          }
        ]
      },
      {
        "id": 3,
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(blue_swarm_requests_total[5m])",
            "legendFormat": "{{method}} {{path}}"
          }
        ]
      },
      {
        "id": 4,
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(blue_swarm_request_latency_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.50, rate(blue_swarm_request_latency_seconds_bucket[5m]))",
            "legendFormat": "50th percentile"
          }
        ]
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "30s"
  }
}
```

### 6.2 Create Resource Optimization Script

Create `scripts/optimize-resources.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

print_status() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

# Get current resource usage
print_status "Analyzing current resource usage..."

docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Get container limits
print_status "Current resource limits:"
docker inspect $(docker-compose ps -q) | jq -r '.[] | "\(.Name): CPU=\(.HostConfig.CpuQuota) Memory=\(.HostConfig.Memory)"'

# Suggest optimizations based on usage
print_status "Resource optimization suggestions:"

# Check for over-provisioned containers
for container in $(docker-compose ps -q); do
    name=$(docker inspect $container | jq -r '.[0].Name')
    cpu_usage=$(docker stats --no-stream --format "{{.CPUPerc}}" $container | sed 's/%//')
    mem_usage=$(docker stats --no-stream --format "{{.MemPerc}}" $container | sed 's/%//')
    
    if (( $(echo "$cpu_usage < 10" | bc -l) )); then
        echo "  - $name: Low CPU usage, consider reducing CPU allocation"
    fi
    
    if (( $(echo "$mem_usage < 20" | bc -l) )); then
        echo "  - $name: Low memory usage, consider reducing memory allocation"
    fi
done
```

## Phase 7: Deployment Automation

### 7.1 Create CI/CD Pipeline Configuration

Create `.github/workflows/docker.yml`:

```yaml
name: Docker Build and Deploy

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: Install dependencies
      run: |
        cd orchestrator
        pip install -r requirements.txt
        pip install pytest pytest-cov
    
    - name: Run tests
      run: |
        cd orchestrator
        pytest --cov=./ --cov-report=xml
    
    - name: Upload coverage
      uses: codecov/codecov-action@v3

  security-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'
    
    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

  build:
    needs: [test, security-scan]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2
    
    - name: Login to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ secrets.REGISTRY_URL }}
        username: ${{ secrets.REGISTRY_USERNAME }}
        password: ${{ secrets.REGISTRY_PASSWORD }}
    
    - name: Build and push orchestrator image
      uses: docker/build-push-action@v4
      with:
        context: ./orchestrator
        push: true
        tags: ${{ secrets.REGISTRY_URL }}/blue-swarm-orchestrator:latest
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Deploy to production
      uses: appleboy/ssh-action@v0.1.5
      with:
        host: ${{ secrets.PROD_HOST }}
        username: ${{ secrets.PROD_USER }}
        key: ${{ secrets.PROD_SSH_KEY }}
        script: |
          cd /opt/blue-swarm
          git pull origin main
          docker-compose -f docker-compose.yml -f docker-compose.prod.yml pull
          docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
          ./scripts/health-check.sh
```

### 7.2 Create Health Check Script

Create `scripts/health-check.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

print_status() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Wait for services to start
sleep 30

# Check service health
services=("orchestrator" "redis" "qdrant" "prometheus" "grafana")
all_healthy=true

for service in "${services[@]}"; do
    if docker-compose ps | grep -q "${service}.*Up (healthy)"; then
        print_status "$service is healthy"
    else
        print_error "$service is not healthy"
        all_healthy=false
    fi
done

# Check HTTP endpoints
endpoints=(
    "http://localhost:18080/healthz"
    "http://localhost:3000/api/health"
    "http://localhost:9090/-/healthy"
)

for endpoint in "${endpoints[@]}"; do
    if curl -f -s "$endpoint" > /dev/null; then
        print_status "$endpoint is responding"
    else
        print_error "$endpoint is not responding"
        all_healthy=false
    fi
done

if [ "$all_healthy" = true ]; then
    print_status "All services are healthy!"
    exit 0
else
    print_error "Some services are not healthy!"
    exit 1
fi
```

## Phase 8: Documentation and Maintenance

### 8.1 Create Maintenance Guide

Create `docs/maintenance.md`:

```markdown
# Blue Team Swarm Maintenance Guide

## Daily Tasks

### 1. Check Service Health
```bash
./scripts/health-check.sh
```

### 2. Review Logs
```bash
docker-compose logs --tail=100
```

### 3. Monitor Resource Usage
```bash
docker stats
```

## Weekly Tasks

### 1. Security Scanning
```bash
./scripts/security-scan.sh
```

### 2. Backup Data
```bash
./scripts/backup.sh
```

### 3. Update Images
```bash
docker-compose pull
docker-compose up -d
```

## Monthly Tasks

### 1. Full System Backup
```bash
./scripts/backup.sh /mnt/backups/monthly
```

### 2. Performance Review
- Review Grafana dashboards
- Check resource utilization trends
- Optimize container resources

### 3. Security Updates
- Update base images
- Apply security patches
- Review vulnerability scan results

## Troubleshooting

### Service Not Starting
1. Check logs: `docker-compose logs <service>`
2. Verify configuration: `docker-compose config`
3. Check resource availability: `docker system df`

### High Memory Usage
1. Identify container: `docker stats`
2. Check memory limits: `docker inspect <container>`
3. Review application logs for memory leaks

### Network Issues
1. Check network configuration: `docker network ls`
2. Verify connectivity: `docker-compose exec <service> ping <other-service>`
3. Review DNS resolution: `docker-compose exec <service> nslookup <service>`

## Emergency Procedures

### Service Recovery
1. Stop affected service: `docker-compose stop <service>`
2. Clear container: `docker-compose rm -f <service>`
3. Restart service: `docker-compose up -d <service>`

### Full System Recovery
1. Stop all services: `docker-compose down`
2. Restore from backup: `./scripts/restore.sh <backup_path>`
3. Start services: `docker-compose up -d`
4. Verify health: `./scripts/health-check.sh`
```

### 8.2 Create Deployment Checklist

Create `docs/deployment-checklist.md`:

```markdown
# Blue Team Swarm Deployment Checklist

## Pre-Deployment

### Environment Preparation
- [ ] Server requirements verified (CPU, RAM, Disk)
- [ ] Docker and Docker Compose installed
- [ ] Network connectivity verified
- [ ] Security policies applied
- [ ] Backup strategy in place

### Configuration
- [ ] .env file configured with production values
- [ ] SSL certificates configured (if required)
- [ ] Firewall rules configured
- [ ] Monitoring endpoints configured
- [ ] Alert notifications configured

## Deployment

### Build and Deploy
- [ ] Code pulled from repository
- [ ] Images built successfully
- [ ] Security scans passed
- [ ] Services started without errors
- [ ] Health checks passing

### Verification
- [ ] All services responding to health checks
- [ ] Web UI accessible and functional
- [ ] API endpoints responding correctly
- [ ] Monitoring data flowing correctly
- [ ] Alerts configured and working

## Post-Deployment

### Monitoring
- [ ] Performance metrics within expected ranges
- [ ] Error rates within acceptable limits
- [ ] Resource utilization normal
- [ ] Backup processes running
- [ ] Security scans scheduled

### Documentation
- [ ] Deployment documented
- [ ] Configuration changes recorded
- [ ] Access credentials secured
- [ ] Support procedures updated
- [ ] Team training completed
```

## Implementation Timeline Summary

### Week 1: Foundation
- Implement multi-stage Dockerfile
- Create production docker-compose.yml
- Add basic health checks
- Implement security basics

### Week 2: Security Hardening
- Add network isolation
- Implement non-root execution
- Add security scanning
- Create backup procedures

### Week 3: Monitoring and Performance
- Enhance monitoring configuration
- Add performance dashboards
- Implement resource limits
- Create optimization procedures

### Week 4: Automation and Documentation
- Create CI/CD pipeline
- Add deployment automation
- Complete documentation
- Final testing and validation

## Success Metrics

### Security
- Zero critical vulnerabilities
- All containers running as non-root
- Network isolation implemented
- Security scans automated

### Reliability
- 99.9% uptime achieved
- All health checks passing
- Automated backups working
- Recovery procedures tested

### Performance
- Response times under 2 seconds
- Resource utilization optimized
- Monitoring comprehensive
- Alerts configured appropriately

This implementation guide provides all the necessary configurations, scripts, and procedures to transform the ATS Sentinel Swarm Docker configuration into a production-ready, secure, and reliable deployment.