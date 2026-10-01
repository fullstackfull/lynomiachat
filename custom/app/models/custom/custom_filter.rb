# Lynomia shared audiences (docs/automation/02-shared-audiences.md). A contact filter is personal (its user's) unless
# `shared`: then it belongs to the account, every member may open it, administrators manage it, automation rules may
# reference it, and it survives its creator. Only contact filters can be shared; conversation folders stay personal.
module Custom::CustomFilter
  def self.prepended(base)
    base.validates :user, presence: true, unless: :shared?
    base.validate :shared_only_for_contacts
    base.scope :visible_to, ->(user) { where(user: user).or(where(shared: true)) }
  end

  private

  def shared_only_for_contacts
    errors.add(:shared, :invalid) if shared? && !contact?
  end
end
