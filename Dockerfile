FROM debian:stable

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        firefox-esr \
        xvfb \
        x11vnc \
        openbox \
        novnc \
        websockify \
        x11-utils \
        dbus-x11 \
        nodejs \
        npm \
    && rm -rf /var/lib/apt/lists/*

# Playwright MCP server (lets an LLM drive a browser) + its Firefox build.
# Playwright cannot attach to the stock firefox-esr, so it ships its own
# patched Firefox, which the MCP server launches headed on the Xvfb display.
RUN npm install -g @playwright/mcp@latest \
    && npx playwright install --with-deps firefox \
    && npm cache clean --force

COPY files/firefox-branding.js /usr/lib/firefox-esr/browser/defaults/preferences/firefox-branding.js

COPY files/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh && mkdir -p /var/log/firefox /config/mcp-user-data

# 6080: noVNC (browser access), 5900: raw VNC, 3000: MCP server (SSE)
EXPOSE 6080 5900 3000

CMD ["/usr/local/bin/start.sh"]

