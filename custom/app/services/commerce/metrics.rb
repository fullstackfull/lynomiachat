# Commerce telemetry (docs/commerce/24-realtime-architecture.md §8). Lynomia has no metrics backend of its own, so each
# event is an ActiveSupport notification (Datadog or New Relic subscribers can count it) and one structured log line.
# Fields are ids, counts, codes and durations only: never a token, an email, a phone, a name or an order payload.
module Commerce::Metrics
  def self.event(name, **fields)
    ActiveSupport::Notifications.instrument(name, fields)
    Rails.logger.info("[Commerce] metric=#{name}#{fields.map { |key, value| " #{key}=#{value}" }.join}")
  end
end
