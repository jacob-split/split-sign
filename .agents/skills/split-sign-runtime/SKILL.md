---
name: split-sign-runtime
description: Use for Split signing, document workflow, Rails, webhook, merchant document, PDF, or production signing runtime tasks.
---

# Split Sign Runtime

This repo contains Split signing and document workflow code. Inspect existing Rails conventions before editing and run focused tests for touched paths.

Treat signing links, generated documents, webhooks, and merchant/customer data as production-sensitive. Do not send live signing workflows or mutate merchant/customer state unless Jacob explicitly approves live execution in the active thread.

Use GBrain for prior Split signing decisions and cross-session context before relying on local notes.
