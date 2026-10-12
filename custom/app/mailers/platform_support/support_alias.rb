# The Lynomia support alias: the one address every OPERATOR-side Platform Support email goes to.
#
# INSTALLATION CONFIGURATION, NOT CODE, AND NO FALLBACK OF ANY KIND. There is no built-in address, no
# `support@`-anything, no ENV default and no seed. Until an operator sets it, this module answers "not
# configured" and `PlatformSupport::TicketMailer` sends no operator email at all
# (docs/platform-support/12-refresh-against-product-refinement.md §11.2).
#
# WHY NOT `Account#support_email`. That reader is a fallback chain ending in the account's own address, and it
# is the customer's address, not Lynomia's. An operator alert addressed to the customer's support inbox is the
# exact failure mode this file exists to make impossible. The shape copied instead is
# `Commerce::Salla::Config.required` (custom/app/services/commerce/salla/config.rb:27-29): one read, no
# substitution, and a loud `KeyError` when a flow that needs the value runs without it.
#
# WHY IT LIVES UNDER `custom/app/mailers`. It is read by exactly one consumer, the mailer beside it, and
# `custom/app/services/platform_support/*.rb` belongs to another agent in this phase's file split (§8). Being
# next to its only caller is also the honest place for it.
#
# WHAT AN OPERATOR MUST DO. Set `PLATFORM_SUPPORT_OPERATOR_ALIAS` in Super Admin → Installation Configs. The
# key needs a `config/installation_config.yml` entry to appear in that list; that file is owned by nobody in
# this split, so the entry is an integration item and the value is read correctly with or without it.
module PlatformSupport::SupportAlias
  KEY = 'PLATFORM_SUPPORT_OPERATOR_ALIAS'.freeze

  # The predicate every caller asks first -- including the staff desk, which renders "no support alias is
  # configured" from it rather than discovering the gap when an email silently fails to arrive.
  def self.configured?
    address.present?
  end

  def self.address
    GlobalConfigService.load(KEY, nil).presence
  end

  # For a flow that has already established the alias is configured. Reaching this with nothing set means the
  # value disappeared between the check and the send, which is a deployment problem and not something to paper
  # over with an invented recipient.
  def self.address!
    address || raise(KeyError, "#{KEY} is not configured")
  end
end
