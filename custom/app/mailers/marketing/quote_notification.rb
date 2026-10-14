# Where a quote request notification goes.
#
# INSTALLATION CONFIGURATION, NO FALLBACK, copied deliberately from PlatformSupport::SupportAlias
# (custom/app/mailers/platform_support/support_alias.rb) which paid for the shape: there is no built-in
# address, no `sales@`-anything and no ENV default. Until an operator sets one, this module answers "not
# configured" and no notification is sent.
#
# WHY NOT REUSE THE PLATFORM SUPPORT ALIAS. That address is where a customer's support ticket goes. A sales
# enquiry from somebody with no account is a different conversation for, in most organisations, a different
# person -- and quietly routing leads into the support queue is the kind of surprise an operator discovers
# weeks later.
#
# AN UNSET ADDRESS LOSES NO LEAD. SiteQuoteRequest is written before the mail is queued and is listed in
# Super Admin, so a missing address costs the alert and not the customer.
module Marketing::QuoteNotification
  KEY = 'MARKETING_QUOTE_NOTIFICATION_EMAIL'.freeze

  def self.configured?
    address.present?
  end

  def self.address
    GlobalConfigService.load(KEY, nil).presence
  end
end
