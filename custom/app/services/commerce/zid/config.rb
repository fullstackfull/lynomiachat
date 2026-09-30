# Installation-wide settings of the Lynomia Zid app (Super Admin → Settings → Zid). Merchant tokens never live here:
# they are each store's encrypted credentials (docs/commerce/14-zid-oauth-and-tokens.md).
#
# `enabled?` is the installation's provider switch. It is separate from the `lynomia_commerce` plan feature, which
# decides which accounts have Commerce at all; both are required to connect or read a Zid store.
module Commerce::Zid::Config
  CALLBACK_PATH = '/commerce/zid/callback'.freeze

  # Read from the config cache directly, like Commerce::Salla::Config.enabled?: it is checked on every Commerce request.
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value('ZID_ENABLED')) == true
  end

  def self.client_id = required('ZID_CLIENT_ID')

  def self.client_secret = required('ZID_CLIENT_SECRET')

  # The callback URL registered for the app in the Zid Partner Dashboard. Zid requires the authorize, token and refresh
  # requests to send exactly this value, so it follows the installation's own URL instead of a separate setting.
  def self.redirect_uri = "#{ENV.fetch('FRONTEND_URL')}#{CALLBACK_PATH}"

  # A value the running flow needs: missing means the app was set up incompletely, so it fails loudly.
  def self.required(name)
    GlobalConfigService.load(name, nil).presence || raise(KeyError, "#{name} is not configured")
  end
  private_class_method :required
end
