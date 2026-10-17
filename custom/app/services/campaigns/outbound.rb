# frozen_string_literal: true

# THE STOP BUTTON FOR CAMPAIGN SENDING, read immediately before each provider call.
#
# WHY IT IS CHECKED PER RECIPIENT AND NOT ONCE PER CAMPAIGN. A campaign is one job iterating
# its whole audience; a switch consulted when the job starts is a switch that cannot stop
# anything once the job is running, which is the only moment anybody reaches for it. Throwing
# it must stop the send that is happening now, not the next one.
#
# TWO LEVELS, BOTH FAIL-SAFE. The installation-wide switch stops every account -- the lever an
# operator pulls when a provider incident or a mistake is unfolding. The per-account switch
# stops one. Either being on is enough; neither can re-enable what the other stopped.
#
# A MISSING OR UNREADABLE SWITCH READS AS "NOT HALTED", which is the one default that is not
# fail-closed, and it is deliberate. This is an emergency brake, not an authorization: making
# an unreachable Redis mean "stop all messaging for everyone" would turn a cache blip into an
# outage. Authorization is consent, and consent fails closed in Campaigns::SendGuard.
module Campaigns::Outbound
  INSTALLATION_KEY = 'CAMPAIGN_SENDING_HALTED'
  ACCOUNT_KEY = 'campaign_sending_halted'

  module_function

  def halted?(account = nil)
    installation_halted? || account_halted?(account)
  end

  def installation_halted?
    ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value(INSTALLATION_KEY)) == true
  rescue StandardError
    false
  end

  # Per account, kept in the account's own settings so it travels with the account and needs
  # no new table. Read through `settings` rather than a feature flag because the feature flag
  # bitmask is at its ceiling (Featurable raises past 63) and because this is an operational
  # state, not a sellable capability.
  def account_halted?(account)
    return false if account.nil?

    ActiveModel::Type::Boolean.new.cast(account.settings[ACCOUNT_KEY]) == true
  rescue StandardError
    false
  end
end
