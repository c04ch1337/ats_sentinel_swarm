# Multi-stage build for ATS Sentinel Swarm Orchestrator
# Stage 1: Build stage with dependencies
FROM python:3.11-slim as builder

# Set environment variables for build
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# Stage 2: Runtime stage with security hardening
FROM python:3.11-slim as runtime

# Set environment variables for runtime
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user with proper home directory
RUN groupadd -r orchestrator && \
    useradd -r -g orchestrator -d /app -s /bin/bash orchestrator

# Copy virtual environment from builder stage
COPY --from=builder /opt/venv /opt/venv

# Create application directory with proper permissions
RUN mkdir -p /app/uploads /app/logs && \
    chown -R orchestrator:orchestrator /app

# Set working directory
WORKDIR /app

# Copy application code
COPY --chown=orchestrator:orchestrator . .

# Make healthcheck script executable
RUN chmod +x /app/healthcheck.sh

# Switch to non-root user
USER orchestrator

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD /app/healthcheck.sh

# Start the application
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
