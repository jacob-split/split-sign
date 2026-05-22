# Codex Cloud Runtime

Use `bash .codex/cloud-setup.sh` as this repo's Codex Cloud setup script.

Expected Cloud environment variables or secrets:

- `GBRAIN_MCP_AUTHORIZATION`: preferred full authorization header value, for example `Bearer ...`.
- `GBRAIN_MCP_BEARER_TOKEN`: alternative token-only value; the setup script prefixes `Bearer`.
- `GBRAIN_MCP_URL`: optional override for the GBrain MCP URL. Defaults to `https://openclaw-gateway.tail27d90c.ts.net:3131/mcp`.
- `GBRAIN_MCP_STATS_URL`: optional health-check URL. Defaults to `https://openclaw-gateway.tail27d90c.ts.net:3131/admin/api/stats`.
- `TAILSCALE_AUTHKEY`: optional auth key if the Cloud environment cannot reach the tailnet URL directly.
- `REQUIRE_GBRAIN=1`: optional strict mode that fails setup if GBrain is unreachable.

The setup script writes `~/.codex/AGENTS.md`, `~/.codex/config.toml`, repo skills, and the curated skills Jacob expects to be available everywhere. Keep secrets out of git; the script only reads them from the Cloud environment.
