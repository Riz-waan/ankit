#!/bin/bash
set -euo pipefail

ANKI_DATA_DIR="${ANKI_DATA_DIR:-/data}"
WEB_PORT="${PORT:-8080}"
VNC_PORT="${VNC_PORT:-5900}"
NO_VNC_WEB_ROOT="${NO_VNC_WEB_ROOT:-/usr/share/novnc}"

# Ensure the data directory exists.
mkdir -p "$ANKI_DATA_DIR"

# Run Anki with the Qt VNC platform plugin unless explicitly overridden.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-vnc}"

echo "[info] Starting Anki with profile dir '$ANKI_DATA_DIR' on port $WEB_PORT"
anki -b "$ANKI_DATA_DIR" &
ANKI_PID=$!

cleanup() {
	if kill -0 "$ANKI_PID" 2>/dev/null; then
		kill "$ANKI_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT INT TERM

# Health check endpoint: listen on PORT for Cloud Run probes.
# Try to bridge VNC via websockify if available, else serve a simple health check.
python_health_server() {
	python3 << 'EOF'
import http.server
import socketserver
import os

port = int(os.environ.get('PORT', 8080))
Handler = http.server.SimpleHTTPRequestHandler

with socketserver.TCPServer(("", port), Handler) as httpd:
    print(f"[info] Health server listening on port {port}")
    httpd.serve_forever()
EOF
}

if command -v websockify >/dev/null 2>&1; then
	echo "[info] Exposing VNC localhost:${VNC_PORT} through noVNC on port ${WEB_PORT}"
	exec websockify --web="$NO_VNC_WEB_ROOT" "$WEB_PORT" "127.0.0.1:${VNC_PORT}"
elif command -v python3 >/dev/null 2>&1; then
	echo "[info] websockify not available; using Python health server on port ${WEB_PORT}"
	python_health_server &
	HEALTH_PID=$!
	wait "$ANKI_PID"
	kill "$HEALTH_PID" 2>/dev/null || true
else
	echo "[error] Neither websockify nor python3 available. Container may not respond to health checks."
	wait "$ANKI_PID"
fi