#!/bin/sh
# LottieFiles Creator's MCP server, at a pinned version, with install
# scripts off. It talks to the Creator editor open in a browser on this
# computer, over a local connection; nothing else.
export npm_config_ignore_scripts=true
exec npx -y @lottiefiles/creator-mcp@0.2.2 "$@"
