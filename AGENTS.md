# Agent Instructions

## Codex Runtime Contract

Select skills for the actual workflow. Load the relevant entrypoint and only the supporting references needed for the affected component. A typo or documentation fix does not require deployment, database or design playbooks; optional workflows add no approval gate.

Surface Linux is the primary local development and execution environment for this repository. The authoritative local checkout is `/home/jacob/Split/src/split-sign`; do not redirect normal work to retired Gizmo/Ubuntu paths or stale macOS checkouts. The Mac remains an Apple-specific/user-facing peer when a task genuinely requires macOS.

Current conversation and live source/runtime state are authoritative. For substantive work, use GEE `continuity_start` with catalog project `split-sign`; reach Memorix only through GEE for current work, and use Deja only as historical evidence. Use Macro for stored operational-source retrieval and read originating services directly for current facts. Do not recreate GBrain or another retired duplicate memory/indexing layer. In Codex Cloud, run `bash .codex/cloud-setup.sh` when expected local config or skills are missing.

Cloud setup installs a deliberate Cloud policy while keeping repository instructions and skills at repository scope. It validates and preserves unrelated configuration, authentication and model choices; it does not copy a live runtime home or establish new private-network membership.

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
