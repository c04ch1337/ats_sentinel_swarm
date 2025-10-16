#!/usr/bin/env bash
set -euo pipefail
[ -f .env ] || { echo '.env missing'; exit 1; }
docker compose up -d
