#!/usr/bin/env bash
# =============================================================================
# AI Platform — Bootstrap (OS-aware entrypoint)
# Detects the OS and delegates to the appropriate platform-specific script.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================="
echo "  AI Platform — Bootstrap"
echo "============================================="

OS="$(uname -s)"
case "$OS" in
    Linux)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            echo "[INFO] Detected: Linux (WSL2)"
        else
            echo "[INFO] Detected: Linux"
        fi
        exec "$SCRIPT_DIR/bootstrap-linux.sh"
        ;;
    Darwin)
        echo "[INFO] Detected: macOS"
        exec "$SCRIPT_DIR/bootstrap-mac.sh"
        ;;
    *)
        echo "[ERROR] Unsupported OS: $OS"
        echo "        For Windows, run scripts/bootstrap-windows.ps1 from PowerShell."
        exit 1
        ;;
esac
