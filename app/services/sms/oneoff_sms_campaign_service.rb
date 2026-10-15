class Sms::OneoffSmsCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" if campaign.inbox.inbox_type != 'Sms' || !campaign.one_off?
    raise 'Completed Campaign' if campaign.completed?

    process_audience
    campaign.completed!
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def process_audience
    campaign.audience_contacts.each do |contact|
      next if contact.phone_number.blank?

      # THE FINAL ELIGIBILITY CHECK, against live rows rather than the audience that was
      # resolved when the scheduler dispatched this campaign. Between then and now the
      # shopper can reply STOP, an agent can block them, the provider can report the number
      # dead, an operator can revoke the integration or throw the kill switch; this is the
      # last moment any of that can be honoured. See Campaigns::SendGuard for the precedence.
      #
      # It paces as well as permits, and in that order -- the throttle SLEEPS, so a refusal
      # landing during the wait has to be read after it, not before.
      next if Campaigns::SendGuard.clear_to_send(contact, campaign, :sms)

      content = Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
      # The paid allowance, taken on the line before the message goes -- not in the gate
      # above, which runs before every check that can still stop this recipient. See
      # Campaigns::SendGuard.spend.
      next if Campaigns::SendGuard.spend(campaign)

      send_message(to: contact.phone_number, content: content)
    end
  end

  def send_message(to:, content:)
    channel.send_text_message(to, content)
  rescue StandardError => e
    Rails.logger.error("[SMS Campaign #{campaign.id}] Failed to send to #{to}: #{e.message}")
  end
end
