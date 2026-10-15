class Campaigns::CampaignConversationBuilder
  pattr_initialize [:contact_inbox_id!, :campaign_display_id!, :conversation_additional_attributes, :custom_attributes]

  def perform
    @contact_inbox = ContactInbox.find(@contact_inbox_id)
    @campaign = @contact_inbox.inbox.campaigns.find_by!(display_id: campaign_display_id)
    # A CANCELLED CAMPAIGN MESSAGES NOBODY, and this is the point that decides it for an
    # ongoing one. Cancelling is honoured for a one-off by Campaigns::SendGuard, per
    # recipient inside the send loop; an ongoing campaign has no loop and no scheduler --
    # the visitor's own `campaign_triggered` event arrives here and a conversation is
    # created. Without this the cancel endpoint answered 200 with campaign_status
    # "cancelled" while every matching website visitor went on being messaged, which is the
    # misreporting cancellation exists to stop. Raising rather than returning because that
    # is how this method already refuses ("Conversation already present"): the rescue below
    # logs it and answers nil.
    raise "Campaign #{@campaign.display_id} is cancelled" if @campaign.cancelled?

    ActiveRecord::Base.transaction do
      @contact_inbox.lock!

      # We won't send campaigns if a conversation is already present
      raise 'Conversation already present' if @contact_inbox.reload.conversations.present?

      @conversation = ::Conversation.create!(conversation_params)
      Messages::MessageBuilder.new(@campaign.sender, @conversation, message_params).perform
    end
    @conversation
  rescue StandardError => e
    Rails.logger.info(e.message)
    nil
  end

  private

  def message_params
    ActionController::Parameters.new({
                                       content: @campaign.message,
                                       campaign_id: @campaign.id
                                     })
  end

  def conversation_params
    {
      account_id: @campaign.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      campaign_id: @campaign.id,
      additional_attributes: conversation_additional_attributes,
      custom_attributes: custom_attributes || {}
    }
  end
end
