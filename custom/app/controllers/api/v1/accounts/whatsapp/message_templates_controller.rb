# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/04-permissions-and-tenancy.md): the templates an
# account manages, read through the one shared query so the manager, the campaign selector and the flow selector can
# never disagree about what exists.
#
#   GET /api/v1/accounts/:account_id/whatsapp/message_templates       every template the account manages, with the
#                                                                     inboxes that can send each one and what may be
#                                                                     done to it
#   GET /api/v1/accounts/:account_id/whatsapp/message_templates/:id   one template
#
# Administrators only, and the role is checked before any record is fetched so a non-administrator never learns from a
# 404 whether a template exists. The per-inbox GET .../inboxes/:id/message_templates endpoint is unchanged and still
# serves the composer, the campaign form and the mobile app.
class Api::V1::Accounts::Whatsapp::MessageTemplatesController < Api::V1::Accounts::BaseController
  before_action -> { authorize(::Whatsapp::MessageTemplate) }
  before_action :fetch_template, only: [:show]

  def index
    @templates = query.templates
    @waba_contexts = query.waba_contexts
  end

  def show
    @waba_contexts = query.waba_contexts
  end

  private

  def query
    @query ||= ::Whatsapp::Templates::Query.new(Current.account)
  end

  def fetch_template
    @template = query.find!(params[:id])
  end
end
