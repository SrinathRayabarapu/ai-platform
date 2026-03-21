#!/usr/bin/env bash
# =============================================================================
# AI Platform — Full reset (removes containers, volumes, and data)
# WARNING: This deletes ALL persistent data (PostgreSQL, Kafka, Redis, etc.)
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}WARNING: This will destroy ALL data (PostgreSQL, Kafka, Redis, Grafana, etc.)${NC}"
echo ""
read -p "Are you sure? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Stopping containers and removing volumes..."
docker compose down -v

echo "Removing data directories..."
rm -rf "$PROJECT_DIR/data"

echo ""
echo -e "${YELLOW}Reset complete.${NC} Run './scripts/bootstrap.sh' to start fresh."
