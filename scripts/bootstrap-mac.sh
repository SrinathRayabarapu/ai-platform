#!/usr/bin/env bash
# =============================================================================
# AI Platform — Bootstrap for macOS
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail() { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

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

# macOS Docker Desktop runs containers in a Linux VM; UID mapping is handled
# automatically. No chown/chmod needed (unlike bare Linux/WSL2).
ok "Permissions: Docker Desktop handles UID mapping automatically"

echo ""
echo "=== Step 4: Environment File ==="

if [ ! -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    warn ".env created from .env.example — review and edit passwords before production use"
else
    ok ".env already exists"
fi

echo ""
echo "=== Step 5: Start Platform ==="

cd "$PROJECT_DIR"
docker compose up -d

echo ""
echo "============================================="
echo "  AI Platform is starting!"
echo "============================================="
echo ""
echo "  Run './scripts/status.sh' to check health."
echo ""
