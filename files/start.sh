#!/bin/bash
set -e

export DISPLAY=:99
VNC_GEOMETRY="${VNC_GEOMETRY:-1280x800x24}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
MCP_PORT="${MCP_PORT:-3000}"
MCP_HOST="${MCP_HOST:-0.0.0.0}"

# Graceful shutdown on SIGTERM: terminate every process in the container.
# Note: SIGKILL cannot be trapped by any process. When the kernel delivers
# SIGKILL to this main process, it tears down the container's PID namespace
# and kills all remaining processes automatically.
shutdown() {
    trap - TERM INT
    echo "SIGTERM received: shutting down all processes gracefully..."
    for pid in /proc/[0-9]*; do
        p="${pid#/proc/}"
        [ "$p" = "$$" ] && continue
        kill -TERM "$p" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    exit 0
}
trap shutdown TERM INT

# Virtual display
Xvfb "$DISPLAY" -screen 0 "$VNC_GEOMETRY" -ac +extension GLX +render -noreset &

# Window manager
openbox &

# VNC server
if [ -n "$VNC_PASSWORD" ]; then
    x11vnc -storepasswd "$VNC_PASSWORD" /root/.vnc/passwd
    VNC_AUTH="-rfbauth /root/.vnc/passwd"
fi
x11vnc -display "$DISPLAY" -forever -shared -rfbport "$VNC_PORT" $VNC_AUTH &

# Firefox: restart automatically if closed by the user.
# --wait keeps the launcher alive until the browser really exits,
# so the loop only restarts when the browser is actually gone.
while true; do
    /usr/bin/firefox --wait "$@" >> /var/log/firefox/output.log 2>> /var/log/firefox/error.log &
    wait $! || true
    echo "Firefox was closed, restarting..."
    sleep 1
done &

# Playwright MCP server (SSE transport) so an LLM can drive a browser.
# It launches its own Playwright Firefox, headed, on the same Xvfb display,
# so the browser the LLM controls is the one visible via noVNC.
# Restart it if it ever exits, mirroring the Firefox loop.
while true; do
    playwright-mcp \
        --browser firefox \
        --port "$MCP_PORT" \
        --host "$MCP_HOST" \
        --user-data-dir /config/mcp-user-data \
        >> /var/log/firefox/mcp.log 2>&1 &
    wait $! || true
    echo "MCP server exited, restarting..."
    sleep 1
done &

# noVNC web client (browser access)
# Run in the background and wait on it: bash only runs the SIGTERM trap
# while it is in `wait`, not while blocked on a foreground command.
websockify --web /usr/share/novnc "$NOVNC_PORT" localhost:"$VNC_PORT" &
wait $!
