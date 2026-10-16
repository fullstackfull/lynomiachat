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

  def self.provision!(name:, plan:, platform_app:)
    raise Refused, 'A platform workspace already exists on this installation' if current.present?

    new(name: name, plan: plan, platform_app: platform_app).perform
  end

  def initialize(name:, plan:, platform_app:)
    @name = name
    @plan = plan
    @platform_app = platform_app
  end

  def perform
    refuse_sellable_plan!
    refuse_unmetered_plan!

    Account.transaction do
      account = Account.create!(name: @name, platform_owned: true)
      account.create_billing_subscription!(status: 'active', source: 'manual', plan: @plan, quantity: 1)
      Billing::FeatureSync.new(account, @plan).perform
      grant_access(account)
      audit(account)
      account
    end
  end

  private

  # WHAT MAKES THE WORKSPACE USABLE, and why it is here rather than left to a later step.
  #
  # Store Syria reaches a workspace through the ACCOUNT api, because there is no platform
  # messaging endpoint -- the platform namespace has users, accounts, grants and consents and
  # nothing for contacts, conversations or messages. To mint the scoped token that reaches it,
  # Platform::Api::V1::UsersController#authorized_account_for_scope requires BOTH that the app
  # holds a permissible on the account AND that the sender is an account_user of it. A
  # workspace provisioned without the pair looks fine and cannot send a thing, which is the
  # kind of half-built state that is discovered much later and from the wrong end.
  #
  # THE SENDER IS A SERVICE IDENTITY, NOT A PERSON. Its address is in a reserved domain that
  # cannot receive mail, so it can never collide with a real user and nobody can be signed in
  # as it by accident -- the same reasoning AccountProvisioner uses for a merchant workspace's
  # service address. `administrator`, because the surfaces this sender has to reach are
  # administrator-gated.
  def grant_access(account)
    sender = User.create!(
      name: "#{@name} notifications",
      email: "platform-notifications-#{account.id}@storesyria.invalid",
      # Nobody ever signs in as this identity -- Store Syria reaches the workspace with a
      # scoped token minted through the platform API, never with a password -- but the
      # policy applies to every User, so it is satisfied with a random value that is
      # discarded the moment it is written.
      password: "#{SecureRandom.alphanumeric(32)}aA1!",
      confirmed_at: Time.current
    )
    AccountUser.create!(account: account, user: sender, role: :administrator)
    @platform_app.platform_app_permissibles.find_or_create_by!(permissible: account)
    @platform_app.platform_app_permissibles.find_or_create_by!(permissible: sender)
  end

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
