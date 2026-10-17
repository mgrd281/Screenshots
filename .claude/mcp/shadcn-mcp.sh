#!/bin/sh
# Starts the shadcn/ui MCP server for the coding agent, at a pinned version,
# so it can browse and read shadcn/ui's components as design references.
# Install scripts of its dependencies are not run.
export npm_config_ignore_scripts=true
exec npx -y shadcn@4.21.1 mcp "$@"
