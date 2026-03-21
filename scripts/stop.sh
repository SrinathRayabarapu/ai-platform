#!/usr/bin/env bash
# =============================================================================
# AI Platform — Stop all containers (preserves data volumes)
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Stopping AI Platform containers..."
docker compose down
echo "Done. Data volumes are preserved. Run './scripts/bootstrap.sh' to restart."
