# Which Odoo partner is this Lynomia account's (docs/odoo/02-architecture.md §4).
#
# THE RULE THIS FILE EXISTS TO ENFORCE: two unrelated Lynomia accounts that happen to share a billing email
# must never become one Odoo partner. So nothing here ever searches by email or by name. The only thing it
# searches on is the stamp it wrote itself, inside the destination scope, and the mapping table's unique
# indexes make the merge a failed insert rather than a silent join.
#
# IT RESOLVES, OR IT ASKS. There is no third behaviour. If the stamp matches exactly one partner, that is the
# partner. If it matches none, one is created. If it matches MORE THAN ONE, the mapping is put to a person --
# because two partners carrying our stamp means somebody duplicated a record in Odoo, and picking either one
# would quietly split or merge a customer's ledger.
class Odoo::CustomerResolver
  class Conflict < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason)
    end
  end

  def initialize(profile, accounting: nil)
    @profile = profile
    @accounting = accounting || Odoo::Accounting.new(profile)
    @stamp = Odoo::SourceStamp.new(profile)
  end

  # Returns a synchronized Odoo::CustomerMapping. Raises Conflict when only a person can decide.
  #
  # `stripe_customer_id` comes from the account's OWN BillingSubscription row, never from a webhook body:
  # Billing::SubscriptionSync already prefers server-owned mappings over provider metadata, and this follows
  # the same rule for the same reason.
  def resolve!(account)
    mapping = mapping_for(account)
    return mapping if mapping.exported? && mapping.state_synchronized?

    partner_id = find_partner(mapping.source_reference) || create_partner(account, mapping)
    mapping.update!(odoo_partner_id: partner_id, state: :synchronized, last_synced_at: Time.current,
                    matched_by: mapping.matched_by.presence || 'source_reference', review_reason: nil)
    mapping
  rescue Conflict => e
    # Flagged HERE rather than where it was detected, so every way of needing a human leaves the same visible
    # state on the same row -- and so the Customers screen never shows a mapping that is stuck without saying
    # why.
    flag(mapping, e.reason)
  rescue ActiveRecord::RecordNotUnique
    # The partner-side unique index fired: another Lynomia account already claims this partner. That IS the
    # merge this class exists to prevent, so it becomes a conflict rather than an exception nobody can read.
    flag(mapping, 'partner_claimed_by_another_account')
  end

  private

  # `find_or_create_by!` on (profile, account) rather than a read-then-write: the unique index decides, so two
  # workers resolving the same account concurrently cannot produce two mappings.
  def mapping_for(account)
    Odoo::CustomerMapping.find_or_create_by!(destination_profile: @profile, account_id: account.id) do |record|
      record.stripe_customer_id = account.billing_subscription&.stripe_customer_id
      record.source_reference = @stamp.reference(kind: 'customer', provider_object_id: "account_#{account.id}")
      record.state = :pending
    end
  end

  def find_partner(reference)
    rows = @accounting.find_partners(reference)
    raise Conflict, 'stamp_matches_several_partners' if rows.length > 1

    rows.first&.fetch('id', nil)
  end

  # The partner's NAME is the account's name, which is a label for a human to read in Odoo and is not used to
  # find anything. Its `email` is stored for the same reason -- an accountant chasing a payment needs it -- and
  # is likewise never a search key.
  def create_partner(account, mapping)
    partner_id = @accounting.create_partner(name: partner_name(account), reference: mapping.source_reference,
                                            email: billing_email(account))
    mapping.matched_by = 'created'
    partner_id
  end

  # Named so an accountant opening Odoo can tell which Lynomia account a partner is, including when two
  # accounts are called the same thing -- which is exactly the case this integration must not collapse.
  def partner_name(account)
    "#{account.name} (Lynomia Chat ##{account.id})"
  end

  def billing_email(account)
    account.administrators.first&.email
  end

  # `odoo_partner_id` IS CLEARED, and that is the whole point of the row: this mapping does not own that
  # partner. Leaving the conflicting id assigned would also make this very update fail the same unique index
  # again -- and an exception raised inside a rescue clause is not caught by its siblings, so the conflict
  # would escape as a PG::UniqueViolation nobody can read.
  def flag(mapping, reason)
    mapping&.update(odoo_partner_id: nil, state: :needs_review, review_reason: reason)
    raise Conflict, reason
  end
end
