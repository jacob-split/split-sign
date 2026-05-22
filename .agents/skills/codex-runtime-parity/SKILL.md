---
name: codex-runtime-parity
description: Use at the start of cloud, remote, local, VM, CLI, or app tasks to keep Codex behavior consistent across environments.
---

# Codex Runtime Parity

Before substantive work, check the available session skills and repo/global skills for anything relevant to the task. Apply the right frontend, backend, UI, testing, deployment, GitHub, Vercel, Supabase, OpenAI, or Split-specific skill instead of working from generic defaults.

Use GBrain as the default durable memory and retrieval layer when the task depends on prior context, decisions, Hermes/Codex continuity, or cross-session state. If GBrain is unavailable, surface the exact missing configuration or network condition.

In Codex Cloud, run `bash .codex/cloud-setup.sh` when the expected `~/.codex/config.toml`, skills, or GBrain MCP configuration are missing.
