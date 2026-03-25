#!/usr/bin/env bash
# =============================================================================
# AI Platform — Write Prometheus file_sd target for Spring Boot /actuator/prometheus
#
# Reads (in order of precedence):
#   AI_SERVICES_SCRAPE_TARGET — full "host:port" (e.g. 100.111.29.42:8081)
#   DEV_MACHINE_IP + SPRING_ACTUATOR_PORT (default 8081)
#   default: host.docker.internal:8081
#
# Re-run after changing .env, then: docker compose restart prometheus
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

cd "$PROJECT_DIR"
ai_platform_load_env "$PROJECT_DIR"

TARGET="${AI_SERVICES_SCRAPE_TARGET:-}"
if [ -z "$TARGET" ] && [ -n "${DEV_MACHINE_IP:-}" ]; then
    TARGET="${DEV_MACHINE_IP}:${SPRING_ACTUATOR_PORT:-8081}"
fi
if [ -z "$TARGET" ]; then
    # Linux: host.docker.internal often missing DNS unless extra_hosts is set; and it never
    # reaches a Spring Boot app running on another host (e.g. Mac). Prefer DEV_MACHINE_IP in .env.
    echo "render-prometheus-config: WARNING: DEV_MACHINE_IP and AI_SERVICES_SCRAPE_TARGET unset; defaulting to host.docker.internal:8081 (wrong if the app runs on another machine)." >&2
    TARGET="host.docker.internal:8081"
fi

OUT_DIR="$PROJECT_DIR/config/prometheus/file_sd"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/ai-services.json"

export AI_SD_TARGET="$TARGET"
export AI_SD_OUT="$OUT_FILE"
python3 <<'PY'
import json, os
out = os.environ["AI_SD_OUT"]
target = os.environ["AI_SD_TARGET"]
doc = [{"targets": [target], "labels": {"env": "ai-lab"}}]
with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
PY

echo "Prometheus file_sd written: $OUT_FILE"
echo "  ai-services scrape target: $TARGET"
ai_platform_log "render-prometheus-config: target=$TARGET file=$OUT_FILE"
