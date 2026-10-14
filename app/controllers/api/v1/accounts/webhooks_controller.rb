class Api::V1::Accounts::WebhooksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_webhook, only: [:update, :destroy]

  def index
    @webhooks = Current.account.webhooks
  end

  def create
    @webhook = Current.account.webhooks.new(webhook_params)
    @webhook.save!
  end

  def update
    @webhook.update!(webhook_params)
  end

  def destroy
    @webhook.destroy!
    head :ok
  end

  private

  # Everything an operator configures about a webhook. `secret` is deliberately absent and is
  # added, for CREATE only, by #permitted_attributes.
  CONFIGURATION_ATTRIBUTES = [:inbox_id, :name, :url, { subscriptions: [] }].freeze

  def webhook_params
    params.require(:webhook).permit(*permitted_attributes)
  end

  # :secret is permitted ON CREATE so a RECEIVER may choose the key its own deliveries are signed
  # with. That is the normal shape for webhooks -- GitHub, GitLab and Shopify all let the
  # subscriber set it -- and it is not a weakening: the signature proves to the receiver that a
  # delivery came from here, so the receiver is the only party it protects and the only one who
  # needs to know it. Choosing it lets an integration DERIVE the key per request from something it
  # already holds instead of storing a copy of one it was handed, which is the difference between
  # a credential at rest and no credential at rest. Omitting it keeps today's behaviour exactly:
  # has_secure_token generates one, including when the value sent is blank, because a blank string
  # makes `secret?` false.
  #
  # NOT ON UPDATE, AND THAT HALF IS THE SECURITY-RELEVANT ONE. Two existing controls are written
  # against the invariant that this column cannot move once the row exists, and permitting it here
  # on every action silently broke both:
  #
  #   custom/app/models/custom/audit/webhook.rb audits `only:` five configuration columns and
  #   excludes the secret so the trail can never contain it. `audited` slices the change set to
  #   those columns, so an update touching ONLY the secret produces an EMPTY slice and therefore
  #   NO audit row -- a signing key could be rotated leaving nothing behind.
  #
  #   lib/webhooks/trigger.rb:57 signs only `if @secret.present?`, and nothing validates presence
  #   on this column -- has_secure_token fills it before_create and never again. A single PATCH
  #   with an empty secret would therefore unsign every future delivery for that webhook,
  #   permanently and quietly.
  #
  # Rotation is create-then-delete, which leaves both an audit trail and a signed row throughout.
  def permitted_attributes
    action_name == 'create' ? [:secret, *CONFIGURATION_ATTRIBUTES] : CONFIGURATION_ATTRIBUTES
  end

  def fetch_webhook
    @webhook = Current.account.webhooks.find(params[:id])
  end
end
