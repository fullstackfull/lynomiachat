require 'rails_helper'

# THE COMMERCIAL AND LIFECYCLE RULES, which pull in opposite directions on purpose.
#
# A BILLING-LOCKED account reaches the desk: a customer whose subscription lapsed must still be able to
# complain about the bill, and the desk is never feature-gated and never sold. The exemption is declared once,
# on the module's base controller, which is the narrowest form available -- widening it means editing that
# method.
#
# An ADMINISTRATIVELY SUSPENDED account does not, and gets no exemption of any kind in V1. That 401 fires in
# `ensure_current_account`, one layer EARLIER than the billing guard, and this module does not touch that file
# -- the edit was removed from the plan rather than deferred, so a spam or security suspension can never gain
# an automatic bypass (D-5).
RSpec.describe 'Platform Support commercial and lifecycle rules', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:plan) { create(:billing_plan) }
  let!(:ticket) { create(:platform_support_ticket, account: account, reporter: reporter) }
  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  def as(user, path = "#{base}/tickets")
    get path, headers: user.create_new_auth_token, as: :json
  end

  describe 'a billing-locked account' do
    before { create(:billing_subscription, account: account, plan: plan, status: 'canceled', source: 'stripe') }

    it 'reads its tickets' do
      as(administrator)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([ticket.id])
    end

    it 'reads one ticket and its messages' do
      as(administrator, "#{base}/tickets/#{ticket.id}")
      expect(response).to have_http_status(:success)

      as(administrator, "#{base}/tickets/#{ticket.id}/messages")
      expect(response).to have_http_status(:success)
    end

    it 'downloads an attachment on its own ticket' do
      message = ticket.messages.create!(author_type: 'User', author_id: reporter.id, author_name: 'A reporter',
                                        body: 'The invoice')
      message.platform_support_message_files.attach(io: StringIO.new('INVOICE'), filename: 'invoice.pdf',
                                                    content_type: 'application/pdf')
      attachment = message.platform_support_message_files.attachments.last

      as(administrator, "#{base}/attachments/#{attachment.id}")

      expect(response).to have_http_status(:success)
    end

    # The same account is locked out of an ordinary account-scoped endpoint, which is what makes the exemption
    # above a real exemption rather than an installation with billing switched off.
    it 'is still locked out of an ordinary account endpoint' do
      allow(Billing::Settings).to receive(:enforced?).and_return(true)

      get "/api/v1/accounts/#{account.id}/conversations", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:payment_required)
    end

    # The desk has no feature flag, so it cannot be gated or sold.
    it 'is reachable by an account with no features enabled at all' do
      account.update!(feature_flags: 0)

      as(administrator)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'an administratively suspended account' do
    before { account.update!(status: :suspended) }

    it 'is refused on every member route with the existing 401' do
      [[base, 'tickets'], [base, "tickets/#{ticket.id}"], [base, "tickets/#{ticket.id}/messages"],
       [base, "tickets/#{ticket.id}/events"]].each do |prefix, suffix|
        as(administrator, "#{prefix}/#{suffix}")
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'is refused on the attachment route' do
      message = ticket.messages.create!(author_type: 'User', author_id: reporter.id, author_name: 'A reporter',
                                        body: 'The invoice')
      message.platform_support_message_files.attach(io: StringIO.new('INVOICE'), filename: 'invoice.pdf',
                                                    content_type: 'application/pdf')
      account.update!(status: :suspended)

      as(administrator, "#{base}/attachments/#{message.platform_support_message_files.attachments.last.id}")

      expect(response).to have_http_status(:unauthorized)
    end

    # The guard itself is unmodified, and the message is unchanged for every other request.
    it 'leaves the suspension guard untouched' do
      source = File.read(Rails.root.join('app/controllers/concerns/ensure_current_account_helper.rb'))

      expect(source).not_to match(/platform_support|support_desk_exempt/i)
      expect(source).to include("render_unauthorized('Account is suspended')")
    end

    it 'is refused for a spam suspension exactly as for any other' do
      account.update!(internal_attributes: { 'suspensions' => [{ 'category' => 'spam' }] })

      as(administrator)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'account deletion' do
    it 'nulls account_id, keeps the name snapshot, and keeps staff and audit history' do
      super_admin = create(:super_admin)
      Custom::AuditLog.create!(auditable: ticket, user: super_admin, action: 'update',
                               comment: 'platform_support.status_changed', audited_changes: { 'status' => 'open' })
      name = ticket.account_name_at_creation
      ticket.messages.create!(author_type: 'User', author_id: reporter.id, author_name: 'A reporter',
                              body: 'Still here')

      account.destroy!

      ticket.reload
      expect(ticket.account_id).to be_nil
      expect(ticket.account_name_at_creation).to eq(name)
      expect(ticket.messages.count).to eq(1)
      expect(Custom::AuditLog.where(auditable_id: ticket.id, auditable_type: 'PlatformSupport::Ticket')).to exist
    end
  end
end
