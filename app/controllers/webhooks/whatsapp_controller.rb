class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :process_payload

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    return head :ok if tracking_events_only?

    Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  def tracking_events_only?
    return false unless whatsapp_business_payload?

    changes = params.fetch(:entry, []).flat_map { |entry| entry.fetch(:changes, []) }
    changes.present? && changes.all? { |change| change[:field] == 'tracking_events' }
  end

  def valid_token?(token)
    # Lynomia: the app-level callback has no phone number in its path, and it is the only URL Meta delivers template
    # webhooks to, so its handshake is verified against an installation-wide token instead of a channel's.
    return app_level_token?(token) if params[:phone_number].blank?

    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
  end

  def app_level_token?(token)
    configured = GlobalConfigService.load('WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN', nil)
    configured.present? && token.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, configured.to_s)
  end

  def meta_app_secrets
    [
      *channel_meta_app_secrets(whatsapp_channel),
      GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    ]
  end

  def whatsapp_channel
    @whatsapp_channel ||= whatsapp_business_payload_channel || Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  # Lynomia: Meta signs every WhatsApp Cloud webhook with the secret of the Meta app that owns the subscription,
  # so manual numbers are verified too: against WHATSAPP_APP_SECRET, or against provider_config['app_secret'] for a
  # number connected through its own Meta app. 360dialog (provider 'default') does not send Meta's signature.
  #
  # Lynomia (docs/p11/00-p10-security-closure.md, SC3): the requirement is decided by the ENVELOPE, not by a
  # channel resolved from the same body. `object == 'whatsapp_business_account'` is Meta's own envelope and
  # nothing else posts it -- 360dialog posts a different shape to the per-number route, which is why the
  # exemption below is still reachable for it. Deciding from the resolved channel let a caller waive its own
  # authentication: resolve to a non-cloud channel and the signature was never checked. Combined with the
  # nil-matches-nil hole the finder used to have, omitting `phone_number_id` was enough to do exactly that.
  def meta_signature_verification_required?
    return true if whatsapp_business_payload?

    whatsapp_channel.blank? || whatsapp_channel.provider == 'whatsapp_cloud'
  end

  def whatsapp_business_payload?
    params[:object] == 'whatsapp_business_account'
  end

  def whatsapp_business_payload_channel
    return unless whatsapp_business_payload?

    metadata = params.dig(:entry, 0, :changes, 0, :value, :metadata)
    return if metadata.blank?

    Whatsapp::WebhookChannelFinderService.new(
      display_phone_number: metadata[:display_phone_number],
      phone_number_id: metadata[:phone_number_id]
    ).perform
  end

  # Lynomia (docs/p11/00-p10-security-closure.md, SC3): the kill switch used to read only the URL segment, so
  # it did nothing on the app-level route, which has none -- a number an operator had deliberately disabled
  # still ingested whenever Meta delivered it to the app's default callback. It now falls back to the number
  # of the channel the payload resolves to.
  def inactive_whatsapp_number?
    phone_number = params[:phone_number].presence || whatsapp_channel&.phone_number
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.include?(phone_number)
  end
end
