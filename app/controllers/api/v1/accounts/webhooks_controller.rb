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

  # :secret is permitted so a RECEIVER may choose the key its own deliveries are signed with.
  #
  # That is the normal shape for webhooks -- GitHub, GitLab and Shopify all let the subscriber
  # set it -- and it is not a weakening: the signature exists to prove to the receiver that a
  # delivery came from here, so the receiver is the only party the secret protects and the only
  # one who needs to know it. Choosing it lets an integration DERIVE the key per request from
  # something it already holds instead of storing a copy of one it was given, which is the
  # difference between a credential at rest and no credential at rest.
  #
  # Omitting it keeps today's behaviour exactly: has_secure_token generates one.
  def webhook_params
    params.require(:webhook).permit(:inbox_id, :name, :url, :secret, subscriptions: [])
  end

  def fetch_webhook
    @webhook = Current.account.webhooks.find(params[:id])
  end
end
