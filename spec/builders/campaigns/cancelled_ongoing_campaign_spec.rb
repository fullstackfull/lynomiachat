require 'rails_helper'

# CANCELLING AN ONGOING CAMPAIGN HAS TO STOP IT, AND NOTHING WAS CHECKING.
#
# `Campaign#cancel!` refuses only a completed or already-cancelled campaign, so an ongoing
# (Website) campaign cancels successfully: the endpoint answers 200 and `render :show`
# reports campaign_status "cancelled". The live path never looked.
#
# An ongoing campaign has no send loop and no scheduler, so Campaigns::SendGuard -- which is
# what honours a cancellation for a one-off, per recipient -- is not in this path at all.
# The visitor's own `campaign_triggered` event reaches CampaignListener and then
# Campaigns::CampaignConversationBuilder, which found the campaign by display_id with no
# status predicate and created the conversation and the message. The widget's campaign list
# filtered on `enabled` alone, so the campaign was still advertised to every visitor as well.
#
# Both are covered here: the list is what the browser is told, and the builder is what
# actually messages somebody. The builder is the one that decides -- the visitor supplies
# the display id, so a campaign absent from the list can still be asked for by name.
RSpec.describe 'a cancelled ongoing campaign', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let!(:campaign) do
    create(:campaign, account: account, inbox: inbox, campaign_type: :ongoing, enabled: true,
                      trigger_rules: { url: 'https://test.com', time_on_page: 10 })
  end

  before { account.enable_features!('campaigns') }

  describe 'the campaign list the widget is given' do
    it 'offers an active ongoing campaign' do
      get '/api/v1/widget/campaigns', params: { website_token: web_widget.website_token }

      expect(response.parsed_body.pluck('id')).to include(campaign.display_id)
    end

    it 'does not offer it once it is cancelled' do
      campaign.cancel!

      get '/api/v1/widget/campaigns', params: { website_token: web_widget.website_token }

      expect(response.parsed_body.pluck('id')).not_to include(campaign.display_id)
    end
  end

  # THE ONE THAT MATTERS. The list is what the browser is shown; this is the message.
  describe 'the conversation the trigger would create' do
    def trigger
      Campaigns::CampaignConversationBuilder.new(contact_inbox_id: contact_inbox.id,
                                                 campaign_display_id: campaign.display_id).perform
    end

    it 'creates one while the campaign is active' do
      expect { trigger }.to change(Conversation, :count).by(1)
    end

    it 'creates none once the campaign is cancelled' do
      campaign.cancel!

      expect { trigger }.not_to change(Conversation, :count)
    end

    it 'sends no message once the campaign is cancelled' do
      campaign.cancel!

      expect { trigger }.not_to change(Message, :count)
    end
  end
end
