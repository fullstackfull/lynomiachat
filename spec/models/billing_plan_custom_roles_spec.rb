require 'rails_helper'

# Custom Roles as a capability a Lynomia plan sells.
#
# It was declared `premium: true` in config/features.yml, which in this codebase means exactly one thing:
# BillingPlan.assignable_features rejects it, because `premium` marks a capability Chatwoot Enterprise licenses
# and this fork therefore cannot sell. Custom Roles is not one of those -- the Enterprise-derived
# implementation was removed and an independent clean-room one written from
# docs/p-final/clean-room/specs/C-account-role-permissions.md -- so the declaration was wrong, and while it
# stood no plan could include the capability, Billing::FeatureSync never managed it, and
# Billing::OverrideGrant refused it as "not a capability a plan can sell".
#
# What the capability MEANS, and the authorization protecting it, are asserted in
# spec/requests/custom_roles_spec.rb and spec/services/conversations/capability_scope_spec.rb. This file is
# only about the commercial wiring: that a plan can sell it, that the sync applies it, and that
# Billing::Entitlements remains the one thing that answers.
# Described as BillingPlan because `BillingPlan.assignable_features` is the one behaviour this change moves;
# everything else here is an existing collaborator asserted through it.
RSpec.describe BillingPlan do
  let(:account) { create(:account) }
  let(:capability) { 'custom_roles' }

  describe 'the feature declaration' do
    let(:declaration) do
      YAML.safe_load(Rails.root.join('config/features.yml').read).find { |feature| feature['name'] == capability }
    end

    it 'no longer claims to be Enterprise-licensed' do
      expect(declaration).to eq('name' => capability, 'display_name' => 'Custom Roles', 'enabled' => false)
    end

    it 'is offered to a plan, which is the whole effect of the change' do
      expect(described_class.assignable_features.pluck('name')).to include(capability)
    end

    # The key still does its job for the capabilities it correctly describes, so this is a correction and not a
    # removal of the mechanism.
    it 'still withholds the capabilities this codebase really does not own' do
      expect(described_class.assignable_features.pluck('name')).not_to include('captain_integration', 'sla', 'saml')
    end
  end

  describe 'a plan that sells it' do
    it 'is valid, where before the validation rejected the name as unknown' do
      plan = build(:billing_plan, features: [capability])

      expect(plan).to be_valid
    end

    it 'turns the capability on for its subscribers when the super admin adds it' do
      plan = create(:billing_plan, features: [])
      create(:billing_subscription, account: account, plan: plan)

      plan.update!(features: [capability])

      expect(account.reload.feature_enabled?(capability)).to be(true)
    end

    it 'is applied by the sync directly too, which is the path a new subscription takes' do
      Billing::FeatureSync.new(account, create(:billing_plan, features: [capability])).perform

      expect(account.reload.feature_enabled?(capability)).to be(true)
    end
  end

  # The other direction, and the one an operator has to know about: the capability is now MANAGED, so a plan
  # that does not include it switches it off. That is the designed precedence -- the plan is the authority and
  # an operator exception is an override -- and the revocation is recorded rather than silent.
  describe 'a plan that does not sell it' do
    let(:plan) { create(:billing_plan, features: ['campaigns']) }

    before { account.enable_features!(capability) }

    it 'switches it off at the next sync' do
      Billing::FeatureSync.new(account, plan).perform

      expect(account.reload.feature_enabled?(capability)).to be(false)
    end

    it 'records the revocation on the account audit trail' do
      Billing::FeatureSync.new(account, plan).perform

      audit = Custom::AuditLog.where(comment: Billing::FeatureSync::AUDIT_REVOKED_BY_SYNC).sole
      expect(audit.audited_changes['capabilities_disabled']).to include(capability)
    end

    it 'leaves it alone when an operator has granted an override, so the exception survives the sync' do
      Billing::OverrideGrant.new(account).grant!(kind: :feature, name: capability, value: true, reason: 'pilot')

      Billing::FeatureSync.new(account, plan).perform

      expect(account.reload.feature_enabled?(capability)).to be(true)
    end
  end

  describe 'the per-account override, which used to be refused outright' do
    let(:grant) { Billing::OverrideGrant.new(account, actor: create(:super_admin)) }

    it 'grants the capability and says the answer came from the override' do
      grant.grant!(kind: :feature, name: capability, value: true, reason: 'contractual exception')

      expect(Billing::Entitlements.allowed?(account, capability)).to be(true)
      expect(Billing::Entitlements.source(account, capability)).to eq(:override)
    end

    it 'revokes it for an account whose plan does not include it' do
      create(:billing_subscription, account: account, plan: create(:billing_plan, features: []))
      grant.grant!(kind: :feature, name: capability, value: false, reason: 'downgrade agreed')

      expect(Billing::Entitlements.allowed?(account, capability)).to be(false)
    end
  end

  describe 'Billing::Entitlements remains the one answer' do
    it 'reports the plan as the source for a subscriber of a plan that sells it' do
      create(:billing_subscription, account: account, plan: create(:billing_plan, features: [capability]))
      account.enable_features!(capability)

      expect(Billing::Entitlements.source(account, capability)).to eq(:plan)
      expect(Billing::Entitlements.allowed?(account, capability)).to be(true)
    end

    # The choke point DECISION 2 established: the membership's capability list is bounded by the entitlement,
    # and it reads it through this service rather than through the flag directly.
    it 'bounds a membership\'s capabilities, so an unentitled account grants nothing from its sets' do
      user = create(:user, account: account, role: :agent)
      membership = account.account_users.find_by(user: user)
      membership.update!(custom_role: create(:custom_role, account: account, permissions: %w[commerce_order_manage]))

      account.enable_features!(capability)
      expect(membership.reload.permissions).to contain_exactly('commerce_order_manage', 'custom_role')

      account.disable_features!(capability)
      expect(membership.reload.permissions).to contain_exactly('agent')
    end
  end

  # The reason this change is allowed at all. Asserted rather than asserted-in-prose, because "is it ours?" is
  # the question that decides whether the capability may be sold.
  describe 'no Chatwoot Enterprise dependency' do
    it 'runs with the Enterprise edition absent' do
      expect(ChatwootApp.enterprise?).to be(false)
      expect(Rails.root.join('enterprise')).not_to exist
      expect(ChatwootApp.extensions).to eq(['custom'])
    end

    it 'implements the capability under custom/, and names no Enterprise constant anywhere in it' do
      files = [
        'custom/app/models/custom_role.rb',
        'custom/app/controllers/api/v1/accounts/custom_roles_controller.rb',
        'custom/app/models/custom/account_user.rb',
        'custom/app/services/conversations/capability_scope.rb'
      ].map { |path| Rails.root.join(path) }

      files.each do |path|
        expect(path).to exist, "#{path} is missing"
        expect(path.read).not_to match(%r{Enterprise::|enterprise/app|include_mod_with\('Enterprise})
      end
    end

    # Where the loaded constant actually comes from, rather than where a file happens to sit: an Enterprise
    # overlay would resolve `CustomRole` somewhere else, and this would say so.
    it 'resolves the loaded constants from the Lynomia overlay' do
      # A method's own source location rather than `const_source_location`, which under Zeitwerk reports where
      # the autoload was registered instead of where the class is written.
      expect(CustomRole.instance_method(:detach_memberships).source_location.first)
        .to end_with('custom/app/models/custom_role.rb')
      expect(Conversations::CapabilityScope.instance_method(:narrow).source_location.first)
        .to end_with('custom/app/services/conversations/capability_scope.rb')
      expect(AccountUser.ancestors.map(&:name)).to include('Custom::AccountUser')
      expect(AccountUser.ancestors.map(&:to_s).grep(/Enterprise/)).to be_empty
    end
  end
end
