require 'rails_helper'

# The Lynomia half of a contact merge: everything the OSS action left behind is moved first, the outcome is
# recorded, and the whole thing is one transaction.
RSpec.describe Custom::ContactMergeAction do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:base) { create(:contact, account: account, email: 'base@example.com') }
  let!(:mergee) { create(:contact, account: account, phone_number: '+96512345678') }

  def merge
    ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform
  end

  describe 'what used to be destroyed' do
    let(:campaign) { create(:campaign, account: account, inbox: inbox) }
    let!(:recipient) do
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: mergee,
                                status: :sent, sent_at: 1.day.ago)
    end
    let!(:ticket) { create(:support_ticket, account: account, contact: mergee) }

    it 'keeps the campaign recipient, on the base contact' do
      merge

      expect(recipient.reload.contact_id).to eq(base.id)
    end

    it 'keeps the support case pointing at a customer' do
      merge

      expect(ticket.reload.contact_id).to eq(base.id)
    end

    it 'still moves what the OSS action already moved' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: mergee)

      merge

      expect(conversation.reload.contact_id).to eq(base.id)
    end

    it 'still destroys the mergee and copies its attributes onto the base' do
      merge

      expect(Contact.where(id: mergee.id)).to be_empty
      expect(base.reload.phone_number).to eq('+96512345678')
    end
  end

  describe 'the audit record' do
    # One moved row, so `moved` has something to report.
    before { create(:support_ticket, account: account, contact: mergee) }

    around do |example|
      Audited.audit_class.as_user(administrator) { example.run }
    end

    it 'records the merge against the base contact, in the account' do
      mergee_id = mergee.id
      merge

      audit = Custom::AuditLog.find_by(comment: described_class::AUDIT_EVENT)
      expect(audit).to be_present
      expect([audit.auditable_type, audit.auditable_id, audit.associated_id])
        .to eq(['Contact', base.id, account.id])
      expect(audit.audited_changes['mergee_contact_id']).to eq(mergee_id)
    end

    it 'records what moved' do
      merge

      audit = Custom::AuditLog.find_by(comment: described_class::AUDIT_EVENT)
      expect(audit.audited_changes['moved']['support_tickets']).to eq(1)
    end

    it 'records a discarded duplicate rather than hiding it' do
      campaign = create(:campaign, account: account, inbox: inbox)
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: base, status: :sent)
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: mergee, status: :failed)

      merge

      audit = Custom::AuditLog.find_by(comment: described_class::AUDIT_EVENT)
      expect(audit.audited_changes['discarded_duplicates']['campaign_recipients']).to eq(1)
    end

    it 'carries ids, counts and nothing else -- no email, no phone number' do
      merge

      audit = Custom::AuditLog.find_by(comment: described_class::AUDIT_EVENT)
      expect(audit.audited_changes.to_json).not_to match(/base@example\.com|\+96512345678/)
    end

    it 'does not fail the merge when the record cannot be written' do
      allow(Custom::AuditLog).to receive(:create!).and_raise(StandardError, 'audit store down')

      expect { merge }.not_to raise_error
      expect(Contact.where(id: mergee.id)).to be_empty
    end
  end

  # The merge is the moment the second number and the second address would otherwise be destroyed, and the
  # measured consequence is that the next inbound message carrying one of them recreates the duplicate
  # (docs/p10/03-unified-customer-identity.md §2).
  describe 'the identities it absorbs' do
    before { account.enable_features('lynomia_unified_identity') && account.save! }

    it 'records the number and the address the survivor could not keep' do
      base.update!(phone_number: '+96550000001')
      mergee.update!(email: 'alt@example.com')

      merge

      expect(base.contact_identities.pluck(:identity_type, :value, :source)).to contain_exactly(
        ['phone', '+96512345678', 'merged'], ['email', 'alt@example.com', 'merged']
      )
    end

    it 'delivers the next message from that number to the survivor' do
      base.update!(phone_number: '+96550000001')

      merge

      contact_inbox = ContactInboxWithContactBuilder.new(
        inbox: create(:inbox, account: account), source_id: SecureRandom.uuid,
        contact_attributes: { name: 'Dana', phone_number: '+96512345678' }
      ).perform

      expect(contact_inbox.contact_id).to eq(base.id)
      expect(account.contacts.count).to eq(1)
    end

    it 'records nothing for a value the survivor kept as its own primary field' do
      merge

      expect(base.reload.phone_number).to eq('+96512345678')
      expect(base.contact_identities.where(identity_type: :phone)).to be_empty
    end

    it 'moves the identities the mergee had already linked' do
      linked = create(:contact_identity, account: account, contact: mergee, identity_type: :phone, value: '+96599999999')

      merge

      expect(linked.reload.contact_id).to eq(base.id)
    end

    it 'clears a row that now duplicates the survivor own primary field' do
      create(:contact_identity, account: account, contact: base, identity_type: :phone, value: '+96512345678')

      merge

      expect(base.reload.phone_number).to eq('+96512345678')
      expect(base.contact_identities.where(value: '+96512345678')).to be_empty
    end

    it 'counts them in the audit without naming them' do
      base.update!(phone_number: '+96550000001')

      merge

      audit = Custom::AuditLog.find_by(comment: described_class::AUDIT_EVENT)
      expect(audit.audited_changes['identities_absorbed']).to eq(1)
      expect(audit.audited_changes.to_json).not_to include('96512345678')
    end

    it 'records nothing at all when the account does not have the feature' do
      account.disable_features('lynomia_unified_identity')
      account.save!
      base.update!(phone_number: '+96550000001')

      merge

      expect(base.contact_identities).to be_empty
    end
  end

  describe 'the transaction' do
    let(:campaign) { create(:campaign, account: account, inbox: inbox) }
    let!(:recipient) do
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: mergee, status: :sent)
    end

    # The relocation runs first and the destroy runs last, so a failure in between must restore both.
    it 'leaves neither contact nor the moved rows half-merged when a later step fails' do
      allow_any_instance_of(Contact).to receive(:update!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

      expect { merge }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Contact.where(id: mergee.id)).to be_present
      expect(recipient.reload.contact_id).to eq(mergee.id)
      expect(Custom::AuditLog.where(comment: described_class::AUDIT_EVENT)).to be_empty
    end
  end
end
