class Webhooks::SmsEventsJob < ApplicationJob
  queue_as :default

  SUPPORTED_EVENTS = %w[message-received message-delivered message-failed].freeze
  DELIVERY_EVENTS = %w[message-delivered message-failed].freeze

  # `channel_id` is resolved and authenticated by Webhooks::SmsController. The payload is never allowed to
  # select the tenant, so a job without it is a leftover from before that change and is dropped rather than
  # trusted (docs/p11/00-p10-security-closure.md, SC1).
  def perform(params = {})
    params = params.with_indifferent_access
    return unless SUPPORTED_EVENTS.include?(params[:type])

    channel = Channel::Sms.find_by(id: params[:channel_id])
    return if channel.nil?

    process_event_params(channel, params)
  end

  private

  # Bandwidth puts `type`, `description` and `errorCode` on the envelope and only the message itself under
  # `message`. Sms::DeliveryStatusService reads the envelope -- and its own spec has always passed it that
  # way -- but this job used to hand it the nested `message` under a `channel:` keyword it does not accept,
  # so every delivery receipt raised ArgumentError and no status was ever recorded.
  def process_event_params(channel, params)
    if DELIVERY_EVENTS.include?(params[:type])
      Sms::DeliveryStatusService.new(inbox: channel.inbox, params: params).perform
    else
      Sms::IncomingMessageService.new(inbox: channel.inbox, params: params[:message]).perform
    end
  end
end
