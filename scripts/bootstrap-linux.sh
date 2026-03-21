#!/usr/bin/env bash
# =============================================================================
# AI Platform — Bootstrap for Linux / WSL2
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; ai_platform_log "OK: $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; ai_platform_log "WARN: $1"; }
fail() { echo -e "${RED}[FAIL]${NC}  $1"; ai_platform_log "FAIL: $1"; exit 1; }

LOG_DIR="$(ai_platform_log_dir "$PROJECT_DIR")"
export AI_PLATFORM_LOG_FILE="${AI_PLATFORM_LOG_FILE:-$LOG_DIR/bootstrap-$(date +%Y%m%d_%H%M%S).log}"
touch "$AI_PLATFORM_LOG_FILE"
ai_platform_log "bootstrap-linux.sh start PROJECT_DIR=$PROJECT_DIR"

if ai_platform_debug_on; then
    set -x
    ok "AI_PLATFORM_DEBUG=1 — shell tracing enabled; full log: $AI_PLATFORM_LOG_FILE"
fi

echo ""
echo "=== Step 1: Verify Docker ==="

if ! command -v docker &>/dev/null; then
    fail "Docker is not installed. Install Docker Engine: https://docs.docker.com/engine/install/"
fi
ok "Docker CLI found: $(docker --version)"

if ! docker info &>/dev/null; then
    fail "Docker daemon is not running. Start it with: sudo service docker start"
    # On WSL2: sudo service docker start
fi
ok "Docker daemon is running"

if ! docker compose version &>/dev/null; then
    fail "Docker Compose v2 plugin not found. Install: https://docs.docker.com/compose/install/"
fi
ok "Docker Compose found: $(docker compose version --short 2>/dev/null || docker compose version)"

echo ""
echo "=== Step 2: Check System Resources ==="

CPU_CORES=$(nproc 2>/dev/null || echo "0")
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))

if [ "$CPU_CORES" -lt 4 ]; then
    warn "CPU cores: $CPU_CORES (minimum recommended: 4)"
else
    ok "CPU cores: $CPU_CORES"
fi

if [ "$TOTAL_RAM_GB" -lt 8 ]; then
    warn "RAM: ${TOTAL_RAM_GB} GB (minimum recommended: 8 GB)"
else
    ok "RAM: ${TOTAL_RAM_GB} GB"
fi

echo ""
echo "=== Step 3: Create Data Directories ==="

DATA_DIRS=(postgres kafka redis prometheus grafana pgadmin redisinsight)

for dir in "${DATA_DIRS[@]}"; do
    mkdir -p "$PROJECT_DIR/data/$dir"
done
ok "Data directories created under $PROJECT_DIR/data/"

echo ""
echo "=== Step 4: Fix Directory Permissions ==="
echo "    (requires sudo for chown/chmod on Grafana, Prometheus, pgAdmin dirs)"

if ! sudo chown -R 472:472 "$PROJECT_DIR/data/grafana" 2>>"$AI_PLATFORM_LOG_FILE"; then
    warn "chown grafana (472) failed — see log: $AI_PLATFORM_LOG_FILE — fix: sudo chown -R 472:472 $PROJECT_DIR/data/grafana"
else
    ok "Grafana data dir (UID 472)"
fi

if ! sudo chmod -R 777 "$PROJECT_DIR/data/prometheus" 2>>"$AI_PLATFORM_LOG_FILE"; then
    warn "chmod prometheus failed — see log — fix: sudo chmod -R 777 $PROJECT_DIR/data/prometheus"
else
    ok "Prometheus data dir (writable)"
fi

if ! sudo chown -R 5050:5050 "$PROJECT_DIR/data/pgadmin" 2>>"$AI_PLATFORM_LOG_FILE"; then
    warn "chown pgadmin (5050) failed — see log — fix: sudo chown -R 5050:5050 $PROJECT_DIR/data/pgadmin"
else
    ok "pgAdmin data dir (UID 5050)"
fi

echo ""
echo "=== Step 5: Environment File ==="

if [ ! -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    warn ".env created from .env.example — review passwords and DEV_MACHINE_IP / KAFKA_ADVERTISED_EXTERNAL_HOST"
else
    ok ".env already exists"
fi

echo ""
echo "=== Step 6: Render Prometheus scrape target (file_sd) ==="
"$SCRIPT_DIR/render-prometheus-config.sh" 2>&1 | tee -a "$AI_PLATFORM_LOG_FILE"

echo ""
echo "=== Step 7: Start Platform ==="

cd "$PROJECT_DIR"
if ! docker compose up -d 2>&1 | tee -a "$AI_PLATFORM_LOG_FILE"; then
    fail "docker compose up -d failed — see: $AI_PLATFORM_LOG_FILE and run: docker compose ps -a && docker compose logs"
fi

echo ""
echo "============================================="
echo "  AI Platform is starting!"
echo "============================================="
echo ""
echo "  Session log: $AI_PLATFORM_LOG_FILE"
echo "  Run './scripts/status.sh' to check health."
echo "  If something fails: see docs/DEBUGGING.md"
echo ""

ai_platform_log "bootstrap-linux.sh finished successfully"
