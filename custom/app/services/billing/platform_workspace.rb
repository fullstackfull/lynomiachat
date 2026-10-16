# THE INSTALLATION'S OWN WORKSPACE, and the subscription that pays for it (P6D).
#
# Store Syria talks to its merchants about their accounts -- onboarding, a broken integration,
# a security notice -- and does it through Lynomia like any other sender. The workspace it
# does that from is not a merchant's, and the commercial arrangement the owner approved is a
# SEPARATE PAID SUBSCRIPTION funded by Store Syria: not a comp, not a permanently free
# account, and not an exemption from billing.
#
# WHY A SERVICE AND NOT A SIGNUP. An account that appears through the ordinary path gets the
# merchant trial on an after_create_commit, lands in the sales figures, and is swept by the
# trial backfill. `platform_owned` stops all three, but only if it is set at creation --
# which is the whole reason this is one deliberate operator act rather than a flag somebody
# remembers to tick afterwards.
#
# NO REAL CHARGE IS CREATED HERE. The subscription is `source: 'manual'` and carries no Stripe
# id, so nothing is billed by this code and no production payment is initiated -- which is
# both what Phase 6 is restricted to and the right default: an operator arranges the real
# commercial relationship, and this records it.
#
# THE PLAN MUST NOT BE SELLABLE. A plan that is `active` AND has a stripe_price_id appears in
# every merchant's upgrade list, so the platform plan is expected to be one or the other --
# checked here rather than discovered by a merchant being offered it.
#
# AND IT MUST METER. Billing::Entitlements.limit returns nil when nothing sets `campaign_sends`,
# and Billing::MeteredUsage.consume returns immediately on a nil limit WITHOUT writing a
# counter row -- so a plan that omits it gives this workspace unlimited, unrecorded sending.
# That is the opposite of the isolation this exists to provide, so it is refused.
class Billing::PlatformWorkspace
  class Refused < StandardError; end

  # One per installation. A second platform workspace is not a thing anybody wants and is far
  # more likely to be a mistake than an intention.
  def self.current
    Account.platform_owned.first
  end

  def self.provision!(name:, plan:)
    raise Refused, 'A platform workspace already exists on this installation' if current.present?

    new(name: name, plan: plan).perform
  end

  def initialize(name:, plan:)
    @name = name
    @plan = plan
  end

  def perform
    refuse_sellable_plan!
    refuse_unmetered_plan!

    Account.transaction do
      account = Account.create!(name: @name, platform_owned: true)
      account.create_billing_subscription!(status: 'active', source: 'manual', plan: @plan, quantity: 1)
      Billing::FeatureSync.new(account, @plan).perform
      audit(account)
      account
    end
  end

  private

  def refuse_sellable_plan!
    return unless @plan.active? && @plan.stripe_price_id.present?

    raise Refused, 'The platform plan must not be sellable: it would appear in every merchant upgrade list'
  end

  def refuse_unmetered_plan!
    return if @plan.limit_for('campaign_sends').present?

    raise Refused, 'The platform plan must set campaign_sends, or platform sending is unmetered and unrecorded'
  end

  def audit(account)
    Custom::AuditLog.create!(
      auditable: account, associated: account, user: nil, action: 'create',
      comment: 'billing.platform_workspace_provisioned',
      audited_changes: { name: @name, plan: @plan.name, source: 'manual' }
    )
  end
end
