# Lynomia Analytics: WhatsApp delivery performance (docs/p8/02b-whatsapp-campaign-analytics.md).
#
# This family answers "are our WhatsApp sends actually arriving", across every WhatsApp inbox in the account --
# campaign sends, flow sends, automation template sends and agent replies alike. Per-campaign funnels are a
# different question and live in Analytics::Campaigns::Metrics.
#
# Two things about the source table decide the whole design:
#
#   1. `messages.status` carries no timestamps. The campaign ladder has delivered_at/read_at; this one does not,
#      so the furthest state reached is all there is, and `delivered` must be read as "status is delivered or
#      read" rather than as status equality with `delivered`.
#
#   2. `failed` is allowed to overwrite `delivered` and `read`
#      (app/services/messages/status_update_service.rb:36-44 permits any transition to or from failed). A message
#      that was delivered and later failed therefore reads only as failed, and its delivery is not recoverable.
#      That understates delivery in exactly that case, and it is the writer's behaviour rather than something the
#      read path can correct.
class Analytics::Whatsapp::Metrics
  WHATSAPP_CHANNEL = 'Channel::Whatsapp'.freeze

  COUNT_METRICS = %i[messages_sent template_messages_sent delivered read failed].freeze
  RATE_METRICS = %i[delivery_rate read_rate failure_rate].freeze
  EVENT_METRICS = (COUNT_METRICS + RATE_METRICS).freeze

  # `messages.content_attributes` cannot be read with the ordinary json operators. The model declares
  # `store :content_attributes` (app/models/message.rb:112), and ActiveRecord::Store serialises the hash to a
  # JSON *string* which the `json` column then encodes again, so the stored value is
  # `"{\"external_echo\":true}"` -- a JSON string, not a JSON object. `content_attributes ->> 'key'` therefore
  # returns NULL for every row. Verified against this database before anything was built on it.
  #
  # `#>> ARRAY[]::text[]` extracts the top-level value as text, which unescapes the inner JSON, and casting that
  # to jsonb gives the object the keys actually live in. It also works unchanged on a row whose content_attributes
  # happens to be a plain object, because extracting an object as text and re-parsing it is a no-op.
  #
  # `additional_attributes` is plain jsonb with no `store` declaration, so it is read directly.
  DECODED_CONTENT_ATTRIBUTES = '(messages.content_attributes #>> ARRAY[]::text[])::jsonb'.freeze

  # A coexistence echo is a message the merchant sent from their own WhatsApp app, synced back into Lynomia as an
  # outgoing message with `status: :delivered` written locally to stop SendReplyJob from re-sending it
  # (app/services/whatsapp/incoming_message_base_service.rb:180-190). That status is a local placeholder, not a
  # Meta delivery receipt, so counting echoes would inflate every rate on this screen with sends Meta never
  # confirmed to Lynomia. They are excluded here and reported separately as `coexistence_echoes` so the exclusion
  # is visible rather than silent.
  ECHO_EXCLUSION = "COALESCE(#{DECODED_CONTENT_ATTRIBUTES} ->> 'external_echo', 'false') <> 'true'".freeze
  ECHO_ONLY = "#{DECODED_CONTENT_ATTRIBUTES} ->> 'external_echo' = 'true'".freeze

  TEMPLATE_NAME = "messages.additional_attributes -> 'template_params' ->> 'name'".freeze
  TEMPLATE_LANGUAGE = "messages.additional_attributes -> 'template_params' ->> 'language'".freeze
  EXTERNAL_ERROR = "#{DECODED_CONTENT_ATTRIBUTES} ->> 'external_error'".freeze

  def initialize(account:, date_range:, filters:)
    @account = account
    @date_range = date_range
    @filters = filters
  end

  def messages_sent
    @messages_sent ||= sends.count
  end

  def template_messages_sent
    sends.where("#{TEMPLATE_NAME} IS NOT NULL").count
  end

  # "Reached delivered or better", not status equality: the ladder keeps only the furthest state reached.
  def delivered
    sends.where(status: %i[delivered read]).count
  end

  def read
    sends.where(status: :read).count
  end

  def failed
    sends.where(status: :failed).count
  end

  # Echoes are not part of any rate; this is how many were left out.
  def coexistence_echoes
    echo_scope.count
  end

  # nil rather than 0 when nothing was sent: "we sent nothing" must not read as "nothing arrived".
  def delivery_rate
    rate(delivered)
  end

  def read_rate
    rate(read)
  end

  def failure_rate
    rate(failed)
  end

  def series(metric)
    counts = case metric
             when :messages_sent then bucketed(sends)
             when :delivered then bucketed(sends.where(status: %i[delivered read]))
             when :failed then bucketed(sends.where(status: :failed))
             end
    fill_buckets(counts)
  end

  def breakdown(dimension)
    case dimension
    when :template then template_rows
    when :inbox then inbox_rows
    when :failure then failure_rows
    end
  end

  private

  # Account first, then WhatsApp only, then the shared filters. Every filter value was proved to belong to this
  # account by Analytics::FilterSet before it reached here.
  #
  # `private: false` matters as much as the channel filter: a private note is an internal message that is never
  # handed to Meta, so its `status` is whatever was written locally and never a delivery receipt. Counting notes
  # would inflate `messages_sent` and deflate every rate on this screen. This is the same exclusion
  # `Message.chat` makes for the same reason (app/models/message.rb:119); it is spelled out here rather than
  # reusing that scope because this family also needs to exclude the echoes, which `chat` knows nothing about.
  def sends
    scope = @account.messages
                    .where(created_at: @date_range.utc_range, message_type: :outgoing, private: false)
                    .where(inbox_id: whatsapp_inbox_ids)
                    .where(ECHO_EXCLUSION)
    scope = scope.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id]
    scope = apply_template_filter(scope) if @filters[:template_id]
    scope.unscope(:order)
  end

  def echo_scope
    scope = @account.messages
                    .where(created_at: @date_range.utc_range, message_type: :outgoing, private: false)
                    .where(inbox_id: whatsapp_inbox_ids)
                    .where(ECHO_ONLY)
    scope = scope.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id]
    scope.unscope(:order)
  end

  # A template is identified by name AND language: the same name exists once per language. The language
  # comparison is case-insensitive because that is the comparison the sender itself makes when it resolves a
  # template (app/services/whatsapp/template_processor_service.rb:32).
  def apply_template_filter(scope)
    template = Whatsapp::MessageTemplate.where(account_id: @account.id).find(@filters[:template_id])
    scope.where("#{TEMPLATE_NAME} = ?", template.name)
         .where("LOWER(#{TEMPLATE_LANGUAGE}) = ?", template.language.downcase)
  end

  def rate(value)
    total = messages_sent
    return nil if total.zero?

    (value.to_f / total * 100).round(1)
  end

  def whatsapp_inbox_ids
    @whatsapp_inbox_ids ||= @account.inboxes.where(channel_type: WHATSAPP_CHANNEL).select(:id)
  end

  def bucketed(scope)
    scope.group_by_period(@date_range.group_by, Arel.sql('messages.created_at'),
                          time_zone: @date_range.zone, default_value: 0).count
  end

  def fill_buckets(counts)
    normalized = (counts || {}).transform_keys { |key| key.to_date.strftime(Analytics::DateRange::DATE_FORMAT) }
    @date_range.bucket_starts.map do |bucket|
      key = bucket.to_date.strftime(Analytics::DateRange::DATE_FORMAT)
      { bucket: key, value: normalized[key].to_i }
    end
  end

  # Grouped on the name and language the message itself recorded, not on a join to the template table: a message
  # is evidence of what was sent, and a template renamed or deleted since would otherwise erase its own history.
  def template_rows
    sends.where("#{TEMPLATE_NAME} IS NOT NULL")
         .group(Arel.sql(TEMPLATE_NAME), Arel.sql(TEMPLATE_LANGUAGE)).count
         .sort_by { |_key, count| -count }
         .map do |(name, language), count|
           { id: [name, language].compact.join(':'), label: language.present? ? "#{name} (#{language})" : name, value: count }
         end
  end

  def inbox_rows
    labels = @account.inboxes.pluck(:id, :name).to_h
    sends.group(:inbox_id).count.sort_by { |_id, count| -count }
         .map { |id, count| { id: id, label: labels[id] || "##{id}", value: count } }
  end

  # Meta's own refusal, stored verbatim as "<code>: <title>"
  # (app/services/whatsapp/incoming_message_base_service.rb:73-76). Grouping on that string needs no second
  # parser and no classification this installation has not observed, and it is the same wording the conversation
  # view already shows an agent.
  def failure_rows
    sends.where(status: :failed)
         .group(Arel.sql(EXTERNAL_ERROR)).count
         .sort_by { |_error, count| -count }
         .map { |error, count| { id: error.presence, label: error.presence, value: count } }
  end
end
