# Installation-wide settings of the Lynomia Salla app (Super Admin → Settings → Salla). Merchant tokens never live here:
# they are each store's encrypted credentials (docs/commerce/11-salla-auth-and-token-lifecycle.md).
#
# `enabled?` is the installation's provider switch. It is separate from the `lynomia_commerce` plan feature, which
# decides which accounts have Commerce at all.
module Commerce::Salla::Config
  INSTALL_URL = 'https://s.salla.sa/apps/install/%<app_id>s'.freeze

  # Read from the config cache directly: GlobalConfigService.load re-creates the row and clears the whole config cache on
  # every read of a false value, and this is checked on every Commerce request.
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value('SALLA_ENABLED')) == true
  end

  def self.app_id = required('SALLA_APP_ID')

  def self.client_id = required('SALLA_CLIENT_ID')

  def self.client_secret = required('SALLA_CLIENT_SECRET')

  # nil until configured: without it no Salla event can be verified, so none is accepted.
  def self.webhook_secret = GlobalConfigService.load('SALLA_WEBHOOK_SECRET', nil).presence

  def self.install_url = format(INSTALL_URL, app_id: ERB::Util.url_encode(app_id))

  # A value the running flow needs: missing means the app was set up incompletely, so it fails loudly.
  def self.required(name)
    GlobalConfigService.load(name, nil).presence || raise(KeyError, "#{name} is not configured")
  end
  private_class_method :required
end
