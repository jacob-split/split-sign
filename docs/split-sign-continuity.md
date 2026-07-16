# Split Sign Continuity

This is the current contract for Split Signature / DocuSeal document generation, signing, and portal writeback.

## Source And Runtime

- Source repo: `jacob-split/split-sign`
- Branch: `main`
- Local path: `/Users/jacob/Split/Split_dev/split-sign`
- Runtime host: `gizmo-gateway`
- Runtime path: `/opt/docuseal`
- Production URL: `https://sign.split-llc.com`

The runtime tree is not the source of truth. Update GitHub `main`, deploy deliberately, and verify the live runtime path.

## Production Deployment

Build a commit-pinned image and record the full source revision in both the image OCI labels and `/opt/docuseal/.split-source-revision`. Keep a rollback copy of the prior compose/runtime metadata under `/opt/docuseal/releases/<revision>/rollback` before changing the live app.

The production compose environment is root-owned. Use `sudo` for compose operations instead of changing ownership or copying credentials. For an app-only release, preserve PostgreSQL and deploy only the app service:

```sh
sudo docker compose -f /opt/docuseal/docker-compose.gizmo.yml up -d --no-deps --no-build app
```

Do not omit `--no-deps`; recreating the app must not bounce PostgreSQL. After deployment, read back the running image and revision, compare the deployed source-file hashes with the committed files, verify PostgreSQL health and record counts, check Sidekiq/Rails startup logs, exercise the review-generation job lock with a harmless nonexistent submission, and confirm both origin and public readiness latency. Retain the previous image and rollback metadata until those checks pass.

## Portal Document Sync

Primary Split-owned files:

- `app/services/merchant_portal_document_sync.rb`
- `app/services/merchant_portal_review_agreement_generator.rb`
- `app/jobs/process_merchant_signing_job.rb`
- `lib/supabase_client.rb`
- `lib/merchant_field_mapper.rb`

The portal writeback table is Supabase `merchant_documents`. Split Signature updates:

- `template_id`
- `template_name`
- `submission_id`
- `embed_src`
- `signed_at`
- `status`
- `archived_at`
- `sort_order`

## Signed Document Proof

When a submitter completes signing, `ProcessMerchantSigningJob` updates `merchant_documents` and marks the merchant complete only when active documents are signed.

Signed PDF visibility for Notion and portal users depends on the website download routes resolving the `merchant_documents.id` record to the signed Split Signature artifact.

## Review Agreement Generation

`MerchantPortalReviewAgreementGenerator` creates merchant-specific clones from configured master templates, applies deterministic prefill defaults, creates no-email portal submissions, and writes them back through `MerchantPortalDocumentSync`.

Relevant env:

- `SPLIT_REVIEW_AGREEMENT_TEMPLATE_IDS`
- `SPLIT_REVIEW_AGREEMENT_SORT_OFFSET`
- `SPLIT_REVIEW_AGREEMENT_FOLDER`
- `SPLIT_REVIEW_AGREEMENT_AUTHOR_EMAIL`

## Agent API

Discovery endpoints:

- `/.well-known/agent.json`
- `/.well-known/agent-card.json`
- `/api/agent/capabilities`
- `/api/agent/readiness.json`
- `/api/agent/openapi.json`

Public agent actions are blocked for live-world mutations. Document generation, submission resync, and review-agreement generation must remain authenticated Rails/Split workflows until an action has explicit auth, risk metadata, and proof handling.
