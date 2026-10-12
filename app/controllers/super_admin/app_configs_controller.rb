class SuperAdmin::AppConfigsController < SuperAdmin::ApplicationController
  # AUDIT_LOG_RETENTION_DAYS is Lynomia's (DECISION 5). Without it here the key is in config/installation_config.yml
  # and read on every sweep, but `create` drops any key not in this list, so an operator had no way to change the
  # retention window from this form at all -- which is the surface the decision's documentation points at. Added
  # alongside the Lynomia COMMERCE_CONFIGS below rather than through an overlay, following this file's own
  # precedent for Lynomia keys.
  GENERAL_CONFIGS = %w[ENABLE_ACCOUNT_SIGNUP FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS WEBHOOK_TIMEOUT MAXIMUM_FILE_UPLOAD_SIZE
                       WIDGET_TOKEN_EXPIRY AUDIT_LOG_RETENTION_DAYS].freeze
  META_INCIDENT_CONFIGS = %w[DISABLE_META_INBOX_CREATION DISABLE_META_MESSAGE_SENDING].freeze
  before_action :set_config
  before_action :allowed_configs
  before_action :keep_stored_secrets, only: :create
  def show
    # ref: https://github.com/rubocop/rubocop/issues/7767
    # rubocop:disable Style/HashTransformValues
    @app_config = InstallationConfig.where(name: @allowed_configs)
                                    .pluck(:name, :serialized_value)
                                    .map { |name, serialized_value| [name, serialized_value['value']] }
                                    .to_h
    # rubocop:enable Style/HashTransformValues
    @installation_configs = ConfigLoader.new.general_configs.each_with_object({}) do |config_hash, result|
      result[config_hash['name']] = config_hash.except('name')
    end
  end

  def create
    errors = []
    params['app_config'].each do |key, value|
      break if errors.any?
      next unless @allowed_configs.include?(key)

      i = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      i.value = value
      errors.concat(i.errors.full_messages) unless i.save
    end

    if errors.any?
      redirect_to super_admin_app_config_path(config: @config), alert: errors.join(', ')
    else
      redirect_to super_admin_settings_path, flash: success_flash
    end
  end

  private

  def set_config
    @config = params[:config] || 'general'
  end

  # Lynomia: show.html.erb never renders a stored secret, so a blank secret field means "keep the stored value".
  def keep_stored_secrets
    params['app_config'].delete_if { |key, value| value.blank? && InstallationConfig.secret_names.include?(key) }
  end

  COMMERCE_CONFIGS = %w[
    COMMERCE_ACTIONS_ENABLED WOOCOMMERCE_ACTIONS_ENABLED SALLA_ACTIONS_ENABLED ZID_ACTIONS_ENABLED SHOPIFY_COMMERCE_ACTIONS_ENABLED
    COMMERCE_RECOVERY_ENABLED SALLA_RECOVERY_ENABLED ZID_RECOVERY_ENABLED SHOPIFY_COMMERCE_RECOVERY_ENABLED COMMERCE_RECOVERY_COOLDOWN_HOURS
  ].freeze

  def allowed_configs
    general_configs = GENERAL_CONFIGS + (ChatwootApp.chatwoot_cloud? ? META_INCIDENT_CONFIGS : [])

    mapping = {
      'facebook' => %w[FB_APP_ID FB_VERIFY_TOKEN FB_APP_SECRET IG_VERIFY_TOKEN FACEBOOK_API_VERSION INSTAGRAM_MESSENGER_API_VERSION
                       ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT],
      'salla' => %w[SALLA_ENABLED SALLA_APP_ID SALLA_CLIENT_ID SALLA_CLIENT_SECRET SALLA_WEBHOOK_SECRET],
      'zid' => %w[ZID_ENABLED ZID_CLIENT_ID ZID_CLIENT_SECRET],
      'shopify_commerce' => %w[SHOPIFY_COMMERCE_ENABLED SHOPIFY_COMMERCE_CLIENT_ID SHOPIFY_COMMERCE_CLIENT_SECRET],
      'commerce' => COMMERCE_CONFIGS,
      'microsoft' => %w[AZURE_APP_ID AZURE_APP_SECRET],
      'email' => %w[MAILER_INBOUND_EMAIL_DOMAIN ACCOUNT_EMAILS_LIMIT ACCOUNT_EMAILS_PLAN_LIMITS],
      'linear' => %w[LINEAR_CLIENT_ID LINEAR_CLIENT_SECRET],
      'slack' => %w[SLACK_CLIENT_ID SLACK_CLIENT_SECRET SLACK_SIGNING_SECRET],
      'instagram' => %w[INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN INSTAGRAM_API_VERSION ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT],
      'tiktok' => %w[TIKTOK_APP_ID TIKTOK_APP_SECRET TIKTOK_API_VERSION],
      'whatsapp_embedded' => %w[WHATSAPP_APP_ID WHATSAPP_APP_SECRET WHATSAPP_CONFIGURATION_ID WHATSAPP_API_VERSION],
      'notion' => %w[NOTION_CLIENT_ID NOTION_CLIENT_SECRET],
      'google' => %w[GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET GOOGLE_OAUTH_REDIRECT_URI ENABLE_GOOGLE_OAUTH_LOGIN],
      'captain' => %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_MODEL CAPTAIN_OPEN_AI_ENDPOINT]
    }

    @allowed_configs = mapping.fetch(@config, general_configs)
  end

  def success_notice
    message = "#{@config.titleize} settings updated successfully"
    return message unless restart_required_config_saved?

    "#{message.delete_suffix('.')}. Restart Chatwoot web and worker processes to apply this change everywhere."
  end

  def success_flash
    restart_required_config_saved? ? { success: success_notice } : { notice: success_notice }
  end

  def restart_required_config_saved?
    params.fetch('app_config', {}).keys.intersect?(InstallationConfig::RESTART_REQUIRED_CONFIG_KEYS)
  end
end

SuperAdmin::AppConfigsController.prepend_mod_with('SuperAdmin::AppConfigsController')
