# Lynomia: authorize the contact merge endpoint (docs/p10/04-contact-merge-linking.md).
#
# `create` is overridden rather than a `before_action` added, because that keeps the whole change to one method
# and leaves the OSS controller's own lookups -- both scoped to `Current.account.contacts`, which is what blocks
# a cross-account merge -- exactly as they are.
module Custom::Api::V1::Accounts::Actions::ContactMergesController
  def create
    authorize(::Contact, :merge?)
    super
  end
end
