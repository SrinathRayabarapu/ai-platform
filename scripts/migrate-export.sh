#!/usr/bin/env bash
# =============================================================================
# AI Platform — Export data for migration to a new machine
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

cd "$PROJECT_DIR"
ai_platform_load_env "$PROJECT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_DIR/backups/export_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
EXPORT_LOG="$BACKUP_DIR/export.log"
exec >> >(tee -a "$EXPORT_LOG") 2>&1

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail() { echo -e "${RED}[FAIL]${NC}  $1"; }

echo "============================================="
echo "  AI Platform — Export (Migration Backup)"
echo "  Output: $BACKUP_DIR"
echo "  Full transcript: $EXPORT_LOG"
echo "============================================="

echo ""
echo "=== PostgreSQL ==="
CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-postgres"
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    warn "Container $CONTAINER is not running — skipping pg_dumpall"
else
    if docker exec "$CONTAINER" pg_dumpall -U "${POSTGRES_USER:-ai_user}" >"$BACKUP_DIR/postgres_full.sql" 2>>"$EXPORT_LOG"; then
        ok "Exported: postgres_full.sql ($(du -h "$BACKUP_DIR/postgres_full.sql" | cut -f1))"
    else
        warn "PostgreSQL export failed — see tail of $EXPORT_LOG"
    fi
fi

echo ""
echo "=== Redis ==="
REDIS_CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-redis"
if docker ps --format '{{.Names}}' | grep -q "^${REDIS_CONTAINER}$"; then
    docker exec "$REDIS_CONTAINER" redis-cli BGSAVE >/dev/null 2>&1 || true
    sleep 3
    if docker cp "$REDIS_CONTAINER":/data/dump.rdb "$BACKUP_DIR/redis_dump.rdb" 2>>"$EXPORT_LOG"; then
        ok "Exported: redis_dump.rdb ($(du -h "$BACKUP_DIR/redis_dump.rdb" | cut -f1))"
    else
        warn "Redis RDB copy failed — see $EXPORT_LOG"
    fi
else
    warn "Container $REDIS_CONTAINER is not running — skipping Redis"
fi

echo ""
echo "=== Grafana Dashboards ==="
GRAFANA_URL="http://localhost:${GRAFANA_PORT:-3000}"
GRAFANA_CREDS="admin:${GF_ADMIN_PASSWORD:-admin}"

mkdir -p "$BACKUP_DIR/grafana_dashboards"
DASHBOARD_UIDS=$(curl -sf -u "$GRAFANA_CREDS" "$GRAFANA_URL/api/search" 2>/dev/null | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    for d in data:
        print(d.get('uid',''))
except Exception:
    pass
" 2>/dev/null)

DASH_COUNT=0
for uid in $DASHBOARD_UIDS; do
    if [ -n "$uid" ]; then
        if curl -sf -u "$GRAFANA_CREDS" "$GRAFANA_URL/api/dashboards/uid/$uid" \
            >"$BACKUP_DIR/grafana_dashboards/${uid}.json" 2>>"$EXPORT_LOG"; then
            DASH_COUNT=$((DASH_COUNT + 1))
        fi
    fi
done
ok "Exported $DASH_COUNT dashboards to grafana_dashboards/"

echo ""
echo "=== Configuration ==="
if [ -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env" "$BACKUP_DIR/dot_env_backup"
    ok "Copied .env (review before restoring secrets on new host)"
fi

echo ""
echo "============================================="
echo "  Export complete: $BACKUP_DIR"
echo "  If anything failed, read: $EXPORT_LOG"
echo "  To migrate: copy the folder to the new machine, then:"
echo "    ./scripts/migrate-import.sh backups/export_${TIMESTAMP}"
echo "============================================="
