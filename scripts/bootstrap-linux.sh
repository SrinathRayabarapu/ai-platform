#!/usr/bin/env bash
# =============================================================================
# AI Platform — Bootstrap for Linux / WSL2
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
echo "=== Step 1: Verify Docker ==="

if ! command -v docker &>/dev/null; then
    fail "Docker is not installed. Install Docker Engine: https://docs.docker.com/engine/install/"
fi
ok "Docker CLI found: $(docker --version)"

if ! docker info &>/dev/null; then
    fail "Docker daemon is not running. Start it with: sudo service docker start"
fi
ok "Docker daemon is running"

if ! command -v docker compose &>/dev/null && ! docker compose version &>/dev/null; then
    fail "Docker Compose (v2) not found. Install: https://docs.docker.com/compose/install/"
fi
ok "Docker Compose found: $(docker compose version --short 2>/dev/null || echo 'available')"

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

# Fix ownership for containers that run as non-root UIDs
echo ""
echo "=== Step 4: Fix Directory Permissions ==="
echo "    (requires sudo for chown/chmod on Grafana, Prometheus, pgAdmin dirs)"

sudo chown -R 472:472 "$PROJECT_DIR/data/grafana"    2>/dev/null && ok "Grafana (UID 472)" || warn "chown grafana failed — may need manual fix"
sudo chmod -R 777     "$PROJECT_DIR/data/prometheus"  2>/dev/null && ok "Prometheus (777)" || warn "chmod prometheus failed — may need manual fix"
sudo chown -R 5050:5050 "$PROJECT_DIR/data/pgadmin"   2>/dev/null && ok "pgAdmin (UID 5050)" || warn "chown pgadmin failed — may need manual fix"

echo ""
echo "=== Step 5: Environment File ==="

if [ ! -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    warn ".env created from .env.example — review and edit passwords before production use"
else
    ok ".env already exists"
fi

echo ""
echo "=== Step 6: Start Platform ==="

cd "$PROJECT_DIR"
docker compose up -d

echo ""
echo "============================================="
echo "  AI Platform is starting!"
echo "============================================="
echo ""
echo "  Run './scripts/status.sh' to check health."
echo ""
