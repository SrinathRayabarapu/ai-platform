#!/usr/bin/env bash
# =============================================================================
# AI Platform — Status check (containers, health, ports, RAM)
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================="
echo "  AI Platform — Status"
echo "============================================="

# --- Container status ---
echo ""
echo "=== Containers ==="
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# --- Health checks ---
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

# --- TCP port checks ---
echo ""
echo "=== TCP Ports ==="

check_port() {
    local name="$1"
    local port="$2"
    if nc -z "$HOST" "$port" 2>/dev/null; then
        echo -e "  ${GREEN}[OPEN]${NC}  $name :$port"
    else
        echo -e "  ${RED}[CLOSED]${NC} $name :$port"
    fi
}

check_port "PostgreSQL" "${POSTGRES_PORT:-5432}"
check_port "Redis"      "${REDIS_PORT:-6379}"
check_port "Kafka"      "${KAFKA_EXTERNAL_PORT:-9094}"

# --- Resource usage ---
echo ""
echo "=== Resource Usage (RAM per container) ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || echo "  (docker stats unavailable)"

echo ""
echo "============================================="
