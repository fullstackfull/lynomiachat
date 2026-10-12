# What references a shared audience. Automation rules reference it through a `contact_audience` condition
# (docs/automation/02-shared-audiences.md), one-off campaigns through an `Audience` entry of their audience
# (docs/campaigns/03-audience-dependency.md). Both store only the audience id, never its conditions, so this is what
# keeps a referenced audience from being deleted or made personal.
module Audience::Usage
  CONDITION_KEY = 'contact_audience'.freeze

  def self.rules(custom_filter)
    candidates = custom_filter.account.automation_rules.where('conditions @> ?', [{ attribute_key: CONDITION_KEY }].to_json)
    candidates.select do |rule|
      rule.conditions.any? do |condition|
        condition['attribute_key'] == CONDITION_KEY && Array(condition['values']).map(&:to_s).include?(custom_filter.id.to_s)
      end
    end
  end

  # The campaigns still to send (scheduled, sending, or blocked waiting for a capability): a completed campaign
  # resolved its recipients when it was sent, and deleting a campaign is how a scheduled one is cancelled.
  #
  # `blocked` is included for the reason the others are (DECISION 6): a blocked campaign has not sent and will
  # send when it is re-activated, so its audience is still in use and must not be deletable out from under it.
  def self.campaigns(custom_filter)
    custom_filter.account.campaigns.one_off.where(campaign_status: %i[active processing blocked])
                 .where('audience @> ?', [{ type: Custom::CampaignAudience::AUDIENCE_TYPE, id: custom_filter.id }].to_json)
  end
end
