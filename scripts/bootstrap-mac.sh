#!/usr/bin/env bash
# =============================================================================
# AI Platform — Bootstrap for macOS
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
ai_platform_log "bootstrap-mac.sh start PROJECT_DIR=$PROJECT_DIR"

if ai_platform_debug_on; then
    set -x
    ok "AI_PLATFORM_DEBUG=1 — shell tracing enabled; full log: $AI_PLATFORM_LOG_FILE"
fi

echo ""
echo "=== Step 1: Verify Docker Desktop ==="

if ! command -v docker &>/dev/null; then
    fail "Docker is not installed. Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
fi
ok "Docker CLI found: $(docker --version)"

if ! docker info &>/dev/null; then
    fail "Docker Desktop is not running. Open Docker Desktop and try again."
fi
ok "Docker daemon is running"

if ! docker compose version &>/dev/null; then
    fail "Docker Compose not available. Update Docker Desktop."
fi
ok "Docker Compose found: $(docker compose version --short)"

echo ""
echo "=== Step 2: Check System Resources ==="

CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
TOTAL_RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))

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
ok "Permissions: Docker Desktop handles UID mapping automatically"

echo ""
echo "=== Step 4: Environment File ==="

if [ ! -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    warn ".env created from .env.example — review passwords and scrape/Kafka host settings"
else
    ok ".env already exists"
fi

echo ""
echo "=== Step 5: Render Prometheus scrape target (file_sd) ==="
"$SCRIPT_DIR/render-prometheus-config.sh" 2>&1 | tee -a "$AI_PLATFORM_LOG_FILE"

echo ""
echo "=== Step 6: Start Platform ==="

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

ai_platform_log "bootstrap-mac.sh finished successfully"
