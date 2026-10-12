class Webhooks::TiktokController < ActionController::API
  # Lynomia (docs/p11/00-p10-security-closure.md, SC4). The window is applied in both directions. It used to
  # reject only `delay > 5`, so a timestamp in the future produced a negative delay and passed unbounded.
  # The timestamp is covered by the signature, so this was never an attacker's replay window -- it is a
  # correctness fix, and it is deliberately the only change here: the tolerance itself stays at the value
  # this integration shipped with, because narrowing or widening it on guesswork would drop real deliveries.
  # What the right tolerance is needs a real TikTok app to measure (see the closure document).
  TIMESTAMP_TOLERANCE = 5.seconds

  before_action :verify_signature!

  def events
    event = JSON.parse(request_payload)
    if echo_event?
      # Add delay to prevent race condition where echo arrives before send message API completes
      # This avoids duplicate messages when echo comes early during API processing
      ::Webhooks::TiktokEventsJob.set(wait: 2.seconds).perform_later(event)
    else
      ::Webhooks::TiktokEventsJob.perform_later(event)
    end

    head :ok
  end

  private

  def request_payload
    @request_payload ||= request.body.read
  end

  def verify_signature!
    signature_header = request.headers['Tiktok-Signature']
    client_secret = GlobalConfigService.load('TIKTOK_APP_SECRET', nil)
    received_timestamp, received_signature = extract_signature_parts(signature_header)

    return head :unauthorized unless client_secret && received_timestamp && received_signature

    signature_payload = "#{received_timestamp}.#{request_payload}"
    computed_signature = OpenSSL::HMAC.hexdigest('SHA256', client_secret, signature_payload)

    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed_signature, received_signature)

    delay = Time.current.to_i - received_timestamp

    return head :unauthorized if delay.abs > TIMESTAMP_TOLERANCE.to_i
  end

  def extract_signature_parts(signature_header)
    return [nil, nil] if signature_header.blank?

    keys = signature_header.split(',')
    signature_parts = keys.map { |part| part.split('=') }.to_h
    [signature_parts['t']&.to_i, signature_parts['s']]
  end

  def echo_event?
    params[:event] == 'im_send_msg'
  end
end
