# One line format for the failures an operator has to be able to see in production.
#
# This is a formatter, not a monitoring system. It writes to Rails.logger, which on this installation goes to stdout
# and so to journald (RAILS_LOG_TO_STDOUT=true in the systemd units), already tagged with the request id
# (config/environments/production.rb: config.log_tags = [:request_id]). The repo's existing convention is a bracketed
# prefix -- [Rack::Attack][Blocked], [INBOX HEALTH], [MobileAuth] -- and this keeps it, so the lines are greppable
# alongside everything else.
#
# Why a formatter at all: the signals it carries come from four unrelated call sites, and four hand-written formats
# are four things to get wrong. Every value goes through #value, which is where the "no secrets, no message bodies,
# no unnecessary PII" rule is actually enforced -- callers pass identifiers, never content.
#
# Level is chosen by what an operator should DO, not by how bad it sounds:
#   info   something happened that is worth finding later
#   warn   expected provider behaviour the operator may want to know about, and must not be paged for
#   error  something the operator can and should act on
module Lynomia::OperatorLog
  PREFIX = 'LYNOMIA'.freeze
  MAX_VALUE = 200
  SAFE_VALUE = %r{\A[\w.:+@/-]*\z}

  class << self
    def info(event, **fields) = emit(:info, event, **fields)
    def warn(event, **fields) = emit(:warn, event, **fields)
    def error(event, **fields) = emit(:error, event, **fields)

    def emit(level, event, **fields)
      Rails.logger.public_send(level, line(event, fields))
    end

    # "[LYNOMIA][WHATSAPP_DELIVERY_REFUSED] account=3 inbox=77 code=131049 retry=DO_NOT_AUTO_RETRY"
    def line(event, fields)
      "[#{PREFIX}][#{event}] #{fields.compact.map { |key, value| "#{key}=#{value(value)}" }.join(' ')}".strip
    end

    private

    # Collapses whitespace so one event is one grep-able line, truncates so a provider's prose cannot fill the log,
    # and quotes anything that is not a bare token so the key=value shape survives a value with spaces in it.
    def value(raw)
      text = raw.to_s.gsub(/\s+/, ' ').strip
      text = "#{text[0, MAX_VALUE]}…" if text.length > MAX_VALUE
      text.match?(SAFE_VALUE) ? text : text.inspect
    end
  end
end
