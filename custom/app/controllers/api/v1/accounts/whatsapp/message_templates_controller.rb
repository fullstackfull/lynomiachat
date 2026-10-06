# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/04-permissions-and-tenancy.md): the templates an
# account manages, read through the one shared query so the manager, the campaign selector and the flow selector can
# never disagree about what exists.
#
#   GET    /api/v1/accounts/:account_id/whatsapp/message_templates             every template, with the inboxes that
#                                                                              can send each one and what may be done
#   POST   /api/v1/accounts/:account_id/whatsapp/message_templates             a new local draft: inbox_id, name,
#                                                                              language, category, parameter_format,
#                                                                              components
#   GET    /api/v1/accounts/:account_id/whatsapp/message_templates/:id         one template
#   PATCH  /api/v1/accounts/:account_id/whatsapp/message_templates/:id         change it (locally for a draft, at Meta
#                                                                              for a template it holds)
#   DELETE /api/v1/accounts/:account_id/whatsapp/message_templates/:id         delete it
#   POST   /api/v1/accounts/:account_id/whatsapp/message_templates/:id/submit  hand a draft to Meta for review
#   POST   /api/v1/accounts/:account_id/whatsapp/message_templates/:id/duplicate  copy it into a new local draft
#
# Administrators only, and the role is checked before any record is fetched so a non-administrator never learns from a
# 404 whether a template exists. Every lifecycle action enforces Whatsapp::Templates::Actions, so hiding a control is
# never the only thing stopping an action. The per-inbox GET .../inboxes/:id/message_templates endpoint is unchanged
# and still serves the composer, the campaign form and the mobile app.
class Api::V1::Accounts::Whatsapp::MessageTemplatesController < Api::V1::Accounts::BaseController
  before_action -> { authorize(::Whatsapp::MessageTemplate) }
  before_action :fetch_template, only: [:show, :update, :destroy, :submit, :duplicate]

  rescue_from ::Whatsapp::Templates::Error do |error|
    render json: { error: error.as_json }, status: :unprocessable_entity
  end

  def index
    @templates = query.templates
    @waba_contexts = query.waba_contexts
  end

  def show; end

  def create
    @template = ::Whatsapp::MessageTemplate.new(
      draft_params.merge(account: Current.account, business_account_id: waba_id_of(inbox))
    )
    @template.save!
    @waba_contexts = query.waba_contexts
    render :show, status: :created
  end

  def update
    ::Whatsapp::Templates::Revision.new(@template, draft_params.except(:name, :language)).perform
    render :show
  end

  def destroy
    ::Whatsapp::Templates::Removal.new(@template).perform
    head :ok
  end

  def submit
    ::Whatsapp::Templates::Submission.new(@template).perform
    render :show
  end

  def duplicate
    @template = ::Whatsapp::Templates::Duplication.new(@template).perform
    render :show, status: :created
  end

  private

  def query
    @query ||= ::Whatsapp::Templates::Query.new(Current.account)
  end

  def fetch_template
    @template = query.find!(params[:id])
    @waba_contexts = query.waba_contexts
  end

  # The client picks an inbox, because that is what a person chooses; the WABA is read from it, because that is what
  # Meta scopes a template to.
  def inbox
    @inbox ||= Current.account.inboxes.find(params.require(:inbox_id))
  end

  def waba_id_of(inbox)
    waba_id = inbox.channel.try(:provider_config)&.dig('business_account_id')
    raise ActionController::ParameterMissing, :inbox_id if waba_id.blank?

    waba_id
  end

  # Name and language are part of Meta's identity for a template and it does not allow either to be edited, so an
  # update ignores them (see #update) rather than pretending they changed.
  def draft_params
    params.permit(:name, :language, :category, :parameter_format)
          .merge(components: ::Whatsapp::Templates::Components.sanitize(params[:components]))
          .compact
  end
end
