# Lynomia owns the documentation, so a tenant has no Help Center to link an inbox to: `Portal.tenant` is empty by
# construction, since the authoring API is closed (custom/app/policies/custom/portal_policy.rb) and the two platform
# portals carry no account. The parameter is refused at the request boundary rather than quietly dropped, so a client
# still sending it learns that it is gone.
#
# Refusing it also closes something upstream left open: `Inbox belongs_to :portal, optional: true` is not scoped to
# the account, so this endpoint accepted any portal id at all -- the platform documentation's, or another tenant's.
module Custom::Api::V1::Accounts::InboxesController
  def self.prepended(base)
    base.class_eval do
      before_action :refuse_help_center_link
    end
  end

  private

  # Unscoped by action on purpose: no request to this controller carries a portal, whichever verb it is.
  def refuse_help_center_link
    return unless params.key?(:portal_id)

    render_could_not_create_error(I18n.t('errors.inboxes.help_center_not_available'))
  end
end
