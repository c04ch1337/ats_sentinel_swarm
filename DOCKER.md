# Blue Team Swarm Docker Architecture

This document provides detailed information about the Docker implementation of the Blue Team Swarm, including architecture, security considerations, performance tuning, and operational procedures.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Service Details](#service-details)
3. [Network Architecture](#network-architecture)
4. [Data Persistence](#data-persistence)
5. [Security Considerations](#security-considerations)
6. [Performance Tuning](#performance-tuning)
7. [Backup and Restore Procedures](#backup-and-restore-procedures)
8. [Monitoring and Logging](#monitoring-and-logging)
9. [Troubleshooting](#troubleshooting)

## Architecture Overview

The Blue Team Swarm uses a multi-container Docker architecture orchestrated by Docker Compose. The implementation follows microservices principles with clear separation of concerns, enabling scalability, maintainability, and security.

### Design Principles

1. **Service Isolation**: Each component runs in its own container with minimal dependencies
2. **Security by Default**: Internal-only networking where possible, read-only file systems, and minimal privilege
3. **Observability**: Comprehensive health checks, logging, and metrics collection
4. **Portability**: Works across Docker Desktop, Ubuntu, and other Linux distributions
5. **Scalability**: Resource limits and reservations defined for predictable performance

### Container Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend Network                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Orchestrator│  │     n8n     │  │       Grafana       │  │
│  │   (8080)    │  │   (5678)    │  │      (3000)         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────────────────────────────────────┐
│                   Internal Network                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │    Redis    │  │   Qdrant    │  │     Prometheus      │  │
│  │   (6379)    │  │   (6333)    │  │      (9090)         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Service Details

### Orchestrator (blue-swarm-orchestrator)

**Role**: Main application logic and web UI
- **Image**: Custom build from `./orchestrator/Dockerfile`
- **Port**: 8080 (mapped to 18080 on host)
- **Resources**: 512MB limit, 256M reservation, 1.0 CPU limit, 0.5 CPU reservation
- **Health Check**: HTTP GET to `/health` endpoint
- **Volumes**: 
  - Configuration files (read-only)
  - Uploads and logs (read-write)

### n8n (blue-swarm-n8n)

**Role**: Workflow automation and integration
- **Image**: `n8nio/n8n:latest`
- **Port**: 5678
- **Resources**: 512MB limit, 256M reservation, 1.0 CPU limit, 0.5 CPU reservation
- **Health Check**: HTTP GET to `/healthz` endpoint
- **Authentication**: Basic auth configurable via environment variables

### Redis (blue-swarm-redis)

**Role**: Caching and message queue
- **Image**: `redis:7-alpine`
- **Port**: 6379 (internal only)
- **Resources**: 256MB limit, 128M reservation, 0.5 CPU limit, 0.25 CPU reservation
- **Health Check**: Redis PING command
- **Security**: Password protected and internal network only

### Qdrant (blue-swarm-qdrant)

**Role**: Vector database for embeddings
- **Image**: `qdrant/qdrant:latest`
- **Port**: 6333 (internal only)
- **Resources**: 512MB limit, 256M reservation, 1.0 CPU limit, 0.5 CPU reservation
- **Health Check**: HTTP GET to `/health` endpoint
- **Persistence**: Named volume for vector storage

### Prometheus (blue-swarm-prometheus)

**Role**: Metrics collection and storage
- **Image**: `prom/prometheus:latest`
- **Port**: 9090 (mapped to host)
- **Resources**: 512MB limit, 256M reservation, 1.0 CPU limit, 0.5 CPU reservation
- **Health Check**: HTTP GET to `/-/healthy` endpoint
- **Configuration**: Custom prometheus.yml mounted read-only

### Grafana (blue-swarm-grafana)

**Role**: Visualization and dashboards
- **Image**: `grafana/grafana:latest`
- **Port**: 3000 (mapped to host)
- **Resources**: 256MB limit, 128M reservation, 0.5 CPU limit, 0.25 CPU reservation
- **Health Check**: HTTP GET to `/api/health` endpoint
- **Configuration**: Provisioned datasources and dashboards

## Network Architecture

### Network Design

The implementation uses two custom networks for security:

1. **blue-swarm-frontend**: Bridge network with external access
   - Contains services that need external access
   - Exposes necessary ports to the host
   - Still provides container-to-container isolation

2. **blue-swarm-internal**: Internal-only bridge network
   - No external access
   - Used for backend services
   - Provides additional security layer

### Network Security

- Internal services (Redis, Qdrant) are only accessible via the internal network
- Frontend services can communicate with internal services but not vice versa
- Container-to-container communication uses service names as hostnames
- Port exposure is minimized to only what's necessary

## Data Persistence

### Volume Strategy

Named volumes are used for data persistence:

| Volume | Service | Purpose | Backup Critical |
|--------|---------|---------|-----------------|
| uploads_data | Orchestrator | User uploads | Yes |
| logs_data | Orchestrator | Application logs | Optional |
| redis_data | Redis | Cache and session data | Low |
| n8n_data | n8n | Workflows and execution history | Yes |
| qdrant_storage | Qdrant | Vector embeddings | Yes |
| prometheus_data | Prometheus | Metrics history | Optional |
| grafana_data | Grafana | Dashboards and user data | Yes |

### Backup Strategy

Critical data includes:
- User uploads (artifacts and analysis results)
- n8n workflows (automation logic)
- Qdrant embeddings (AI model data)
- Grafana configurations (dashboards and settings)

## Security Considerations

### Container Security

1. **Minimal Base Images**: Using Alpine-based images where possible
2. **Read-only File Systems**: Configuration files mounted as read-only
3. **Non-root Users**: Containers run as non-root users where supported
4. **Resource Limits**: CPU and memory limits prevent resource exhaustion
5. **Health Checks**: Automatic restart on failure

### Network Security

1. **Network Segmentation**: Internal and frontend networks separate concerns
2. **Minimal Port Exposure**: Only necessary ports exposed to host
3. **Service Discovery**: Internal communication via service names
4. **Firewall Rules**: Host-based firewall can restrict access further

### Data Security

1. **Encryption at Rest**: Consider LUKS or similar for sensitive data
2. **Encryption in Transit**: HTTPS/TLS for external communications
3. **Secrets Management**: Environment variables for sensitive data
4. **Access Control**: Authentication on all external services

### Operational Security

1. **Regular Updates**: Keep images updated with security patches
2. **Vulnerability Scanning**: Regular scanning of images
3. **Log Monitoring**: Monitor logs for security events
4. **Backup Verification**: Regular backup and restore testing

## Performance Tuning

### Resource Allocation

Default resource allocations are balanced for typical use cases:

| Service | CPU Limit | CPU Reservation | Memory Limit | Memory Reservation |
|---------|-----------|-----------------|--------------|--------------------|
| Orchestrator | 1.0 | 0.5 | 512M | 256M |
| n8n | 1.0 | 0.5 | 512M | 256M |
| Redis | 0.5 | 0.25 | 256M | 128M |
| Qdrant | 1.0 | 0.5 | 512M | 256M |
| Prometheus | 1.0 | 0.5 | 512M | 256M |
| Grafana | 0.5 | 0.25 | 256M | 128M |

### Scaling Considerations

1. **Vertical Scaling**: Increase resource limits for higher load
2. **Horizontal Scaling**: Some services can be scaled (n8n, orchestrator)
3. **Load Balancing**: Consider HAProxy or similar for horizontal scaling
4. **Resource Monitoring**: Use Prometheus to monitor resource usage

### Optimization Tips

1. **Redis Configuration**: Tune memory settings based on cache requirements
2. **Prometheus Retention**: Adjust retention based on storage capacity
3. **Qdrant Performance**: Monitor vector database performance
4. **Log Rotation**: Implement log rotation to prevent disk space issues

## Backup and Restore Procedures

### Automated Backup

The deployment script includes automated backup functionality:

```bash
# Create backup during deployment
./scripts/deploy.sh -b

# Manual backup
docker compose down
tar -czf backup_$(date +%Y%m%d_%H%M%S).tar.gz \
  .env uploads/ logs/ grafana_data/ prometheus_data/ \
  redis_data/ n8n_data/ qdrant_storage/
docker compose up -d
```

### Restore Procedure

1. **Stop Services**:
   ```bash
   docker compose down -v
   ```

2. **Extract Backup**:
   ```bash
   tar -xzf backup_20231015.tar.gz
   ```

3. **Start Services**:
   ```bash
   docker compose up -d
   ```

4. **Verify Restoration**:
   ```bash
   docker compose ps
   docker compose logs
   ```

### Backup Script

The deployment script includes backup functionality with:
- Automatic backup before deployment (optional)
- Backup retention management (keeps last 7 days)
- Service interruption during backup
- Comprehensive data inclusion

### Disaster Recovery

1. **Documented Recovery**: Keep this document accessible
2. **Backup Verification**: Regular test restores
3. **Off-site Backups**: Consider off-site backup storage
4. **Recovery Time Objective**: Aim for < 30 minutes recovery

## Monitoring and Logging

### Health Checks

All services include health checks:
- **Interval**: 30 seconds
- **Timeout**: 10 seconds
- **Retries**: 3
- **Start Period**: 40 seconds

### Metrics Collection

Prometheus collects metrics from:
- Container resource usage
- Application-specific metrics
- Service health status
- Custom business metrics

### Log Management

1. **Centralized Logging**: All logs accessible via `docker compose logs`
2. **Log Rotation**: Configure log rotation for long-running deployments
3. **Log Levels**: Adjustable via environment variables
4. **Log Analysis**: Use tools like ELK stack for advanced analysis

### Alerting

Grafana can be configured for alerting on:
- Service health failures
- Resource utilization thresholds
- Application-specific metrics
- Security events

## Troubleshooting

### Common Issues

#### Service Startup Failures

1. **Check Logs**: `docker compose logs service_name`
2. **Verify Configuration**: Ensure `.env` is properly configured
3. **Check Resources**: Verify sufficient memory and disk space
4. **Network Issues**: Check network connectivity between containers

#### Performance Issues

1. **Resource Monitoring**: Use `docker stats` to monitor resource usage
2. **Bottleneck Identification**: Check Prometheus metrics
3. **Configuration Tuning**: Adjust resource limits and reservations
4. **Scale Resources**: Increase limits if needed

#### Data Issues

1. **Volume Corruption**: Check volume integrity
2. **Backup Restoration**: Restore from recent backup
3. **Data Consistency**: Verify data consistency across services
4. **Permission Issues**: Check volume permissions

### Debug Tools

1. **Container Access**: `docker compose exec service_name /bin/sh`
2. **Network Debugging**: `docker compose exec service_name ping other_service`
3. **Volume Inspection**: `docker volume inspect volume_name`
4. **Resource Usage**: `docker stats`

### Recovery Procedures

1. **Service Restart**: `docker compose restart service_name`
2. **Full Restart**: `docker compose down && docker compose up -d`
3. **Recreation**: `docker compose down -v && docker compose up -d`
4. **Restore from Backup**: See backup and restore procedures

## Development Workflow

### Development Environment

For development, use the override configuration:
```bash
./scripts/deploy.sh -e development
```

This includes:
- Live code mounting for hot reloading
- Exposed service ports for debugging
- Additional development tools
- Disabled authentication for easier development

### Testing Changes

1. **Local Development**: Use development environment
2. **Integration Testing**: Test with full stack
3. **Production Validation**: Test in production-like environment
4. **Rollback Plan**: Have rollback procedure ready

### CI/CD Integration

The deployment scripts can be integrated into CI/CD pipelines:
- Automated testing
- Automated deployment
- Rollback capabilities
- Environment-specific configurations