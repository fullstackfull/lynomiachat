# Resolves the WhatsApp channel for an inbound WhatsApp Cloud webhook.
#
# Lynomia (docs/p11/00-p10-security-closure.md, SC3). Meta's `phone_number_id` is the stable identifier for a
# number and is now what this service looks the channel up BY, rather than a filter applied afterwards. Two
# things were wrong with filtering:
#
#   * The filter was a bare `==`, so it matched when BOTH sides were nil. A payload carrying a
#     display_phone_number but no phone_number_id was therefore accepted by any candidate channel whose
#     provider_config has no 'phone_number_id' -- which is every 360dialog channel. Those are also exactly the
#     channels for which the controller skipped Meta's signature check, and it decided that by resolving the
#     channel from the same body, so a caller could choose a channel AND waive its own authentication by
#     simply omitting the id.
#   * A channel whose stored display number no longer matches what Meta sends was never found at all, because
#     the only lookup keys were spellings of the display number. The payload was dropped and reported as
#     `unroutable_payload` even though the stable identifier agreed.
#
# The display-number lookups are kept as a fallback for a legacy row that never recorded a phone_number_id,
# and the normalized spelling is accepted only on a strict non-nil id match -- normalizing Argentinian numbers
# strips the mobile 9, which names a DIFFERENT real subscriber (see argentina_phone_normalizer.rb), so that
# candidate is only ever safe behind an exact identifier match.
class Whatsapp::WebhookChannelFinderService
  def initialize(display_phone_number:, phone_number_id:)
    @display_phone_number = display_phone_number
    @phone_number_id = phone_number_id.presence&.to_s
  end

  # Meta sends phone_number_id on every Cloud delivery. Without one there is nothing authoritative to resolve
  # against, so nothing is resolved -- rather than falling through to a nil-matches-nil comparison.
  def perform
    return if @phone_number_id.blank?

    channel_by_phone_number_id || channel_by_display_number
  end

  private

  # Deliberately NOT indexed. Measured on this expression: at 50 channels, which is already generous for one
  # installation, an expression index and a sequential scan are indistinguishable (0.086 ms against 0.084 ms).
  # The index only starts to pay at around 2,000 channels (0.483 ms -> 0.042 ms for 64 kB), which no single
  # installation has. Recorded in docs/p11/07-security-performance.md with both plans, so the threshold is
  # known rather than guessed if the shape of the installation ever changes.
  def channel_by_phone_number_id
    matches = Channel::Whatsapp.where("provider_config->>'phone_number_id' = ?", @phone_number_id).order(:id).to_a
    return matches.first unless matches.many?

    # Meta gives a phone number to one WABA, and every writer of this key takes it from a Graph response
    # authorized for that number, so two rows should be impossible -- but the column carries no database
    # uniqueness, so if it ever happens say so loudly and resolve deterministically instead of at random.
    Rails.logger.error(
      "[WHATSAPP INGEST] event=ambiguous_phone_number_id phone_number_id=#{@phone_number_id} " \
      "channel_ids=#{matches.map(&:id).join(',')}"
    )
    matches.first
  end

  def channel_by_display_number
    return if digits.blank?

    exact = Channel::Whatsapp.find_by(phone_number: "+#{digits}")
    # A row that never recorded an id is a legacy channel; one that recorded a different id is not this number.
    return exact if exact && exact.provider_config['phone_number_id'].blank?

    [exact, channel_by_normalized_number].compact.find do |channel|
      channel.provider_config['phone_number_id'] == @phone_number_id
    end
  end

  def digits
    @digits ||= @display_phone_number.to_s.gsub(/[^0-9]/, '')
  end

  def channel_by_normalized_number
    normalizer = Whatsapp::PhoneNumberNormalizationService::NORMALIZERS
                 .lazy.map(&:new).find { |n| n.handles_country?(digits) }
    return unless normalizer

    Channel::Whatsapp.find_by(phone_number: "+#{normalizer.normalize(digits)}")
  end
end
