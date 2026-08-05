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

The container's configured working directory is the persisted `/data/docuseal` volume, while the Rails application and `Gemfile` are under `/app`. Run the harmless review-generation lock probe from `/app` and pass the current hash-shaped job payload:

```sh
app_id="$(sudo docker compose -f /opt/docuseal/docker-compose.gizmo.yml ps -q app)"
sudo docker exec -w /app "$app_id" bundle exec rails runner \
  "GenerateMerchantPortalReviewAgreementsJob.new.perform({'submission_ids'=>[-999999]}); puts 'review_lock_probe=passed'"
```

## Transactional Email

Split Signature uses the existing Split Resend account through SMTP. The canonical Mac Keychain entries are `com.split.shared.RESEND_API_KEY` and `com.split.shared.RESEND_FROM_EMAIL`; reuse those values and never rotate the key as part of a Split Signature deploy. Production must render a root-owned `/opt/docuseal/.env` with `SMTP_ADDRESS=smtp.resend.com`, port `587`, username `resend`, the existing Resend key as `SMTP_PASSWORD`, `SMTP_DOMAIN=split-llc.com`, STARTTLS enabled, and the Split Signature sender address. A blank `SMTP_ADDRESS` is unconfigured and must not activate the SMTP delivery path.

Before restarting the app, verify the live Resend domain is still enabled for sending and that the app container can reach the SMTP host. After the app-only deploy, confirm the SMTP settings are nonempty without printing their values, allow the intended Sidekiq retry to drain, and verify a successful mail event. Do not send a synthetic real-recipient message when an intended queued notification already provides end-to-end proof.

## Portal Document Sync

Primary Split-owned files:

- `app/services/merchant_portal_document_sync.rb`
- `app/services/merchant_portal_review_agreement_generator.rb`
- `app/jobs/process_merchant_signing_job.rb`
- `lib/control_plane_client.rb`
- `lib/merchant_field_mapper.rb`

The portal writeback table is the Split control-plane `merchant_documents` table. Split Signature updates:

- `template_id`
- `template_name`
- `submission_id`
- `embed_src`
- `sent_at`
- `opened_at`
- `signed_at`
- `declined_at`
- `expired_at`
- `last_signature_event_at`
- `status`
- `archived_at`
- `sort_order`

Every Split Signature surface uses this same lifecycle: portal embed, shared
link, API send, Admin Portal send, and direct Split Signature UI send. A
non-null `submission_id` identifies one historical agreement; sending the same
template again must create another agreement rather than overwrite the prior
one. Email-only merchant discovery fails closed when more than one merchant
shares the address.

## Signed Document Proof

When a submitter completes signing, `ProcessMerchantSigningJob` updates `merchant_documents` and marks the merchant complete only when active documents are signed.

Signed PDF visibility for Notion and portal users depends on the website download routes resolving the `merchant_documents.id` record to the signed Split Signature artifact.

## Review Agreement Generation

`MerchantPortalReviewAgreementGenerator` creates merchant-specific clones only
from active canonical masters in `Portal Agreements`, stores new clones in that
same folder, applies deterministic prefill defaults, creates no-email portal
submissions, and writes them back through `MerchantPortalDocumentSync`.
Existing templates in `pending` are historical records and must not be moved or
deleted by deployment or backfill.

The current default portal masters are `128, 129`: Onyx MPA and Private Client
Lease Agreement. Template `130`, Private Client Delivery and Acceptance, is
the operational replacement for Installation Verification. It is generated
with the two initial agreements and remains independently available at sort
order 100, but must not be included in or block the initial packet. Legacy
templates `1, 2, 9, 10, 94, 95`
remain canonical historical/alternate masters and must not be deleted.

Templates `128` through `130` were created from externally retained,
SHA-256-pinned source PDFs. All merchant signatures and initials are typed
acknowledgements, signing dates are signer-generated date fields, and every
delivery date remains a blank read-only operational field.

The initial Onyx and lease packet uses one Telnyx Verify challenge. Split writes
the same sent, phone-verified, and completed-verification proof into both native
submission audit trails. Delivery and Acceptance is a later independent signing
event and therefore carries its own SMS proof.

Template `128` owns the operator-configured pricing defaults. Portal submission
generation must copy fields mapped as `constant.template_default`; it must not
replace those values with blanks. The current defaults include 1.75% plus
$0.05 for credit, check card, Amex, and PIN debit, plus the configured voice
authorization, batch, chargeback, PCI, pre-arbitration, chargeback-reversal,
monthly-minimum, AVS, and per-item fees. Changes made to those master defaults
must flow through without hard-coding a different submission value.

Template `129` likewise preserves the operator-configured lease-payment
default. `script/repair_portal_agreement_template_defaults.rb` verifies both
masters in dry-run mode and changes only their `data_path` values when invoked
with `APPLY=1`.

Self-service portal generation remains fail-closed until all required merchant
profile data is complete. Admin ad hoc generation may explicitly mark only
missing template fields with `portal_signer_completion`; Split Signature permits
those allowlisted fields alongside typed signatures while continuing to reject
changes to populated read-only fields. Required checkbox choice groups use
`portal_signer_completion_group` and must have exactly one selected value.

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
