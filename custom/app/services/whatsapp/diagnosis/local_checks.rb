# frozen_string_literal: true

# The CHANNEL and AUTH sections of a Lynomia WhatsApp diagnosis: what this installation has stored about the
# channel, and whether it holds the credentials the inbound and outbound paths need. No Meta call, no network.
#
# Reads only. Nothing here writes to the database, to Redis or to Meta.
class Whatsapp::Diagnosis::LocalChecks
  include Whatsapp::Diagnosis::StoredConfig

  SIGNATURE_FAILURE_NOTE = 'Webhooks::WhatsappController#verify_meta_signature! answers 401 and drops the payload. ' \
                           'This is the most commonly missed cause of "inbound never arrives", and it is silent ' \
                           'apart from a Rails.logger.warn.'

  # What the flag means now, and what it no longer means.
  #
  # It used to stop ALL inbound for an embedded-signup channel: Webhooks::WhatsappEventsJob returned after one
  # Rails.logger.warn when `reauthorization_required? && embedded_signup_channel?`, so every customer message was
  # discarded — permanently, since the Redis key has no expiry, and silently, since the controller had already
  # answered Meta 200 OK. That guard is gone (docs/real-whatsapp-uat/09-fix.md §1): inbound now persists and only
  # media downloads degrade. The flag is still worth reporting, because it means a real authorization problem was
  # recorded and the channel's outbound and media paths are affected.
  REAUTH_NOTE = 'An authorization problem was recorded for this channel. Since docs/real-whatsapp-uat/09-fix.md §1 ' \
                'this no longer discards inbound messages, but it does mean media downloads and token-bearing ' \
                'calls are failing. The only supported clear is completing the reauthorization flow for the inbox ' \
                '(Settings -> Inboxes -> this inbox); deleting the Redis key hides the cause and the flag returns ' \
                'after the next two authorization errors.'

  COUNTER_NOTE = 'prompt_reauthorization! can set the flag WITHOUT incrementing this counter, so a count of 0 ' \
                 'beside a set flag is expected and not a contradiction. Both are printed because neither can be ' \
                 'inferred from the other.'

  def initialize(report)
    @report = report
  end

  # ---- CHANNEL -------------------------------------------------------------------------------------------------

  def channel_section(channel, config)
    report.heading("CHANNEL — inbox ##{channel.inbox&.id}")
    report.rows(identity_rows(channel, config))
    reauthorization_check(channel)
  end

  # ---- AUTH ----------------------------------------------------------------------------------------------------

  # Presence and provenance only. The values themselves are never printed, masked or otherwise.
  def auth(channel, config)
    report.heading("AUTH — inbox ##{channel.inbox&.id}")
    report.rows(credential_rows(config))
    report.say "WHATSAPP_APP_ID: #{stored_config('WHATSAPP_APP_ID').presence || '<blank>'}"
    app_secret_check(config)
    verify_token_check
  end

  private

  attr_reader :report

  def reauthorization_check(channel)
    latched = channel.reauthorization_required?
    report.say "authorization_error_count: #{channel.authorization_error_count} " \
               "(threshold #{channel.class::AUTHORIZATION_ERROR_THRESHOLD})"
    report.say "  #{COUNTER_NOTE}"
    report.check("inbox ##{channel.inbox&.id}: the channel is not awaiting reauthorization", !latched,
                 latched ? 'REAUTHORIZATION REQUIRED' : 'false', note: REAUTH_NOTE)
  end

  def app_secret_check(config)
    channel_secret = config[:app_secret].presence
    installation = stored_config('WHATSAPP_APP_SECRET')
    present = channel_secret.present? || installation.present?
    report.check(
      'a Meta app secret is configured (installation or channel)',
      present,
      "installation #{installation.present? ? 'set' : 'BLANK'}, channel #{channel_secret.present? ? 'set' : 'blank'}",
      note: 'Meta signs every WhatsApp Cloud webhook with the app secret, and the controller rejects a payload no ' \
            "configured secret verifies. #{SIGNATURE_FAILURE_NOTE}"
    )
  end

  def verify_token_check
    token = stored_config('WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN')
    report.check(
      'WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN is configured',
      token.present?,
      token.present? ? 'set' : 'BLANK',
      note: 'Only the app-level callback (/webhooks/whatsapp with no number in the path) uses it, which is where ' \
            'template-status webhooks arrive. A blank value fails that handshake.'
    )
  end

  def identity_rows(channel, config)
    inbox = channel.inbox
    [
      ['ids', "account_id=#{inbox&.account_id} inbox_id=#{inbox&.id} channel_id=#{channel.id}"],
      ['account', "#{inbox&.account&.name.inspect} status=#{inbox&.account&.status}"],
      ['inbox name', inbox&.name.inspect],
      ['provider', channel.provider.inspect],
      ['stored phone_number', report.mask_phone(channel.phone_number)],
      ['source', config[:source].presence || '<not recorded>'],
      ['coexistence indicators', coexistence_hint(config).presence || 'none recorded in provider_config'],
      ['provider_config keys', config.keys.sort.join(', ')]
    ]
  end

  # Presence and provenance, never a value — not even masked. A masked credential still leaks its length, and
  # nothing in this report needs it: the operator is being asked "is it configured, and from where".
  def credential_rows(config)
    [
      ['access token (provider_config.api_key)', config[:api_key].present? ? 'present' : 'ABSENT'],
      ['channel-level app_secret', config[:app_secret].present? ? 'present' : 'blank'],
      ['channel webhook_verify_token', config[:webhook_verify_token].present? ? 'present' : 'blank'],
      ['credential source', config[:source].presence || '<not recorded>']
    ]
  end

  def coexistence_hint(config)
    config.keys.select { |key| key.to_s.match?(/coexist|smb|business_app|platform/i) }
          .map { |key| "#{key}=#{config[key].inspect}" }.join(' ')
  end
end
