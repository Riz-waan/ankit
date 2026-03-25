#!/bin/bash
set -euo pipefail

ANKI_DATA_DIR="${ANKI_DATA_DIR:-/data}"
WEB_PORT="${PORT:-8080}"
VNC_PORT="${VNC_PORT:-5900}"
NO_VNC_WEB_ROOT="${NO_VNC_WEB_ROOT:-/usr/share/novnc}"

# Run Anki with the Qt VNC platform plugin unless explicitly overridden.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-vnc}"

echo "[info] Starting Anki with profile dir '$ANKI_DATA_DIR'"
anki -b "$ANKI_DATA_DIR" &
ANKI_PID=$!

cleanup() {
	if kill -0 "$ANKI_PID" 2>/dev/null; then
		kill "$ANKI_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT INT TERM

# Cloud Run only routes HTTP(S) on $PORT, so expose the VNC session via noVNC/websockify.
if command -v websockify >/dev/null 2>&1; then
	echo "[info] Exposing VNC localhost:${VNC_PORT} through noVNC on port ${WEB_PORT}"
	exec websockify --web="$NO_VNC_WEB_ROOT" "$WEB_PORT" "127.0.0.1:${VNC_PORT}"
fi

echo "[warn] websockify not installed; waiting on Anki process only"
wait "$ANKI_PID"