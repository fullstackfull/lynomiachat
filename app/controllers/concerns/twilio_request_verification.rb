# frozen_string_literal: true

# Verifies Twilio's X-Twilio-Signature on the two public Twilio callbacks. Lives here beside
# MetaTokenVerifyConcern, which does the same job for Meta's webhooks -- and because
# `custom/app/*/concerns` is not an autoload root in this fork (config/application.rb globs one level), so a
# concern placed there resolves as Concerns::... rather than at the top level.
# (docs/p11/00-p10-security-closure.md, SEC-1 and SEC-2).
#
# Both endpoints used to accept any unauthenticated body and pick the receiving Channel::TwilioSms from body
# fields -- MessagingServiceSid, or AccountSid plus the number. A Twilio number is a business's public phone
# number and an Account SID is not a secret, so anyone holding both could inject inbound messages into that
# account, or mark an existing outgoing message failed with an attacker-chosen error string that agents read.
# This is the same defect class as the Bandwidth webhook, closed the same way.
#
# WHY THE BODY MAY STILL NAME THE CHANNEL
# It names a CANDIDATE; the signature is what proves the caller holds that candidate's secret. Twilio signs
# with the account's auth token, which this installation stores per channel, so resolving first and verifying
# against that channel's own token is the only order that can work -- and an attacker naming a channel they do
# not own cannot produce its signature. Exactly the shape used for Bandwidth, where the path names the channel
# and Basic auth proves the caller holds its credentials.
#
# OPERATIONAL NOTE: Twilio signs the exact URL it was configured with. `request.original_url` reconstructs
# that from the request, which is correct behind a proxy that sets X-Forwarded-Proto and Host -- the
# deployment this fork ships. A proxy that rewrites the path or drops those headers will fail verification,
# which is the honest failure for a misconfigured deployment rather than a reason to skip the check.
module TwilioRequestVerification
  extend ActiveSupport::Concern

  SIGNATURE_HEADER = 'X-Twilio-Signature'

  included do
    before_action :verify_twilio_signature!
  end

  private

  def verify_twilio_signature!
    return if valid_twilio_signature?

    Rails.logger.warn("[TWILIO] Rejected a callback with a missing or invalid #{SIGNATURE_HEADER}: #{request.path}")
    head :unauthorized
  end

  def valid_twilio_signature?
    signature = request.headers[SIGNATURE_HEADER]
    return false if signature.blank?

    token = twilio_channel_for_verification&.auth_token
    return false if token.blank?

    Twilio::Security::RequestValidator.new(token)
                                      .validate(request.original_url, request.request_parameters, signature)
  rescue StandardError => e
    # A malformed URL or signature must be a refusal, not a 500 that Twilio retries forever.
    Rails.logger.warn("[TWILIO] Could not verify a callback signature: #{e.class}")
    false
  end

  # The same resolution the downstream services use, so a request that verifies here is a request they can
  # route. `To` for inbound, `From` for a delivery receipt about something this installation sent.
  def twilio_channel_for_verification
    return @twilio_channel_for_verification if defined?(@twilio_channel_for_verification)

    @twilio_channel_for_verification = resolve_twilio_channel
  end

  def resolve_twilio_channel
    service_sid = params[:MessagingServiceSid]
    return ::Channel::TwilioSms.find_by(messaging_service_sid: service_sid) if service_sid.present?

    account_sid = params[:AccountSid]
    number = params[:To].presence || params[:From]
    return nil if account_sid.blank? || number.blank?

    ::Channel::TwilioSms.find_by(account_sid: account_sid, phone_number: number) ||
      ::Channel::TwilioSms.find_by(account_sid: account_sid, phone_number: "whatsapp:#{number}")
  end
end
