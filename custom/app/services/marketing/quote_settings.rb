# Reading and writing the one setting the sales desk has: where a quote request is emailed.
#
# INSTALLATION CONFIG REMAINS THE SINGLE SOURCE OF TRUTH. This module adds no store of its own -- it validates,
# writes `MARKETING_QUOTE_NOTIFICATION_EMAIL` through the InstallationConfig model, and audits the change.
# `InstallationConfig after_commit :clear_cache` evicts the Redis copy GlobalConfig serves, so a new address is
# live on the next request with no restart and no deploy, which is the owner's requirement.
#
# BLANK IS A REAL VALUE AND IT MEANS OFF. Clearing the field writes an empty string rather than deleting the
# row, so the key stays visible in Installation Configs, `Marketing::QuoteNotification.configured?` answers
# false, the mailer becomes a no-op and the banner appears. Nothing is invented in its place.
#
# THE DEFAULT IS EMPTY AND STAYS EMPTY. No seed, no ENV fallback and no built-in address exists anywhere in
# this module or in Marketing::QuoteNotification; an installation that has never been configured sends no
# notification at all.
module Marketing::QuoteSettings
  KEY = Marketing::QuoteNotification::KEY
  AUDIT_EVENT = 'marketing.quote_notification_email_changed'.freeze
  MAX_LENGTH = 180

  Result = Struct.new(:ok, :message, :detail, keyword_init: true) do
    def ok? = ok
  end

  class << self
    def address = Marketing::QuoteNotification.address

    def configured? = Marketing::QuoteNotification.configured?

    # Save, or refuse with a reason. A refusal leaves the stored address untouched.
    #
    # The validation is the one the quote form itself applies to a visitor's address
    # (URI::MailTo::EMAIL_REGEXP and the same 180-character cap as SiteQuoteRequest#email), so an operator
    # cannot store an address the application would reject coming the other way.
    #
    # ONE ADDRESS. A comma-separated list would pass `mail(to:)` and silently become several recipients with no
    # validation behind them, so a value containing a comma fails the regex and is refused like any other
    # malformed address. A distribution list belongs on the mail server, where it can be managed.
    def update(value, actor:)
      email = value.to_s.strip

      return Result.new(ok: false, message: :too_long) if email.length > MAX_LENGTH
      return Result.new(ok: false, message: :invalid) if email.present? && !email.match?(URI::MailTo::EMAIL_REGEXP)

      previous = address.to_s
      return Result.new(ok: true, message: :unchanged, detail: email) if previous == email

      config = InstallationConfig.find_or_initialize_by(name: KEY)
      config.update!(value: email)
      audit(config, previous, email, actor)

      Result.new(ok: true, message: email.blank? ? :cleared : :saved, detail: email)
    end

    # Sends one test message to the configured address, SYNCHRONOUSLY and on purpose.
    #
    # An operator pressing "send test" is asking whether this installation can deliver mail to that address.
    # Enqueueing the answer would report only that Redis accepted a job, which is not the question -- so the
    # SMTP conversation happens in the request and its outcome is what the screen reports. The one failure
    # class ApplicationMailer swallows is named in Marketing::QuoteNotificationJob.
    def send_test(actor:)
      return Result.new(ok: false, message: :not_configured) unless configured?

      Marketing::QuoteMailer.test_notification(actor&.email).deliver_now
      Result.new(ok: true, message: :test_sent, detail: address)
    rescue StandardError => e
      Rails.logger.error("[Marketing] quote notification test to #{address} failed: #{e.class}: #{e.message}")
      Result.new(ok: false, message: :test_failed, detail: "#{e.class}: #{e.message}")
    end

    # THE THREE STATES THE SCREEN REPORTS, decided here so the view cannot invent a fourth.
    #
    #   :unconfigured -- no address is stored, so nothing is sent.
    #   :failing      -- the most recent recorded delivery attempt failed.
    #   :configured   -- an address is stored and the most recent attempt, if there has been one, succeeded.
    #
    # A STORED ADDRESS IS NOT A SUCCESS STATE. `:configured` says the setting is in place and nothing more;
    # whether anything has actually been delivered is a separate question the screen answers from
    # `last_delivery`, which stays nil until a real notification goes out. That is the owner's rule -- no
    # permanent green tick for an address nobody has used.
    def status
      return :unconfigured unless configured?

      latest_attempt&.notification_failed? ? :failing : :configured
    end

    # The newest recorded attempt of any outcome. The installation's current delivery state is this row.
    def latest_attempt
      SiteQuoteRequest.notification_attempted.latest_notification_first.first
    end

    def last_failure
      SiteQuoteRequest.notification_failed.latest_notification_first.first
    end

    def last_delivery
      SiteQuoteRequest.notification_delivered.latest_notification_first.first
    end

    private

    # THE ADDRESS ITSELF IS RECORDED, both the old and the new. It is an operator's own business address, not a
    # credential and not a customer's personal data -- and an audit entry saying "the address changed" without
    # saying what to is useless to the person trying to work out why alerts stopped arriving. `AuditTrail::
    # Secrets` scrubs by key name and does not match `value`, so the entry survives the write intact.
    def audit(config, previous, current, actor)
      Custom::AuditLog.create!(
        auditable: config, user: actor, action: 'update', comment: AUDIT_EVENT,
        audited_changes: { 'value' => [previous.presence, current.presence] }
      )
    rescue StandardError => e
      # The setting is already saved; a failed audit must not pretend otherwise.
      Rails.logger.error("[Marketing] could not audit the quote notification change: #{e.class}")
    end
  end
end
