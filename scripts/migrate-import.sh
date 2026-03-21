#!/usr/bin/env bash
# =============================================================================
# AI Platform — Import data from a migration backup
#
# Usage: ./scripts/migrate-import.sh <backup-directory>
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

cd "$PROJECT_DIR"
ai_platform_load_env "$PROJECT_DIR"

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

IMPORT_LOG="${BACKUP_DIR}/import-$(date +%Y%m%d_%H%M%S).log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

echo "============================================="
echo "  AI Platform — Import (Migration Restore)"
echo "  Source: $BACKUP_DIR"
echo "  Log: $IMPORT_LOG"
echo "============================================="

exec >> >(tee -a "$IMPORT_LOG") 2>&1

echo ""
echo "=== PostgreSQL ==="
if [ -f "$BACKUP_DIR/postgres_full.sql" ]; then
    CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-postgres"
    # pg_dumpall output includes roles and CREATE DATABASE — restore into maintenance DB 'postgres'
    if docker exec -i "$CONTAINER" psql -U "${POSTGRES_USER:-ai_user}" -d postgres -v ON_ERROR_STOP=1 <"$BACKUP_DIR/postgres_full.sql"; then
        ok "Imported: postgres_full.sql"
    else
        echo -e "${RED}PostgreSQL import reported errors — see $IMPORT_LOG${NC}"
        warn "If roles already exist, you may need a fresh volume or manual cleanup"
    fi
else
    warn "No postgres_full.sql found — skipping"
fi

echo ""
echo "=== Redis ==="
if [ -f "$BACKUP_DIR/redis_dump.rdb" ]; then
    REDIS_CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-redis"
    docker compose stop redis
    if docker cp "$BACKUP_DIR/redis_dump.rdb" "$REDIS_CONTAINER":/data/dump.rdb; then
        ok "Copied redis_dump.rdb into container"
    else
        warn "Could not copy RDB — ensure container name matches COMPOSE_PROJECT_NAME"
    fi
    docker compose start redis
    ok "Redis restarted"
else
    warn "No redis_dump.rdb found — skipping"
fi

echo ""
echo "=== Grafana Dashboards ==="
if [ -d "$BACKUP_DIR/grafana_dashboards" ]; then
    GRAFANA_URL="http://localhost:${GRAFANA_PORT:-3000}"
    GRAFANA_CREDS="admin:${GF_ADMIN_PASSWORD:-admin}"

    DASH_COUNT=0
    for f in "$BACKUP_DIR"/grafana_dashboards/*.json; do
        if [ -f "$f" ]; then
            PAYLOAD=$(python3 -c "
import json, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as fp:
    data = json.load(fp)
dash = data.get('dashboard', data)
dash.pop('id', None)
dash.pop('version', None)
print(json.dumps({'dashboard': dash, 'overwrite': True}))
" "$f" 2>/dev/null)
            if [ -n "$PAYLOAD" ]; then
                if curl -sf -u "$GRAFANA_CREDS" -X POST "$GRAFANA_URL/api/dashboards/db" \
                    -H "Content-Type: application/json" -d "$PAYLOAD" >/dev/null; then
                    DASH_COUNT=$((DASH_COUNT + 1))
                fi
            fi
        fi
    done
    ok "Imported $DASH_COUNT dashboards"
else
    warn "No grafana_dashboards/ found — skipping"
fi

echo ""
echo "=== Configuration ==="
if [ -f "$BACKUP_DIR/dot_env_backup" ]; then
    warn "Found dot_env_backup — merge manually; do not blindly overwrite:"
    echo "    diff $BACKUP_DIR/dot_env_backup .env"
fi

echo ""
echo "============================================="
echo "  Import finished. Run ./scripts/status.sh"
echo "  Full log: $IMPORT_LOG"
echo "============================================="
