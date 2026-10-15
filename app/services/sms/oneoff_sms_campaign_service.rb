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
      next if Campaigns::SendGuard.refusal(contact, campaign, :sms)

      content = Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
      send_message(to: contact.phone_number, content: content)
    end
  end

  def send_message(to:, content:)
    channel.send_text_message(to, content)
  rescue StandardError => e
    Rails.logger.error("[SMS Campaign #{campaign.id}] Failed to send to #{to}: #{e.message}")
  end
end
