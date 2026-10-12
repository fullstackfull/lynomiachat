require 'rails_helper'

# What unified identity does to the two phases that came before it (docs/p10/01-architecture.md §3).
#
# The answer is meant to be "nothing it should not", and each part of that is asserted rather than assumed: P8's
# reported history is untouched, the timeline shows the union once, P9's cases follow the surviving customer,
# and a flow's state follows its conversation.
RSpec.describe 'P10 identity integration with P8 and P9', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { create(:contact, account: account, email: 'base@example.com') }
  let(:mergee) { create(:contact, account: account, phone_number: '+96512345678') }

  def merge
    Current.user = administrator
    ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform
  ensure
    Current.user = nil
  end

  describe "P8's reported history" do
    # `reporting_events` has no contact column at all -- it keys on account, inbox, user and conversation
    # (db/schema.rb) -- so a merge cannot change a figure that has already been reported. Asserted because the
    # brief asks for it, and because the absence of that column is the whole reason the answer is clean.
    it 'is untouched by a merge' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: mergee)
      event = create(:reporting_event, account: account, inbox: inbox, conversation: conversation,
                                       name: 'conversation_resolved', value: 120)

      expect { merge }.not_to(change { event.reload.attributes })
      expect(conversation.reload.contact_id).to eq(base.id)
    end

    it 'keeps the campaign send history the mergee had, on the survivor' do
      campaign = create(:campaign, account: account, inbox: inbox)
      recipient = CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: mergee,
                                            status: :sent, sent_at: 2.days.ago)

      merge

      expect(recipient.reload.contact_id).to eq(base.id)
      expect(CampaignRecipient.where(campaign: campaign).count).to eq(1)
    end
  end

  describe "P8's contact activity timeline" do
    it 'shows the merged customer one entry per conversation, not two' do
      create(:conversation, account: account, inbox: inbox, contact: base)
      create(:conversation, account: account, inbox: inbox, contact: mergee)

      merge

      get "/api/v1/accounts/#{account.id}/contacts/#{base.id}/activity",
          headers: administrator.create_new_auth_token, as: :json

      entries = response.parsed_body['payload']
      conversation_entries = entries.select { |entry| entry['category'] == 'conversations' }
      expect(conversation_entries.map { |entry| entry['id'] }.uniq.length).to eq(conversation_entries.length)
      expect(conversation_entries.length).to eq(2)
    end

    it 'does not show a linked identity as an extra entry' do
      account.enable_features('lynomia_unified_identity')
      account.save!
      Contacts::IdentityLinker.new(contact: base, identity_type: :phone, value: '+96599999999').link

      get "/api/v1/accounts/#{account.id}/contacts/#{base.id}/activity",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to be_empty
    end
  end

  describe "P9's support cases" do
    it 'follow the surviving customer rather than losing one' do
      ticket = create(:support_ticket, account: account, contact: mergee)

      merge

      expect(ticket.reload.contact_id).to eq(base.id)
    end

    it 'are recorded in the merge audit by count, never by value' do
      create(:support_ticket, account: account, contact: mergee)

      Audited.audit_class.as_user(administrator) { merge }

      audit = Custom::AuditLog.find_by(comment: Custom::ContactMergeAction::AUDIT_EVENT)
      expect(audit.audited_changes['moved']['support_tickets']).to eq(1)
      expect(audit.audited_changes.to_json).not_to match(/base@example\.com|\+96512345678/)
    end
  end

  describe 'a flow session' do
    # `flow_sessions` has no contact column; it keys on the conversation, which the OSS merge moves. So a flow
    # mid-conversation keeps its state and its customer without this phase touching it.
    it 'follows its conversation to the surviving customer' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: mergee)

      merge

      expect(FlowSession.column_names).not_to include('contact_id')
      expect(conversation.reload.contact_id).to eq(base.id)
    end
  end

  describe 'the analytics registry' do
    # PART H: no new omnichannel metric, and in particular no engagement score.
    it 'gained no identity metric' do
      names = Analytics::MetricFamily::FAMILIES.values.flat_map(&:metrics).map(&:to_s)

      expect(Analytics::MetricFamily.keys).not_to include(:identity, :identities)
      expect(names.grep(/identity|engagement|score/)).to be_empty
    end
  end
end
