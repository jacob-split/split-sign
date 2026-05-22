---
name: gbrain-memory
description: Use when a task needs durable memory, prior decisions, Hermes memory, Codex memory, ByteRover migration context, or GBrain admin inspection.
---

# GBrain Memory

GBrain is the default durable memory and retrieval layer for Hermes and Codex continuity. Query the `gbrain` MCP server before relying on local or stale memory for prior context.

Use source `__all__` by default. Use `hermes-memory` only for Hermes-specific recall and `codex-memory` only for Codex-specific recall.

If this is Codex Cloud and the `gbrain` MCP server is missing, run `bash .codex/cloud-setup.sh` and then continue with an explicit note if the current agent process needs a restart or a new cloud task before MCP tools reload.
