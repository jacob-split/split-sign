# Agent Instructions

## Codex Runtime Contract

Before any nontrivial task, review the available session skills and the repo/global skills that may apply. Use the relevant frontend, backend, UI, testing, deployment, GitHub, Vercel, Supabase, OpenAI, design-system, Ruby/Rails, and Split-specific skills before touching implementation. Do not skip skill discovery just because the task looks like a normal app edit.

All Codex environments must preserve the same operating behavior: macOS app, macOS CLI, VM CLI, remote sessions, Cloud tasks, and projectless chats. If the environment cannot read Jacob's global `/Users/jacob/.codex/AGENTS.md` or `/home/ubuntu/.codex/AGENTS.md`, recreate the same behavior from this file before substantive work.

GBrain is the default durable memory and retrieval layer for Codex/Hermes continuity. If a task needs prior context, project history, decisions, cross-session recall, or Hermes/Codex memory, query GBrain first through the `gbrain` MCP server when it is available. In Codex Cloud, run `bash .codex/cloud-setup.sh` if `~/.codex/config.toml`, GBrain MCP config, or expected skills are missing. If GBrain is still unavailable, identify the exact missing piece: `GBRAIN_MCP_AUTHORIZATION`, `GBRAIN_MCP_BEARER_TOKEN`, `TAILSCALE_AUTHKEY`, network access to the tailnet URL, or Cloud setup-script configuration. Do not silently fall back to stale local memory.

For Cloud runs, this repo intentionally carries `.codex/cloud-setup.sh`, `.codex/config.toml`, and `.agents/skills/*` so the cloud environment can hydrate the same config/skill behavior used locally and on the VM. Prefer using the configured setup script in the Codex Cloud environment so MCP servers and skills are ready before the agent starts.

## Split Sign Runtime

This repository contains Split signing/document workflow code. Treat document generation, signing links, merchant/customer data, webhooks, and production credentials as sensitive production behavior.

Inspect existing Rails conventions before editing, run focused tests for touched code, and verify production-bound behavior against the actual runtime path named by Jacob. Do not mutate merchant/customer state or send live document workflows unless Jacob explicitly approves live execution in the active thread.
