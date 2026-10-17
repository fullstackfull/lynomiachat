# Lynomia shared audiences (docs/automation/02-shared-audiences.md). A contact filter is personal (its user's) unless
# `shared`: then it belongs to the account, every member may open it, administrators manage it, automation rules may
# reference it, and it survives its creator. Only contact filters can be shared; conversation folders stay personal.
module Custom::CustomFilter
  def self.prepended(base)
    base.validates :user, presence: true, unless: :shared?
    base.validate :shared_only_for_contacts
    base.scope :visible_to, ->(user) { where(user: user).or(where(shared: true)) }
  end

  # The audience's contacts now, as the account (no member's inbox scope): how automation rules and campaigns read a
  # shared audience (docs/campaigns/02-recipients.md). A relation, evaluated by whoever uses it.
  #
  # `commerce_store_id` narrows the Commerce aggregates to one installation's links, so the
  # same saved audience means "customers who spent over 500 WITH US" when a store-scoped
  # campaign resolves it and "over 500 anywhere" when the account's own filter does. The
  # audience itself is not rewritten and not duplicated per store; the scope is who is asking.
  # See Audience::CommerceCondition. Absent, the behaviour is exactly what it was.
  def members(commerce_store_id: nil)
    payload = Array(query['payload']).map { |condition| condition.to_h.with_indifferent_access }
    Contacts::FilterService.new(account, nil, { payload: payload, commerce_store_id: commerce_store_id }).relation
  end

  private

  def shared_only_for_contacts
    errors.add(:shared, :invalid) if shared? && !contact?
  end
end
