# Blue Team Co-Pilot Swarm (v1.5)

Focus: **Zscaler ZPA**, **Rapid7 InsightIDR**, **JIRA ticketing**, plus **Grafana + Prometheus** and a **web UI** for uploads, ZPA diffs, and a unified enrichment comment.
Stack runs on Ubuntu Docker or Docker Desktop.

## Quickstart

### Prerequisites
- Docker and Docker Compose (or Docker Compose V2)
- At least 4GB of RAM available for Docker
- 10GB of free disk space

### Basic Setup

1. **Clone and Configure**
   ```bash
   git clone <repository-url>
   cd ats_sentinel_swarm
   cp .env.example .env
   # Edit .env with your API keys and configuration
   ```

2. **Deploy Using Scripts (Recommended)**
   ```bash
   # Make scripts executable
   chmod +x scripts/*.sh
   
   # Deploy to production
   ./scripts/deploy.sh
   
   # Or deploy to development
   ./scripts/deploy.sh -e development
   ```

3. **Alternative: Simple Docker Compose**
   ```bash
   # For quick testing
   docker compose up -d
   
   # Or with development overrides
   docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
   ```

4. **Access the Services**
   - Web UI → http://localhost:18080
   - n8n → http://localhost:5678
   - Grafana → http://localhost:3000 (admin/admin)
   - Prometheus → http://localhost:9090
   - Qdrant → http://localhost:6333

   Development-only services:
   - Redis Commander → http://localhost:8081
   - File Browser → http://localhost:8082

## Features

- Upload artifacts, auto-analyze IoCs, and create a **single, clean JIRA comment**.
- ZPA **policy diff** preview + **enforcement gate** (env flag + JIRA status allowlist).
- IDR **Notables pull** with JIRA mapping (priority from severity).
- Pluggable LLM provider: `OPENAI | ANTHROPIC | AZURE_OPENAI | OLLAMA` (shim included).
- Comprehensive monitoring with Prometheus and Grafana dashboards.
- Containerized deployment with health checks and automatic restarts.

## Safety

- **Read-first** by default. JIRA writes require `JIRA_ENABLE_WRITE=true`.
- ZPA enforcement requires `ZPA_ENABLE_ENFORCE=true` and approved JIRA status.
- See `policies/SOC_DO_NO_HARM.md`.

## Docker Deployment Instructions

### Environment Configuration

The Docker deployment is configured through environment variables in the `.env` file:

#### Required Variables
- `LLM_PROVIDER`: Choose from `OPENAI`, `ANTHROPIC`, `AZURE_OPENAI`, or `OLLAMA`
- Provider-specific API keys:
  - OpenAI: `OPENAI_API_KEY`
  - Anthropic: `ANTHROPIC_API_KEY`
  - Azure OpenAI: `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`
  - Ollama: `OLLAMA_BASE_URL` (optional, defaults to http://host.docker.internal:11434)

#### External Service Configuration
- **ZPA**: `ZPA_BASE_URL`, `ZPA_CLIENT_ID`, `ZPA_CLIENT_SECRET`, `ZPA_CLOUD`
- **Rapid7 IDR**: `R7_IDR_BASE`, `R7_IDR_API_KEY`
- **JIRA**: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_PROJECT_KEY`

#### Security Configuration
- `REDIS_PASSWORD`: Password for Redis (change from default)
- `N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD`: n8n authentication
- `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD`: Grafana authentication

### Development vs Production Deployment

#### Development Deployment
```bash
./scripts/deploy.sh -e development
```
Development mode includes:
- Live code mounting for hot reloading
- Exposed service ports for direct access
- Debug logging enabled
- Additional development tools (Redis Commander, File Browser)
- Disabled authentication for easier development

#### Production Deployment
```bash
./scripts/deploy.sh
```
Production mode includes:
- Read-only volume mounts for security
- Internal-only networking where possible
- Resource limits and reservations
- Health checks and automatic restarts
- Authentication enabled on all services

### Advanced Deployment Options

#### Backup Before Deployment
```bash
./scripts/deploy.sh -b
```

#### Skip Validation (Not Recommended)
```bash
./scripts/deploy.sh -v
```

#### Restore from Backup
```bash
./scripts/deploy.sh -r backup_20231015.tar.gz
```

### Service Management

#### Check Service Status
```bash
docker compose ps
```

#### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f orchestrator
```

#### Stop Services
```bash
docker compose down
```

#### Update Services
```bash
# Pull latest images and redeploy
./scripts/deploy.sh

# Or manually
docker compose pull
docker compose up -d
```

## Troubleshooting

### Common Issues

#### Services Won't Start
1. Check if all required environment variables are set in `.env`
2. Verify Docker and Docker Compose are installed and running
3. Check available disk space and memory
4. Review logs: `docker compose logs`

#### Permission Errors
1. Ensure scripts are executable: `chmod +x scripts/*.sh`
2. Check if Docker daemon is running: `docker info`
3. For Linux, ensure your user is in the docker group: `sudo usermod -aG docker $USER`

#### Port Conflicts
1. Check if ports are already in use: `netstat -tulpn | grep :18080`
2. Modify port mappings in `docker-compose.yml` if needed

#### Memory Issues
1. Increase Docker memory allocation (Docker Desktop)
2. Check resource limits in `docker-compose.yml`
3. Monitor resource usage: `docker stats`

#### Service Health Issues
1. Check service health: `docker compose ps`
2. View health check logs: `docker inspect container_name`
3. Restart unhealthy service: `docker compose restart service_name`

#### LLM Provider Issues
1. Verify API keys are correct and have sufficient permissions
2. Check network connectivity to LLM provider
3. Review orchestrator logs: `docker compose logs orchestrator`

### Debug Mode

For detailed debugging:
1. Deploy with development mode: `./scripts/deploy.sh -e development`
2. Enable debug logging in `.env`: `DEBUG=true`, `LOG_LEVEL=DEBUG`
3. Access additional debugging tools at ports 8081 and 8082

### Getting Help

1. Check the logs for error messages
2. Review the [DOCKER.md](DOCKER.md) for detailed architecture information
3. Verify all prerequisites are met
4. Check the GitHub issues for known problems

## Architecture

The Blue Team Swarm consists of the following services:
- **Orchestrator**: Main application logic and web UI
- **n8n**: Workflow automation and integration
- **Redis**: Caching and message queue
- **Qdrant**: Vector database for embeddings
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards

For detailed architecture information, see [DOCKER.md](DOCKER.md).

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with the development deployment
5. Submit a pull request

## License

See LICENSE file for details.
