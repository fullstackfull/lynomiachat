require 'rails_helper'

# Tenants consume Lynomia documentation; they do not author it, so ArticlePolicy grants nothing to a tenant role
# (custom/app/policies/custom/article_policy.rb). The endpoint-level matrix across every principal and verb is
# spec/requests/custom/tenant_help_center_removal_spec.rb.
RSpec.describe ArticlePolicy, type: :policy do
  subject(:article_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:portal) { create(:portal, account: account) }
  let(:article) { create(:article, account: account, portal: portal, author: administrator) }

  let(:administrator_context) { { user: administrator, account: account, account_user: account.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.first } }

  permissions :index?, :update?, :show?, :edit?, :create?, :destroy?, :reorder? do
    context 'when administrator' do
      it { expect(article_policy).not_to permit(administrator_context, article) }
    end

    context 'when agent' do
      it { expect(article_policy).not_to permit(agent_context, article) }
    end
  end
end
