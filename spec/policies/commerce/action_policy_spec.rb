require 'rails_helper'

# Who may act on a store order (docs/commerce/32-actions-security.md): administrators everything; agents nothing unless a
# custom role grants commerce_order_manage (spec/enterprise), and never refunds or cancellations.
RSpec.describe Commerce::ActionPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:context_for) { ->(user) { { user: user, account: account, account_user: account.account_users.find_by(user: user) } } }

  permissions :perform? do
    it 'lets administrators perform every order action' do
      Commerce::ActionRun::ORDER_ACTIONS.each { |action_type| expect(policy).to permit(context_for.call(admin), action_type) }
    end

    it 'gives agents no order action by default' do
      Commerce::ActionRun::ORDER_ACTIONS.each { |action_type| expect(policy).not_to permit(context_for.call(agent), action_type) }
    end
  end
end
