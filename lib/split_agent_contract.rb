# frozen_string_literal: true

module SplitAgentContract
  module_function

  VERSION = '2026-08-17'

  def contract
    {
      schemaVersion: 'split.agent-contract.v1',
      contractVersion: VERSION,
      app: {
        id: 'split-sign',
        name: 'Split Signature',
        category: 'document_signing',
        source: {
          repo: 'https://github.com/jacob-split/split-sign',
          branch: 'main',
          localPath: '/home/jacob/Split/src/split-sign'
        },
        productionUrls: ['https://sign.split-llc.com'],
        runtime: {
          host: 'ultramarine',
          path: '/srv/split-target/docuseal'
        },
        docs: ['AGENTS.md', 'docs/split-sign-continuity.md']
      },
      capabilities: capabilities,
      readiness: readiness,
      actions: actions,
      endpoints: {
        capabilities: '/api/agent/capabilities',
        readiness: '/api/agent/readiness.json',
        openapi: '/api/agent/openapi.json',
        actionInvocation: '/api/agent/actions/{action_id}/invoke',
        agentJson: '/.well-known/agent.json',
        agentCard: '/.well-known/agent-card.json'
      }
    }
  end

  def capabilities
    [
      {
        id: 'portal_document_sync',
        title: 'Portal document sync',
        status: 'ready',
        description: 'Split Signature writes submission state back to Supabase merchant_documents.',
        proof: ['MerchantPortalDocumentSync', 'ControlPlaneClient.upsert_merchant_document']
      },
      {
        id: 'signed_document_writeback',
        title: 'Signed document writeback',
        status: 'ready',
        description: 'Completed submitters update signed_at/status and can mark merchants complete.',
        proof: ['ProcessMerchantSigningJob', 'merchant_documents.signed_at']
      },
      {
        id: 'review_agreement_generation',
        title: 'Review agreement generation',
        status: 'ready',
        description: 'Portal onboarding can generate merchant-specific review agreement clones.',
        proof: ['MerchantPortalReviewAgreementGenerator', 'SPLIT_REVIEW_AGREEMENT_TEMPLATE_IDS']
      },
      {
        id: 'template_field_mapping',
        title: 'Template field mapping',
        status: 'ready',
        description: 'Template field mappings are read from and written to Supabase for repeatable prefill.',
        proof: ['MerchantFieldMapper', 'template_field_mappings']
      }
    ]
  end

  def readiness
    checks = [
      { id: 'runtime_path_registered', status: 'pass', message: 'Runtime is the split-target DocuSeal stack on ultramarine with state rooted at /srv/split-target/docuseal.' },
      { id: 'portal_sync_registered', status: 'pass', message: 'MerchantPortalDocumentSync is present.' },
      { id: 'signed_job_registered', status: 'pass', message: 'ProcessMerchantSigningJob is present.' },
      { id: 'live_mutations_blocked', status: 'pass', message: 'No live signing mutation is callable through public agent endpoints.' }
    ]

    {
      schemaVersion: 'split.agent-readiness.v1',
      appId: 'split-sign',
      contractVersion: VERSION,
      status: 'pass',
      checks: checks,
      summary: {
        pass: checks.count { |check| check[:status] == 'pass' },
        warn: checks.count { |check| check[:status] == 'warn' },
        fail: checks.count { |check| check[:status] == 'fail' }
      }
    }
  end

  def actions
    [
      {
        id: 'inspect_signing_contract',
        title: 'Inspect signing contract',
        risk: 'read',
        callable: false,
        requiresAuth: false,
        proof: ['GET /api/agent/capabilities']
      },
      {
        id: 'generate_review_agreements',
        title: 'Generate merchant review agreements',
        risk: 'live_world',
        callable: false,
        requiresAuth: true,
        proof: ['must run through authenticated Rails/Split workflow', 'writes submissions and merchant_documents']
      },
      {
        id: 'resync_submission_to_portal',
        title: 'Resync submission to portal',
        risk: 'write',
        callable: false,
        requiresAuth: true,
        proof: ['must run through authenticated Rails/Split workflow', 'updates merchant_documents']
      }
    ]
  end

  def agent_card
    {
      schemaVersion: 'a2a.agent-card.v1',
      name: 'Split Signature',
      description: 'Agent discovery for Split Signature document generation, signing, and portal document writeback.',
      url: 'https://sign.split-llc.com',
      provider: {
        organization: 'Split LLC',
        repo: 'https://github.com/jacob-split/split-sign'
      },
      capabilities: capabilities.map { |item| item.slice(:id, :title, :status) },
      endpoints: contract[:endpoints]
    }
  end

  def openapi
    {
      openapi: '3.1.0',
      info: {
        title: 'Split Signature Agent API',
        version: VERSION
      },
      paths: {
        '/api/agent/capabilities' => {
          get: {
            summary: 'Read the Split Signature agent contract',
            responses: { '200' => { description: 'Agent contract' } }
          }
        },
        '/api/agent/readiness.json' => {
          get: {
            summary: 'Read the Split Signature readiness report',
            responses: { '200' => { description: 'Readiness report' } }
          }
        },
        '/api/agent/actions/{action_id}/invoke' => {
          post: {
            summary: 'Invoke a proof-gated signing action when implemented',
            responses: {
              '403' => { description: 'Action is not callable through this public surface' },
              '404' => { description: 'Unknown action' }
            }
          }
        }
      }
    }
  end
end
