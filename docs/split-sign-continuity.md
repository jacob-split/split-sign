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

The VM host does not provide Ruby outside the application container. Use the installed host Python runtime for any atomic root-owned dotenv update. If the shared VM's classic Docker builder stalls on a tiny overlay, stop after the first failed build and recheck I/O pressure. A safe fallback is to derive the same commit-pinned image with `docker create`, `docker cp`, and `docker commit`, set the full OCI revision label, then compare all deployed file hashes before use; do not loop the builder or install another dependency tree.

## Transactional Email

Split Signature uses the existing Split Resend account through SMTP. The canonical Mac Keychain entries are `com.split.shared.RESEND_API_KEY` and `com.split.shared.RESEND_FROM_EMAIL`; reuse those values and never rotate the key as part of a Split Signature deploy. Production must render a root-owned `/opt/docuseal/.env` with `SMTP_ADDRESS=smtp.resend.com`, port `587`, username `resend`, the existing Resend key as `SMTP_PASSWORD`, `SMTP_DOMAIN=split-llc.com`, STARTTLS enabled, and the Split Signature sender address. A blank `SMTP_ADDRESS` is unconfigured and must not activate the SMTP delivery path.

Before restarting the app, verify the live Resend domain is still enabled for sending and that the app container can reach the SMTP host. After the app-only deploy, confirm the SMTP settings are nonempty without printing their values, allow the intended Sidekiq retry to drain, and verify a successful mail event. Do not send a synthetic real-recipient message when an intended queued notification already provides end-to-end proof.

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
