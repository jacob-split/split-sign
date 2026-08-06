# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Submitters::SubmitValues do
  describe '.validate_portal_sms_verification!' do
    let(:account) { create(:account) }
    let!(:user) { create(:user, account:) }
    let(:template) { create(:template, account:, author: user) }
    let(:submission) do
      create(:submission, :with_submitters, template:, created_by_user: user)
    end
    let(:submitter) { submission.submitters.first }
    let(:proof_data) do
      {
        'channel' => 'sms',
        'provider' => 'telnyx_verify',
        'external_event_id' => SecureRandom.uuid
      }
    end

    def add_proof_event(event_type, data: proof_data)
      create(:submission_event, submission:, submitter:, event_type:, data:)
    end

    it 'fails closed for the Onyx and Private Client stack without complete proof' do
      submitter.update!(
        metadata: {
          'merchant_id' => 'merchant_123',
          'agreement_stack_key' => 'onyx_private_client'
        }
      )
      add_proof_event('send_2fa_sms')

      expect { described_class.validate_portal_sms_verification!(submitter) }
        .to raise_error(
          Submitters::SubmitValues::ValidationError,
          Submitters::SubmitValues::PORTAL_SMS_VERIFICATION_ERROR
        )
    end

    it 'honors the explicit SMS requirement for future portal stacks' do
      submitter.update!(
        metadata: {
          'merchant_id' => 'merchant_123',
          'agreement_stack_key' => 'future_stack',
          'requires_sms_verification' => true
        }
      )

      expect { described_class.validate_portal_sms_verification!(submitter) }
        .to raise_error(Submitters::SubmitValues::ValidationError)
    end

    it 'accepts only the complete provider-backed SMS audit event set' do
      submitter.update!(
        metadata: {
          'merchant_id' => 'merchant_123',
          'agreement_stack_key' => 'onyx_private_client'
        }
      )
      described_class::PORTAL_SMS_VERIFICATION_EVENT_TYPES.each { |event_type| add_proof_event(event_type) }

      expect { described_class.validate_portal_sms_verification!(submitter) }.not_to raise_error
    end

    it 'rejects proof events without provider references' do
      submitter.update!(
        metadata: {
          'merchant_id' => 'merchant_123',
          'requires_sms_verification' => true
        }
      )
      described_class::PORTAL_SMS_VERIFICATION_EVENT_TYPES.each do |event_type|
        add_proof_event(event_type, data: proof_data.except('external_event_id'))
      end

      expect { described_class.validate_portal_sms_verification!(submitter) }
        .to raise_error(Submitters::SubmitValues::ValidationError)
    end

    it 'does not add an SMS requirement to legacy merchant agreements' do
      submitter.update!(
        metadata: {
          'merchant_id' => 'merchant_123',
          'agreement_stack_key' => 'payroc_tcg',
          'requires_sms_verification' => false
        }
      )

      expect { described_class.validate_portal_sms_verification!(submitter) }.not_to raise_error
    end
  end

  describe '.portal_action_field?' do
    it 'allows only signatures, initials, and explicitly authorized signer-completion fields' do
      expect(described_class.portal_action_field?({ 'type' => 'signature' })).to be(true)
      expect(described_class.portal_action_field?({ 'type' => 'initials' })).to be(true)
      expect(
        described_class.portal_action_field?(
          {
            'type' => 'text',
            'preferences' => { 'portal_signer_completion' => true }
          }
        )
      ).to be(true)
      expect(described_class.portal_action_field?({ 'type' => 'text' })).to be(false)
    end
  end

  describe '.validate_portal_completion_groups!' do
    let(:group_preferences) do
      {
        'portal_signer_completion' => true,
        'portal_signer_completion_group' => 'bank_account_type',
        'portal_signer_completion_group_required' => true
      }
    end
    let(:fields) do
      [
        {
          'uuid' => 'personal',
          'type' => 'checkbox',
          'submitter_uuid' => 'merchant',
          'readonly' => false,
          'preferences' => group_preferences
        },
        {
          'uuid' => 'business',
          'type' => 'checkbox',
          'submitter_uuid' => 'merchant',
          'readonly' => false,
          'preferences' => group_preferences
        }
      ]
    end
    let(:submission) { Struct.new(:template_fields).new(fields) }

    it 'accepts exactly one selected choice' do
      submitter = Struct.new(:uuid, :values, :submission).new(
        'merchant',
        { 'personal' => false, 'business' => true },
        submission
      )

      expect { described_class.validate_portal_completion_groups!(submitter) }.not_to raise_error
    end

    it 'rejects unanswered and multiply selected choice groups' do
      unanswered = Struct.new(:uuid, :values, :submission).new(
        'merchant',
        { 'personal' => false, 'business' => false },
        submission
      )
      multiple = Struct.new(:uuid, :values, :submission).new(
        'merchant',
        { 'personal' => true, 'business' => true },
        submission
      )

      expect { described_class.validate_portal_completion_groups!(unanswered) }
        .to raise_error(Submitters::SubmitValues::RequiredFieldError, 'personal')
      expect { described_class.validate_portal_completion_groups!(multiple) }
        .to raise_error(Submitters::SubmitValues::RequiredFieldError, 'personal')
    end

    it 'requires every mirrored occurrence of the selected choice' do
      mirrored_fields = [
        fields.first.merge(
          'uuid' => 'corporation-page-1',
          'preferences' => group_preferences.merge(
            'portal_signer_completion_group_choice' => 'corporation'
          )
        ),
        fields.first.merge(
          'uuid' => 'corporation-page-2',
          'preferences' => group_preferences.merge(
            'portal_signer_completion_group_choice' => 'corporation'
          )
        ),
        fields.last.merge(
          'uuid' => 'llc-page-1',
          'preferences' => group_preferences.merge(
            'portal_signer_completion_group_choice' => 'llc'
          )
        ),
        fields.last.merge(
          'uuid' => 'llc-page-2',
          'preferences' => group_preferences.merge(
            'portal_signer_completion_group_choice' => 'llc'
          )
        )
      ]
      mirrored_submission = Struct.new(:template_fields).new(mirrored_fields)
      complete = Struct.new(:uuid, :values, :submission).new(
        'merchant',
        {
          'corporation-page-1' => false,
          'corporation-page-2' => false,
          'llc-page-1' => true,
          'llc-page-2' => true
        },
        mirrored_submission
      )
      incomplete = Struct.new(:uuid, :values, :submission).new(
        'merchant',
        {
          'corporation-page-1' => false,
          'corporation-page-2' => false,
          'llc-page-1' => true,
          'llc-page-2' => false
        },
        mirrored_submission
      )

      expect { described_class.validate_portal_completion_groups!(complete) }.not_to raise_error
      expect { described_class.validate_portal_completion_groups!(incomplete) }
        .to raise_error(Submitters::SubmitValues::RequiredFieldError, 'corporation-page-1')
    end
  end

  it 'synchronizes mirrored portal checkbox choices across the entire agreement' do
    source = Rails.root.join('app/javascript/submission_form/form.vue').read

    expect(source).to match(
      /this\.fields\s*\.filter\(\(item\) => item\.preferences\?\.portal_signer_completion_group === group\)/
    )
  end
end
