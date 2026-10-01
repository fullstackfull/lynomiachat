# Salla app events for Lynomia Commerce: POST /webhooks/salla, the webhook URL of the Lynomia Salla app.
#
# Verify, acknowledge, queue: this request only checks the signature on the raw body and queues it (Salla waits about
# 30 s). Tokens are stored and Salla is called in Commerce::Salla::WebhookJob. A delivery that is unsigned, badly signed or
# arrives while no webhook secret is configured gets 401 and is never parsed.
class Webhooks::SallaController < ActionController::API
  def create
    secret = Commerce::Salla::Config.webhook_secret
    raw_body = request.raw_post
    verified = secret && Commerce::Salla::Webhook.verified?(raw_body, strategy: request.headers['X-Salla-Security-Strategy'],
                                                                      signature: request.headers['X-Salla-Signature'], secret: secret)
    unless verified
      Commerce::Metrics.event('commerce.webhook.rejected', provider: 'salla')
      return head :unauthorized
    end

    Commerce::Salla::Webhook.enqueue(raw_body)
    head :ok
  end
end
