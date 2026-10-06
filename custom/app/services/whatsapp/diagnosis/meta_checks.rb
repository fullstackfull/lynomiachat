# frozen_string_literal: true

# The live half of a Lynomia WhatsApp diagnosis: what Meta says, read through the installation's existing
# Whatsapp::FacebookApiClient. It fills the META IDENTITY, AUTH, WABA SUBSCRIPTION and WEBHOOK sections.
#
# Every call here is a GET. Nothing subscribes, registers, rotates or deletes — P5 Part T forbids it, and a
# diagnosis that mutates the thing it is diagnosing is worthless anyway.
class Whatsapp::Diagnosis::MetaChecks
  # The webhook fields Lynomia's own inbound path needs, taken from the client so the two cannot drift. `messages`
  # carries customer messages and delivery statuses; `smb_message_echoes` carries the Business-App side of a
  # Coexistence number; `message_template_status_update` carries Meta's template approvals.
  REQUIRED_FIELDS = Whatsapp::FacebookApiClient::WEBHOOK_DEFAULT_FIELDS

  PHONE_FIELDS = 'display_phone_number,verified_name,quality_rating,code_verification_status,status,platform_type,' \
                 'name_status,messaging_limit_tier,is_official_business_account'

  TOKEN_PERMISSIONS = %w[whatsapp_business_messaging whatsapp_business_management].freeze

  NO_SUBSCRIPTION_NOTE = 'This is the single most common cause of "inbound never arrives". With no subscribed app, ' \
                         'Meta has nowhere to deliver and never calls the callback URL at all. The existing fix is ' \
                         'Whatsapp::FacebookApiClient#subscribe_app_to_waba — do not hand-roll a subscription.'

  # The field list Meta reported for the subscribed app, handed to Whatsapp::Diagnosis::WebhookChecks so
  # the WEBHOOK section can compare it without repeating the read.
  attr_reader :subscribed_fields

  def initialize(report)
    @report = report
    @subscribed_fields = nil
  end

  # ---- META IDENTITY -------------------------------------------------------------------------------------------

  def identity(channel, config)
    report.heading("META IDENTITY — inbox ##{channel.inbox&.id}")
    report.say "Graph API version in use: #{api_version} (default #{Whatsapp::FacebookApiClient::DEFAULT_API_VERSION})"
    report.rows(
      [
        ['WABA (business_account_id)', config[:business_account_id].presence || '<blank>'],
        ['phone_number_id', config[:phone_number_id].presence || '<blank>']
      ]
    )
    client = client_for(config, 'META IDENTITY reads') or return
    phone_number(client, config[:phone_number_id])
  end

  # ---- AUTH (Meta's verdict on the credential; the local half is in LocalChecks#auth) --------------------------

  def auth(config)
    client = client_for(config, 'token validity and scopes') or return

    token_state(client, config[:api_key])
    permissions(client)
  end

  # ---- WABA SUBSCRIPTION ---------------------------------------------------------------------------------------

  def waba_subscription(channel, config)
    report.heading("WABA SUBSCRIPTION — inbox ##{channel.inbox&.id}")
    waba_id = config[:business_account_id]
    return report.blocked('WABA subscription reads', 'provider_config has no business_account_id') if waba_id.blank?

    client = client_for(config, 'WABA subscription reads') or return

    subscribed_apps(client, waba_id)
    templates(client, waba_id)
  end

  private

  attr_reader :report

  def api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', Whatsapp::FacebookApiClient::DEFAULT_API_VERSION)

  # One client per token, so a channel's four sections share a single object. A blank token is reported once per
  # section rather than raised, because the rest of the section may still have something to say.
  def client_for(config, label)
    token = config[:api_key]
    return report.blocked(label, 'provider_config has no api_key on this channel') && nil if token.blank?

    @client_cache ||= {}
    @client_cache[token] ||= Whatsapp::FacebookApiClient.new(token)
  end

  def token_state(client, token)
    data = report.read('token debug (validity, scopes, expiry)') { client.debug_token(token) }
    return if data.nil?

    info = data['data'] || {}
    report.rows(
      [
        ['app_id', info['app_id']],
        ['type', info['type']],
        ['expires_at', report.format_unix(info['expires_at'])],
        ['data_access_expires_at', report.format_unix(info['data_access_expires_at'])],
        ['scopes', Array(info['scopes']).join(', ')]
      ],
      indent: '  '
    )
    report.check('the access token is valid', info['is_valid'] == true, info['is_valid'].inspect,
                 note: 'An expired or invalidated token fails every send and every read.')
  end

  def permissions(client)
    data = report.read('token permissions (/me/permissions)') { client.fetch_permissions }
    return if data.nil?

    granted = Array(data['data']).select { |entry| entry['status'] == 'granted' }.pluck('permission')
    report.say "  granted: #{granted.join(', ')}"
    TOKEN_PERMISSIONS.each do |needed|
      report.check("permission #{needed} is granted", granted.include?(needed),
                   granted.include?(needed) ? 'granted' : 'MISSING')
    end
  end

  def phone_number(client, phone_number_id)
    if phone_number_id.blank?
      report.blocked('phone number state', 'provider_config has no phone_number_id')
      return
    end

    data = report.read("phone number state (/#{phone_number_id})") do
      client.fetch_phone_number(phone_number_id, fields: PHONE_FIELDS)
    end
    report_phone_number(data) if data
  end

  def report_phone_number(data)
    report.rows(phone_rows(data), indent: '  ')
    report.check('the phone number is CONNECTED at Meta', data['status'].to_s.upcase == 'CONNECTED',
                 data['status'].inspect,
                 note: 'A number that is not CONNECTED cannot send or receive through the Cloud API.')
    return if data['platform_type'].blank?

    report.say "  platform_type is reported, so this number's Coexistence state is visible here: " \
               "#{data['platform_type'].inspect}"
  end

  def phone_rows(data)
    [
      ['display_phone_number', report.mask_phone(data['display_phone_number'])],
      ['verified_name', data['verified_name'].inspect],
      ['name_status', data['name_status'].inspect],
      ['status', data['status'].inspect],
      ['code_verification_status', data['code_verification_status'].inspect],
      ['quality_rating', data['quality_rating'].inspect],
      ['messaging_limit_tier', data['messaging_limit_tier'].inspect],
      ['platform_type', data['platform_type'].inspect],
      ['official_business_account', data['is_official_business_account'].inspect]
    ]
  end

  # P5 Part C. The primary suspect for "inbound never arrives".
  def subscribed_apps(client, waba_id)
    data = report.read("WABA app subscription (/#{waba_id}/subscribed_apps)") { client.fetch_subscribed_apps(waba_id) }
    return if data.nil?

    apps = Array(data['data'])
    report.say "  subscribed apps: #{apps.size}"
    apps.each { |entry| subscribed_app(entry) }
    report.check('at least one app is subscribed to this WABA', apps.any?,
                 apps.any? ? "#{apps.size} app(s)" : 'NONE', note: NO_SUBSCRIPTION_NOTE)
    configured_app_is_subscribed(apps)
  end

  # The app id is printed in full on purpose: it is a public identifier, not a credential, and an operator cannot
  # compare it against WHATSAPP_APP_ID masked. The app SECRET is never read here.
  def subscribed_app(entry)
    app = entry['whatsapp_business_api_data'] || {}
    report.say "    app_id=#{app['id']} name=#{app['name'].inspect}"
    fields = Array(entry['subscribed_fields'] || app['subscribed_fields'])
    report.say "    subscribed_fields: #{fields.presence&.join(', ') || '<not reported by this endpoint>'}"
    @subscribed_fields = fields if fields.present?
  end

  def configured_app_is_subscribed(apps)
    configured = GlobalConfigService.load('WHATSAPP_APP_ID', nil)
    return if configured.blank? || apps.empty?

    ids = apps.map { |entry| (entry['whatsapp_business_api_data'] || {})['id'].to_s }
    report.check("the configured app (#{configured}) is the subscribed one", ids.include?(configured.to_s),
                 "subscribed: #{ids.join(', ')}",
                 note: "A different Meta app owns the subscription, so webhooks are signed with that app's secret " \
                       "and delivered to its callback URL, not this installation's.")
  end

  # P5 Part H needs an approved template to reach a contact whose window is closed.
  def templates(client, waba_id)
    data = report.read("templates owned by this WABA (/#{waba_id}/message_templates)") do
      client.fetch_message_templates(waba_id)
    end
    return if data.nil?

    all = Array(data['data'])
    approved = all.select { |template| template['status'].to_s.upcase == 'APPROVED' }
    report.say "  templates: #{all.size} total, #{approved.size} APPROVED"
    approved.first(10).each { |t| report.say "    APPROVED #{t['name']} (#{t['language']}, #{t['category']})" }
    report.check('at least one APPROVED template exists to open a new conversation', approved.any?,
                 "#{approved.size} approved",
                 note: 'Reaching a contact outside the 24-hour window requires an approved template. With none, a ' \
                       'brand-new contact cannot be contacted at all — which is correct WhatsApp policy, not a defect.')
  end
end
