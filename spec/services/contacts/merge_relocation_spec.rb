require 'rails_helper'

# What a merge used to lose. Each example plants a row that the database would have deleted or orphaned when the
# mergee was destroyed, and asserts it survives on the base contact instead.
RSpec.describe Contacts::MergeRelocation do
  subject(:relocate) { described_class.new(base: base, mergee: mergee).perform }

  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:base) { create(:contact, account: account) }
  let(:mergee) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  describe 'the rows the database would have deleted outright' do
    it 'moves campaign recipients instead of letting the cascade delete them' do
      campaign = create(:campaign, account: account, inbox: inbox)
      recipient = CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: mergee,
                                            status: :sent, sent_at: 1.day.ago)

      expect(relocate[:moved][:campaign_recipients]).to eq(1)
      expect(recipient.reload.contact_id).to eq(base.id)
    end

    it 'moves a commerce customer link' do
      store = create(:commerce_store, :zid, account: account)
      link = create(:commerce_customer_link, account: account, store: store, contact: mergee)

      expect(relocate[:moved][:commerce_customer_links]).to eq(1)
      expect(link.reload.contact_id).to eq(base.id)
    end
  end

  describe 'the rows the database would have orphaned' do
    it 'keeps a support case with its customer' do
      ticket = create(:support_ticket, account: account, contact: mergee)

      expect(relocate[:moved][:support_tickets]).to eq(1)
      expect(ticket.reload.contact_id).to eq(base.id)
    end

    it 'keeps a commerce cart with its customer' do
      store = create(:commerce_store, :zid, account: account)
      cart = Commerce::Cart.create!(account: account, commerce_store: store, provider: 'zid',
                                    provider_cart_id: 'cart-1', contact: mergee, state: :abandoned,
                                    first_seen_at: 1.day.ago, last_provider_event_at: 1.day.ago,
                                    abandoned_at: 1.day.ago, currency: 'SAR')

      expect(relocate[:moved][:commerce_carts]).to eq(1)
      expect(cart.reload.contact_id).to eq(base.id)
    end

    it 'keeps a CSAT response, which was destroyed because it was never moved' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: mergee)
      message = create(:message, account: account, inbox: inbox, conversation: conversation)
      response = create(:csat_survey_response, account: account, conversation: conversation, message: message,
                                               contact: mergee)

      expect(relocate[:moved][:csat_survey_responses]).to eq(1)
      expect(response.reload.contact_id).to eq(base.id)
    end
  end

  describe 'a uniqueness the move would otherwise violate' do
    it 'keeps the base contact’s campaign recipient and discards the mergee’s duplicate, counting it' do
      campaign = create(:campaign, account: account, inbox: inbox)
      kept = CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: base,
                                       status: :read, sent_at: 2.days.ago)
      duplicate = CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: mergee,
                                            status: :failed, failed_at: 1.day.ago)

      result = relocate

      expect(result[:moved][:campaign_recipients]).to be_nil
      expect(result[:discarded][:campaign_recipients]).to eq(1)
      expect(kept.reload.status).to eq('read')
      expect(CampaignRecipient.where(id: duplicate.id)).to be_empty
    end

    it 'moves the recipients for other campaigns in the same merge' do
      shared = create(:campaign, account: account, inbox: inbox)
      other = create(:campaign, account: account, inbox: inbox)
      CampaignRecipient.create!(account: account, campaign: shared, inbox: inbox, contact: base, status: :sent)
      CampaignRecipient.create!(account: account, campaign: shared, inbox: inbox, contact: mergee, status: :sent)
      movable = CampaignRecipient.create!(account: account, campaign: other, inbox: inbox, contact: mergee,
                                          status: :sent)

      result = relocate

      expect([result[:moved][:campaign_recipients], result[:discarded][:campaign_recipients]]).to eq([1, 1])
      expect(movable.reload.contact_id).to eq(base.id)
    end

    it 'keeps one commerce link per store' do
      store = create(:commerce_store, :zid, account: account)
      create(:commerce_customer_link, account: account, store: store, contact: base,
                                      external_customer_id: 'cust-base')
      create(:commerce_customer_link, account: account, store: store, contact: mergee,
                                      external_customer_id: 'cust-mergee')

      result = relocate

      expect(result[:discarded][:commerce_customer_links]).to eq(1)
      expect(Commerce::CustomerLink.where(contact_id: base.id).pluck(:external_customer_id)).to eq(['cust-base'])
    end
  end

  describe 'labels' do
    it 'adds the mergee’s labels to the base contact without duplicating a shared one' do
      base.update!(label_list: %w[vip])
      mergee.update!(label_list: %w[vip arabic])

      expect(relocate[:moved][:labels]).to eq(2)
      expect(base.reload.label_list).to match_array(%w[vip arabic])
    end

    it 'does nothing when the mergee has none' do
      expect(relocate[:moved]).not_to have_key(:labels)
    end
  end

  it 'reports nothing moved when there is nothing to move' do
    expect(relocate).to eq({ moved: {}, discarded: {} })
  end
end
