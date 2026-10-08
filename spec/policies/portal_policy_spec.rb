# frozen_string_literal: true

require 'rails_helper'

# Tenants consume Lynomia documentation; they do not author it, so PortalPolicy grants nothing to a tenant role
# (custom/app/policies/custom/portal_policy.rb). Upstream granted read to every member and write to an
# administrator; both are now refused, which is what this asserts. The endpoint-level matrix across every principal
# and verb is spec/requests/custom/tenant_help_center_removal_spec.rb.
RSpec.describe PortalPolicy, type: :policy do
  subject(:portal_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:portal) { create(:portal, account: account) }

  let(:administrator_context) { { user: administrator, account: account, account_user: account.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.first } }

  permissions :index?, :show?, :update?, :edit?, :create?, :destroy?, :logo? do
    context 'when administrator' do
      it { expect(portal_policy).not_to permit(administrator_context, portal) }
    end

    context 'when agent' do
      it { expect(portal_policy).not_to permit(agent_context, portal) }
    end
  end
end
