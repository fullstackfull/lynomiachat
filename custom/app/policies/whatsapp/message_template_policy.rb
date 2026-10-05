# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/04-permissions-and-tenancy.md section 1): managing
# a template writes to Meta under the account's own credentials, so it sits with its neighbours -- inbox creation,
# campaign creation and the existing template sync are all administrator-only, and the read-only template page is
# already administrator-only in its route. There is no custom-role permission key for inboxes, channels, campaigns or
# templates, and this phase does not add a second authorization model.
class Whatsapp::MessageTemplatePolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end
end
