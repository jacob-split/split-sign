# Agent Instructions

## Codex Runtime Contract

Before any nontrivial task, review the available session skills and the repo/global skills that may apply. Use the relevant frontend, backend, UI, testing, deployment, GitHub, Vercel, Supabase, OpenAI, design-system, Ruby/Rails, and Split-specific skills before touching implementation. Do not skip skill discovery just because the task looks like a normal app edit.

Surface Linux is the primary local development and execution environment for this repository. The authoritative local checkout is `/home/jacob/Split/src/split-sign`; do not redirect normal work to retired Gizmo/Ubuntu paths or stale macOS checkouts. The Mac remains an Apple-specific/user-facing peer when a task genuinely requires macOS.

Current conversation and live source/runtime state are authoritative. For substantive work, use GEE `continuity_start` with catalog project `split-sign`; reach Memorix only through GEE for current work, and use Deja only as historical evidence. Use Macro for stored operational-source retrieval and read originating services directly for current facts. Do not recreate GBrain or another retired duplicate memory/indexing layer. In Codex Cloud, run `bash .codex/cloud-setup.sh` when expected local config or skills are missing.

For Cloud runs, this repo intentionally carries `.codex/cloud-setup.sh`, `.codex/config.toml`, and `.agents/skills/*` so the cloud environment can hydrate the same GEE/continuity and skill behavior used by the current project. Keep secrets out of git.

## Split Sign Runtime

This repository contains Split signing/document workflow code. Treat document generation, signing links, merchant/customer data, webhooks, and production credentials as sensitive production behavior.

Inspect existing Rails conventions before editing, run focused tests for touched code, and verify production-bound behavior against the actual runtime path named by Jacob. Do not mutate merchant/customer state or send live document workflows unless Jacob explicitly approves live execution in the active thread.

Before changing merchant portal document sync, Supabase `merchant_documents` writeback, signed-document completion state, review-agreement generation, or Split Signature agent discovery, read `docs/split-sign-continuity.md`.

Current machine-readable discovery surfaces:

- `/.well-known/agent.json`
- `/.well-known/agent-card.json`
- `/api/agent/capabilities`
- `/api/agent/readiness.json`
- `/api/agent/openapi.json`

Public agent actions are intentionally blocked for live signing/document mutations until an action has authenticated execution, risk metadata, and proof fields.
