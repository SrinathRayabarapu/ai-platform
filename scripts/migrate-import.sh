#!/usr/bin/env bash
# =============================================================================
# AI Platform — Import data from a migration backup
#
# Usage: ./scripts/migrate-import.sh <backup-directory>
#
# Prerequisites:
#   1. Run ./scripts/bootstrap.sh first (creates containers + data dirs)
#   2. Containers must be running
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup-directory>"
    echo "  e.g. $0 backups/export_20260320_143000"
    exit 1
fi

BACKUP_DIR="$1"
if [ ! -d "$BACKUP_DIR" ]; then
    echo "ERROR: Backup directory not found: $BACKUP_DIR"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

echo "============================================="
echo "  AI Platform — Import (Migration Restore)"
echo "  Source: $BACKUP_DIR"
echo "============================================="

# --- PostgreSQL ---
echo ""
echo "=== PostgreSQL ==="
if [ -f "$BACKUP_DIR/postgres_full.sql" ]; then
    CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-postgres"
    docker exec -i "$CONTAINER" psql -U "${POSTGRES_USER:-ai_user}" -d "${POSTGRES_DB:-ai_lab}" < "$BACKUP_DIR/postgres_full.sql" >/dev/null 2>&1 \
        && ok "Imported: postgres_full.sql" \
        || warn "PostgreSQL import had warnings (check manually)"
else
    warn "No postgres_full.sql found — skipping"
fi

# --- Redis ---
echo ""
echo "=== Redis ==="
if [ -f "$BACKUP_DIR/redis_dump.rdb" ]; then
    REDIS_CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-redis"
    # Stop Redis, replace RDB, restart
    docker compose stop redis
    docker cp "$BACKUP_DIR/redis_dump.rdb" "$REDIS_CONTAINER":/data/dump.rdb 2>/dev/null \
        && ok "Copied redis_dump.rdb into container" \
        || warn "Could not copy RDB — try manually"
    docker compose start redis
    ok "Redis restarted with imported data"
else
    warn "No redis_dump.rdb found — skipping"
fi

# --- Grafana dashboards ---
echo ""
echo "=== Grafana Dashboards ==="
if [ -d "$BACKUP_DIR/grafana_dashboards" ]; then
    GRAFANA_URL="http://localhost:${GRAFANA_PORT:-3000}"
    GRAFANA_CREDS="admin:${GF_ADMIN_PASSWORD:-admin}"

    DASH_COUNT=0
    for f in "$BACKUP_DIR"/grafana_dashboards/*.json; do
        if [ -f "$f" ]; then
            # Extract dashboard JSON and post it
            PAYLOAD=$(python3 -c "
import json,sys
data = json.load(open('$f'))
dash = data.get('dashboard', data)
dash.pop('id', None)
dash.pop('version', None)
print(json.dumps({'dashboard': dash, 'overwrite': True}))
" 2>/dev/null)
            if [ -n "$PAYLOAD" ]; then
                curl -sf -u "$GRAFANA_CREDS" -X POST "$GRAFANA_URL/api/dashboards/db" \
                    -H "Content-Type: application/json" -d "$PAYLOAD" >/dev/null 2>&1 \
                    && DASH_COUNT=$((DASH_COUNT + 1))
            fi
        fi
    done
    ok "Imported $DASH_COUNT dashboards"
else
    warn "No grafana_dashboards/ found — skipping"
fi

# --- .env ---
echo ""
echo "=== Configuration ==="
if [ -f "$BACKUP_DIR/dot_env_backup" ]; then
    warn "Found dot_env_backup — compare with your current .env manually:"
    echo "    diff $BACKUP_DIR/dot_env_backup .env"
fi

echo ""
echo "============================================="
echo "  Import complete. Run './scripts/status.sh' to verify."
echo "============================================="
