#!/bin/sh
# Starts the Playwright MCP server for the coding agent, at a pinned version.
# In a Claude Code cloud container the browser Playwright provides lives in
# /opt/pw-browsers, and the container itself is the sandbox (it runs as
# root, where Chromium's own sandbox cannot start). Elsewhere Playwright
# finds or installs its own browser and keeps Chromium's sandbox on.
if [ -z "$PLAYWRIGHT_MCP_EXECUTABLE_PATH" ] && [ -x /opt/pw-browsers/chromium ]; then
  set -- --executable-path /opt/pw-browsers/chromium --no-sandbox "$@"
fi
exec npx -y @playwright/mcp@0.0.83 --headless --isolated --output-dir .playwright-mcp "$@"
