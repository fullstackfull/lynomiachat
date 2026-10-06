# frozen_string_literal: true

# The WEBHOOK section of a Lynomia WhatsApp diagnosis: where Meta will actually deliver this number's events,
# which fields it will send, and whether this installation could verify a delivery arriving right now.
#
# Kept apart from MetaChecks because the callback question is the one a Meta dashboard check cannot answer — see
# Whatsapp::Diagnosis::CallbackClassification — and because this section reads both sides: Meta's configuration and
# the installation's own signing material.
#
# One GET, and only when a phone_number_id exists. Nothing is written.
class Whatsapp::Diagnosis::WebhookChecks
  include Whatsapp::Diagnosis::StoredConfig

  CLASSIFICATION = Whatsapp::Diagnosis::CallbackClassification

  FIELDS_NOTE = 'Without `messages` Meta never posts customer messages or delivery statuses, so inbound is silent ' \
                'AND outbound messages never leave `sent`. Without `smb_message_echoes` a Coexistence number loses ' \
                'the Business App side of the conversation.'

  VERIFICATION_NOTE = 'A missing signing secret means Webhooks::WhatsappController answers 401 to every delivery ' \
                      'and nothing but a Rails.logger.warn records it. A missing channel verify token means Meta ' \
                      'cannot re-verify the per-number callback when it next challenges it.'

  def initialize(report)
    @report = report
  end

  def run(channel, config, subscribed_fields:)
    report.heading("WEBHOOK — inbox ##{channel.inbox&.id}")
    report.say "route Meta should call: #{displayed_callback(channel)}"
    report.say "app-level route (template status webhooks): #{CLASSIFICATION.safe(app_level_route)}"
    classify(config, expected_callback(channel))
    required_fields(subscribed_fields)
    verification_readiness(channel, config)
  end

  private

  attr_reader :report

  def expected_callback(channel)
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp/#{channel.phone_number}"
  end

  # The comparison uses the real number; the printed line never does.
  def displayed_callback(channel)
    "#{ENV.fetch('FRONTEND_URL', '<FRONTEND_URL unset>')}/webhooks/whatsapp/#{report.mask_phone(channel.phone_number)}"
  end

  def app_level_route = "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp"

  def classify(config, expected)
    phone_number_id = config[:phone_number_id]
    return report.blocked('effective callback', 'provider_config has no api_key on this channel') if config[:api_key].blank?
    return report.blocked('effective callback', 'provider_config has no phone_number_id') if phone_number_id.blank?

    client = Whatsapp::FacebookApiClient.new(config[:api_key])
    report.read("what Meta holds for this number (/#{phone_number_id}?fields=webhook_configuration)") do
      data = client.fetch_phone_number(phone_number_id, fields: 'webhook_configuration')
      report_classification(CLASSIFICATION.new(expected: expected, configuration: data['webhook_configuration']))
    end
  end

  def report_classification(classification)
    report.rows(
      [
        ['phone-level override', CLASSIFICATION.safe(classification.override)],
        ['app-level callback', CLASSIFICATION.safe(classification.app_level)],
        ['effective (an override wins)', CLASSIFICATION.safe(classification.effective)]
      ],
      indent: '  '
    )
    report.say '  (scheme, host and path only — an override URI can carry a verify token in its query string)'
    if classification.verdict == CLASSIFICATION::UNKNOWN
      return report.blocked('the callback Meta will deliver to', "#{classification} — #{classification.note}")
    end

    report.check('the callback Meta will deliver to is this installation',
                 classification.verdict == CLASSIFICATION::MATCH,
                 classification.to_s, note: classification.note)
  end

  def required_fields(subscribed_fields)
    return report.blocked('subscribed webhook fields', 'the WABA read did not report a field list') if subscribed_fields.nil?

    missing = Whatsapp::Diagnosis::MetaChecks::REQUIRED_FIELDS - subscribed_fields
    report.check('the required webhook fields are subscribed', missing.empty?,
                 missing.empty? ? "all of #{Whatsapp::Diagnosis::MetaChecks::REQUIRED_FIELDS.join(', ')}" : "MISSING #{missing.join(', ')}",
                 note: FIELDS_NOTE)
  end

  # Whether Meta's re-verification challenge for THIS number could be answered. The signing secret is the AUTH
  # section's single check, and is only referenced here so the two are read together.
  def verification_readiness(channel, config)
    verify = config[:webhook_verify_token].presence
    secret = config[:app_secret].presence || stored_config('WHATSAPP_APP_SECRET')
    report.check("inbox ##{channel.inbox&.id}: this number has a webhook verify token",
                 verify.present?, verify.present? ? 'present' : 'MISSING',
                 note: VERIFICATION_NOTE)
    report.say "  signing secret for this channel: #{secret.present? ? 'available (see AUTH)' : 'MISSING (see AUTH)'}"
  end
end
