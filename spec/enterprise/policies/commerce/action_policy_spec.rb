require 'rails_helper'

# A custom role with commerce_order_manage changes statuses and resends store emails; refunds and cancellations stay
# administrator-only whatever the role grants (pilot rule, docs/commerce/32-actions-security.md).
RSpec.describe Commerce::ActionPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:custom_role) { create(:custom_role, account: account, permissions: %w[conversation_manage commerce_order_manage]) }
  let(:user) { create(:user) }
  let(:account_user) { create(:account_user, user: user, account: account, role: :agent, custom_role: custom_role) }
  let(:user_context) { { user: user, account: account, account_user: account_user } }

  permissions :perform? do
    it 'allows the managing actions only' do
      %w[update_order_status resend_invoice resend_payment_link update_shipping].each do |action_type|
        expect(policy).to permit(user_context, action_type)
      end
      %w[cancel_order refund_full refund_partial].each { |action_type| expect(policy).not_to permit(user_context, action_type) }
    end

    it 'gives a custom role without the permission nothing' do
      custom_role.update!(permissions: %w[conversation_manage contact_manage])

      Commerce::ActionRun::ORDER_ACTIONS.each { |action_type| expect(policy).not_to permit(user_context, action_type) }
    end
  end

  it 'is a permission custom roles can be given' do
    expect(CustomRole::PERMISSIONS).to include('commerce_order_manage')
    expect(build(:custom_role, account: account, permissions: %w[commerce_order_manage])).to be_valid
  end
end
