# frozen_string_literal: true

# Everything a Lynomia WhatsApp diagnosis can answer without calling Meta: the installation's own configuration,
# the worker that has to process a webhook, the channel's recorded identity, and what the database says about
# inbound traffic. P5 Parts A, N, P, R and S.
#
# Reads only. Nothing here writes to the database.
class Whatsapp::Diagnosis::LocalChecks
  SIGNATURE_FAILURE_NOTE = 'Webhooks::WhatsappController#verify_meta_signature! answers 401 and drops the payload. ' \
                           'This is the most commonly missed cause of "inbound never arrives", and it is silent ' \
                           'apart from a Rails.logger.warn.'

  # The highest-value check in this whole report, and it needs no network call.
  #
  # Webhooks::WhatsappEventsJob#channel_is_inactive? (app/jobs/webhooks/whatsapp_events_job.rb:148-156) returns
  # true when `reauthorization_required? && embedded_signup_channel?`, and #perform (:11-14) then returns after a
  # single Rails.logger.warn -- no raise, no retry, no Sentry. Sidekiq records the job as a success and the
  # controller has already answered Meta 200 OK, so Meta never retries. Every inbound webhook for the channel is
  # discarded, while outbound keeps working because sending never consults this flag.
  #
  # The flag is a Redis key set with no expiry (Reauthorizable#prompt_reauthorization! ->
  # Redis::Alfred.set(key, true), no `ex:`). Nothing clears it but #reauthorized!, which runs only when someone
  # completes the reauthorization flow in the UI. Two ways in: AUTHORIZATION_ERROR_THRESHOLD = 2 authorization
  # errors (a media-download 401 in incoming_message_whatsapp_cloud_service.rb:18 is one), or
  # Channel::Whatsapp#setup_webhooks (app/models/channel/whatsapp.rb:158-163), which rescues StandardError and
  # calls prompt_reauthorization! instead of re-raising -- so a webhook-setup failure at connect time latches the
  # channel while the API still answers success.
  REAUTH_NOTE = 'This single flag stops ALL inbound for this channel while outbound keeps working, which is ' \
                'exactly the reported shape. It is a Redis key with no expiry, cleared only by completing the ' \
                'reauthorization flow in the UI (Settings -> Inboxes -> this inbox). Clearing it is the fix ONLY ' \
                'if the condition that set it is gone -- check the token and the media downloads first, or it ' \
                'will latch again on the next two authorization errors.'

  def initialize(report)
    @report = report
  end

  def installation_config
    report.heading('INSTALLATION CONFIGURATION (Lynomia side)')
    report.say "Graph API version in use: #{api_version} (default #{Whatsapp::FacebookApiClient::DEFAULT_API_VERSION})"
    app_secret_check
    verify_token_check
    report.rows(
      [
        ['WHATSAPP_APP_ID', GlobalConfigService.load('WHATSAPP_APP_ID', nil).presence || '<blank>'],
        ['INACTIVE_WHATSAPP_NUMBERS', inactive_numbers.join(', ').presence || '<blank>'],
        ['FRONTEND_URL', ENV.fetch('FRONTEND_URL', '<unset>')]
      ]
    )
    report.say 'Meta must be able to reach <FRONTEND_URL>/webhooks/whatsapp/<number> from the public internet.'
  end

  def worker
    report.heading('QUEUE AND WORKER (P5 Part P)')
    queue = Webhooks::WhatsappEventsJob.new.queue_name
    configured = sidekiq_queues
    report.say "Webhooks::WhatsappEventsJob queue: #{queue}"
    report.say "queues in config/sidekiq.yml: #{configured.join(', ')}"
    report.check(
      "the job's queue is consumed by the worker config",
      configured.include?(queue),
      configured.include?(queue) ? 'listed' : 'NOT LISTED',
      note: 'A job enqueued to a queue no worker consumes is invisible and looks exactly like "Meta never called us".'
    )
    sidekiq_runtime
  end

  def identity(channel, config)
    report.heading("CHANNEL IDENTITY (P5 Part A) — inbox ##{channel.inbox&.id}")
    report.rows(identity_rows(channel, config))
    report.rows(credential_rows(config))
    reauthorization_check(channel, config)
    signature_secret_check(channel, config)
    inactive_number_check(channel)
  end

  # P5 Part F: the JOB_FAILURE / INBOX_ROUTING class that looks exactly like META_SUBSCRIPTION from outside.
  def reauthorization_check(channel, config)
    latched = channel.reauthorization_required?
    embedded = config[:source] == 'embedded_signup'
    report.say "authorization_error_count: #{channel.authorization_error_count} " \
               "(threshold #{channel.class::AUTHORIZATION_ERROR_THRESHOLD})"
    report.say "reauthorization_required: #{latched}, source is embedded_signup: #{embedded}"
    report.check(
      "inbox ##{channel.inbox&.id}: the channel is NOT latched into reauthorization-required",
      !(latched && embedded),
      latched && embedded ? 'LATCHED — every inbound webhook is being dropped' : "latched=#{latched} embedded=#{embedded}",
      note: REAUTH_NOTE
    )
    return unless latched && !embedded

    report.say '  the flag is set but this is not an embedded-signup channel, so the job does not drop webhooks ' \
               'for it (the guard is deliberately narrow). It still means an authorization error was recorded.'
  end

  private

  attr_reader :report

  def api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', Whatsapp::FacebookApiClient::DEFAULT_API_VERSION)

  def inactive_numbers
    @inactive_numbers ||= GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s.split(',').map(&:strip)
  end

  def app_secret_check
    secret = GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    report.check(
      'WHATSAPP_APP_SECRET is configured',
      secret.present?,
      secret.present? ? "set, #{report.mask(secret)}" : 'BLANK',
      note: 'Meta signs every WhatsApp Cloud webhook with the app secret, and the controller rejects a payload no ' \
            "configured secret verifies. A channel-level app_secret also satisfies it. #{SIGNATURE_FAILURE_NOTE}"
    )
  end

  def verify_token_check
    token = GlobalConfigService.load('WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN', nil)
    report.check(
      'WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN is configured',
      token.present?,
      token.present? ? "set, #{report.mask(token)}" : 'BLANK',
      note: 'Only the app-level callback (/webhooks/whatsapp with no number in the path) uses it, which is where ' \
            'template-status webhooks arrive. A blank value fails that handshake.'
    )
  end

  def sidekiq_runtime
    require 'sidekiq/api'
    sidekiq_stats
    processes = Sidekiq::ProcessSet.new
    report.check('at least one Sidekiq process is alive', processes.size.positive?, "#{processes.size} process(es)",
                 note: 'Webhooks would be accepted with 200 and never processed.')
    processes.each { |process| report.say "  process queues: #{Array(process['queues']).join(', ')}" }
    dead_whatsapp_jobs
  rescue StandardError => e
    report.blocked('Sidekiq statistics', "#{e.class.name}: #{e.message.to_s[0, 120]}")
  end

  def sidekiq_stats
    stats = Sidekiq::Stats.new
    report.say "sidekiq processed=#{stats.processed} failed=#{stats.failed} enqueued=#{stats.enqueued} " \
               "retry=#{Sidekiq::RetrySet.new.size} dead=#{Sidekiq::DeadSet.new.size}"
  end

  def dead_whatsapp_jobs
    dead = Sidekiq::DeadSet.new.select { |job| job.klass.to_s.include?('Whatsapp') }
    report.say "dead WhatsApp jobs: #{dead.size}"
    dead.first(3).each { |job| report.say "  dead: #{job.klass} — #{job['error_message'].to_s[0, 160]}" }
  end

  def identity_rows(channel, config)
    inbox = channel.inbox
    [
      ['ids', "account_id=#{inbox&.account_id} inbox_id=#{inbox&.id} channel_id=#{channel.id}"],
      ['inbox name', inbox&.name.inspect],
      ['provider', channel.provider.inspect],
      ['stored phone_number', report.mask_phone(channel.phone_number)],
      ['business_account_id (WABA)', config[:business_account_id].presence || '<blank>'],
      ['phone_number_id', config[:phone_number_id].presence || '<blank>'],
      ['provider_config keys', config.keys.sort.join(', ')],
      ['source', config[:source].presence || '<not recorded>']
    ]
  end

  def credential_rows(config)
    [
      ['access token', report.mask(config[:api_key])],
      ['channel-level app_secret', masked_or_blank(config[:app_secret])],
      ['webhook_verify_token', masked_or_blank(config[:webhook_verify_token])],
      ['coexistence indicators', coexistence_hint(config).presence || 'none recorded in provider_config']
    ]
  end

  def masked_or_blank(value) = value.present? ? report.mask(value) : '<blank>'

  def signature_secret_check(channel, config)
    available = config[:app_secret].present? || GlobalConfigService.load('WHATSAPP_APP_SECRET', nil).present?
    report.check(
      "inbox ##{channel.inbox&.id}: a secret exists to verify Meta's webhook signature",
      available,
      available ? 'available' : 'NO SECRET AVAILABLE',
      note: SIGNATURE_FAILURE_NOTE
    )
  end

  def inactive_number_check(channel)
    listed = inactive_numbers.include?(channel.phone_number)
    report.check(
      "inbox ##{channel.inbox&.id}: the number is NOT on the inactive list",
      !listed,
      listed ? 'LISTED AS INACTIVE' : 'not listed',
      note: 'Webhooks::WhatsappController answers 422 for a number on INACTIVE_WHATSAPP_NUMBERS and never enqueues ' \
            'the payload.'
    )
  end

  def coexistence_hint(config)
    config.keys.select { |key| key.to_s.match?(/coexist|smb|business_app|platform/i) }
          .map { |key| "#{key}=#{config[key].inspect}" }.join(' ')
  end

  def sidekiq_queues
    path = Rails.root.join('config/sidekiq.yml')
    return [] unless path.exist?

    yaml = YAML.safe_load(ERB.new(path.read).result, aliases: true, permitted_classes: [Symbol])
    Array(yaml[:queues] || yaml['queues']).map { |queue| Array(queue).first.to_s }
  rescue StandardError
    []
  end
end
