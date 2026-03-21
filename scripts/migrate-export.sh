#!/usr/bin/env bash
# =============================================================================
# AI Platform — Export data for migration to a new machine
#
# Creates a timestamped backup directory with:
#   - PostgreSQL full dump (pg_dumpall)
#   - Redis RDB snapshot
#   - Grafana dashboards (API export)
#   - Platform config (.env)
#
# Kafka data is NOT exported (dev lab topics are ephemeral; config is in compose).
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_DIR/backups/export_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

echo "============================================="
echo "  AI Platform — Export (Migration Backup)"
echo "  Output: $BACKUP_DIR"
echo "============================================="

# --- PostgreSQL ---
echo ""
echo "=== PostgreSQL ==="
CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-postgres"
docker exec "$CONTAINER" pg_dumpall -U "${POSTGRES_USER:-ai_user}" > "$BACKUP_DIR/postgres_full.sql" 2>/dev/null \
    && ok "Exported: postgres_full.sql ($(du -h "$BACKUP_DIR/postgres_full.sql" | cut -f1))" \
    || warn "PostgreSQL export failed — is the container running?"

# --- Redis ---
echo ""
echo "=== Redis ==="
REDIS_CONTAINER="${COMPOSE_PROJECT_NAME:-ai-lab}-redis"
docker exec "$REDIS_CONTAINER" redis-cli BGSAVE >/dev/null 2>&1
sleep 2
docker cp "$REDIS_CONTAINER":/data/dump.rdb "$BACKUP_DIR/redis_dump.rdb" 2>/dev/null \
    && ok "Exported: redis_dump.rdb ($(du -h "$BACKUP_DIR/redis_dump.rdb" | cut -f1))" \
    || warn "Redis export failed — is the container running?"

# --- Grafana dashboards ---
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
except: pass
" 2>/dev/null)

DASH_COUNT=0
for uid in $DASHBOARD_UIDS; do
    if [ -n "$uid" ]; then
        curl -sf -u "$GRAFANA_CREDS" "$GRAFANA_URL/api/dashboards/uid/$uid" \
            > "$BACKUP_DIR/grafana_dashboards/${uid}.json" 2>/dev/null && DASH_COUNT=$((DASH_COUNT + 1))
    fi
done
ok "Exported $DASH_COUNT dashboards to grafana_dashboards/"

# --- .env ---
echo ""
echo "=== Configuration ==="
if [ -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env" "$BACKUP_DIR/dot_env_backup"
    ok "Copied .env"
fi

echo ""
echo "============================================="
echo "  Export complete: $BACKUP_DIR"
echo ""
echo "  To migrate, copy this directory to the new machine and run:"
echo "    ./scripts/migrate-import.sh backups/export_${TIMESTAMP}"
echo "============================================="
