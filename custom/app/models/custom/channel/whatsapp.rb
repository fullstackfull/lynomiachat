# Lynomia Campaigns (docs/campaigns/02-recipients.md): a campaign recipient that fails needs Meta's own
# reason, and the OSS `delegate :send_template, to: :provider_service` (app/models/channel/whatsapp.rb:147)
# drops the provider instance along with its error. Sending through the provider once and keeping it
# lets Custom::Whatsapp::Providers::BaseService#last_error reach the recipient.
module Custom::Channel::Whatsapp
  attr_reader :last_provider_error

  def send_template(...)
    provider = provider_service
    response = provider.send_template(...)
    @last_provider_error = provider.last_error
    response
  end
end
