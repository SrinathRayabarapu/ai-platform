#!/usr/bin/env bash
# =============================================================================
# AI Platform — shared helpers (source from other scripts: source scripts/lib/common.sh)
# =============================================================================

# Project root (directory containing docker-compose.yml)
ai_platform_project_dir() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    echo "$here"
}

# Load .env into current shell (safe for values without spaces in keys we use).
# Does not fail if .env is missing.
ai_platform_load_env() {
    local root="${1:-}"
    if [ -z "$root" ]; then
        root="$(ai_platform_project_dir)"
    fi
    if [ -f "$root/.env" ]; then
        set -a
        # shellcheck disable=SC1090,SC1091
        source "$root/.env"
        set +a
    fi
}

# Verbose / trace logging for debugging failed runs.
# Usage: AI_PLATFORM_DEBUG=1 ./scripts/bootstrap.sh
# Or:    export AI_PLATFORM_DEBUG=1
ai_platform_debug_on() {
    [ "${AI_PLATFORM_DEBUG:-0}" = "1" ] || [ "${AI_PLATFORM_DEBUG:-0}" = "true" ]
}

ai_platform_log_dir() {
    local root="${1:-$(ai_platform_project_dir)}"
    mkdir -p "$root/logs"
    echo "$root/logs"
}

# Append a line to the session log file (set AI_PLATFORM_LOG_FILE before calling bootstraps).
ai_platform_log() {
    local msg="$1"
    if [ -n "${AI_PLATFORM_LOG_FILE:-}" ]; then
        echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $msg" >>"$AI_PLATFORM_LOG_FILE"
    fi
}
