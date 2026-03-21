#!/usr/bin/env bash
# =============================================================================
# AI Platform — Status check (containers, health, ports, RAM)
# Loads .env if present so AI_LAB_HOST / ports match your deployment.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

cd "$PROJECT_DIR"
ai_platform_load_env "$PROJECT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================="
echo "  AI Platform — Status"
echo "============================================="

echo ""
echo "=== Containers ==="
docker compose ps -a --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || {
    echo -e "  ${RED}docker compose ps failed${NC} — is Docker running? Try: docker info"
    exit 1
}

echo ""
echo "=== Health Endpoints ==="

check_health() {
    local name="$1"
    local url="$2"
    local code
    code=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || echo "000")
    if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
        echo -e "  ${GREEN}[UP]${NC}   $name ($url) — HTTP $code"
    else
        echo -e "  ${RED}[DOWN]${NC} $name ($url) — HTTP $code"
    fi
}

HOST="${AI_LAB_HOST:-localhost}"

check_health "Grafana"    "http://$HOST:${GRAFANA_PORT:-3000}/api/health"
check_health "Prometheus" "http://$HOST:${PROMETHEUS_PORT:-9090}/-/healthy"
check_health "Kafka UI"   "http://$HOST:${KAFKA_UI_PORT:-8080}"
check_health "pgAdmin4"   "http://$HOST:${PGADMIN_PORT:-5050}"
check_health "RedisInsight" "http://$HOST:${REDISINSIGHT_PORT:-5540}"

echo ""
echo "=== TCP Ports ==="

check_port() {
    local name="$1"
    local port="$2"
    if command -v nc &>/dev/null && nc -z -w 2 "$HOST" "$port" 2>/dev/null; then
        echo -e "  ${GREEN}[OPEN]${NC}  $name :$port"
        return
    fi
    if command -v python3 &>/dev/null && python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('$HOST', int('$port'))); s.close()" 2>/dev/null; then
        echo -e "  ${GREEN}[OPEN]${NC}  $name :$port"
        return
    fi
    # Fallback: bash /dev/tcp (Linux; macOS Bash 3 lacks /dev/tcp)
    if bash -c "echo >/dev/tcp/$HOST/$port" 2>/dev/null; then
        echo -e "  ${GREEN}[OPEN]${NC}  $name :$port"
    else
        echo -e "  ${RED}[CLOSED]${NC} $name :$port ${YELLOW}(from this machine to $HOST — install netcat or use python3 for checks)${NC}"
    fi
}

check_port "PostgreSQL" "${POSTGRES_PORT:-5432}"
check_port "Redis"      "${REDIS_PORT:-6379}"
check_port "Kafka"      "${KAFKA_EXTERNAL_PORT:-9094}"

echo ""
echo "=== Containers in bad states (if any) ==="
docker compose ps -a --format "{{.Name}}\t{{.Status}}" 2>/dev/null | grep -iE 'exited|dead|restarting|unhealthy' || echo "  (none matched exited/restarting/unhealthy — OK)"

echo ""
echo "=== Resource Usage (RAM per container) ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || echo "  (docker stats unavailable)"

echo ""
echo "=== Quick debug commands ==="
echo "  docker compose logs -f --tail=100 <service>"
echo "  docker compose logs prometheus grafana kafka postgres 2>&1 | tail -200"
echo "  See docs/DEBUGGING.md for full playbook"
echo ""
echo "============================================="
