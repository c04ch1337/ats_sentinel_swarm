# Blue Team Co-Pilot Swarm (v1.5)

Focus: **Zscaler ZPA**, **Rapid7 InsightIDR**, **JIRA ticketing**, plus **Grafana + Prometheus** and a **web UI** for uploads, ZPA diffs, and a unified enrichment comment.
Stack runs on Ubuntu Docker or Docker Desktop.

## Quickstart
1) `cp .env.example .env` and populate keys.
2) `docker compose up -d` or `./scripts/bootstrap.sh`.
3) Open:
   - Web UI → http://localhost:18080
   - n8n → http://localhost:5678
   - Grafana → http://localhost:3000 (admin/admin)
   - Prometheus → http://localhost:9090
   - Qdrant → http://localhost:6333

## Features
- Upload artifacts, auto-analyze IoCs, and create a **single, clean JIRA comment**.
- ZPA **policy diff** preview + **enforcement gate** (env flag + JIRA status allowlist).
- IDR **Notables pull** with JIRA mapping (priority from severity).
- Pluggable LLM provider: `OPENAI | ANTHROPIC | AZURE_OPENAI | OLLAMA` (shim included).

## Safety
- **Read-first** by default. JIRA writes require `JIRA_ENABLE_WRITE=true`.
- ZPA enforcement requires `ZPA_ENABLE_ENFORCE=true` and approved JIRA status.
- See `policies/SOC_DO_NO_HARM.md`.
