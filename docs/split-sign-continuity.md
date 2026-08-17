# Split Sign Continuity

This is the current contract for Split Signature / DocuSeal document generation, signing, and portal writeback.

## Source And Runtime

- Source repo: `jacob-split/split-sign`
- Branch: `main`
- Authoritative local checkout: `/home/jacob/Split/src/split-sign`
- Runtime host: `ultramarine`
- Runtime state root: `/srv/split-target/docuseal`
- App container: `split-target-docuseal-app-1`
- Database container: `split-target-docuseal-postgres-1`
- Redis container: `split-target-docuseal-redis-1`
- Production URL: `https://sign.split-llc.com`
- Current app image source revision is read from OCI label `org.opencontainers.image.revision`; it must match the reviewed application-code commit used for the deployed image. Documentation/operations-only commits may legitimately be newer without forcing an app rebuild.

The runtime tree and Docker volumes are deployment state, not source authority. Make changes in the Surface checkout, commit/push them, deploy deliberately through the current `split-target` runtime process, and verify the running image revision before considering the release complete. Do not use retired `/opt/docuseal`, `gizmo-gateway`, or Mac `Split_dev` paths.

## Production Deployment

The current Surface deployment is a containerized `split-target-docuseal` stack with root-owned secrets under `/etc/split-target/secrets/`, persistent Docker volumes for application data/PostgreSQL/Redis, and route services `split-target-docuseal-app-proxy.service` plus `split-target-route-docuseal.service`. There is no authoritative host-side `/opt/docuseal/docker-compose.gizmo.yml` workflow anymore.

Before a release, capture the current app image/revision and database/application state. Deploy only a reviewed commit-pinned app image; do not replace PostgreSQL or Redis for an app-only source release. After deployment:

1. Verify `split-target-docuseal-app-1`, PostgreSQL, and Redis are running/healthy.
2. Verify the app container OCI revision equals the reviewed application-code commit for that image; do not require a rebuild solely because documentation/operations metadata advanced.
3. Verify `https://sign.split-llc.com` and the loopback route through the current Surface route services.
4. Check Rails/Sidekiq startup logs and the harmless review-generation lock probe from `/app`.
5. Verify portal document writeback and existing signed-document state without printing secrets or merchant PII.

The live app environment is root-owned in `/etc/split-target/secrets/docuseal-app.env`. Reuse the configured Resend SMTP and control-plane credentials; never copy them into the Git checkout, print them, or rotate them as an incidental deploy step.

For container-side Rails probes use the current app container, for example:

```sh
app_id="$(docker ps -q -f name=^split-target-docuseal-app-1$)"
docker exec -w /app "$app_id" bundle exec rails runner \
  "GenerateMerchantPortalReviewAgreementsJob.new.perform({'submission_ids'=>[-999999]}); puts 'review_lock_probe=passed'"
```

## Transactional Email

Split Signature uses the configured Split Resend SMTP values from `/etc/split-target/secrets/docuseal-app.env`. The runtime must have nonempty SMTP host, username, password, domain, sender, TLS, and timeout settings. Verify them by key presence and a real queued delivery when one already exists; do not print values or send an unnecessary synthetic message.

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
event and therefore carries its own SMS proof. Split Signature rejects final
completion for every SMS-gated portal submission unless all three provider-backed
events are already attached to that exact submitter, so a direct signing link
cannot bypass the portal challenge.

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
