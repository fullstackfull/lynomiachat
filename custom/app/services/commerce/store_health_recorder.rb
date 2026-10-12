# The only thing that writes Commerce::StoreHealth (docs/product-refinement/09-commerce-operations.md §writer).
#
# One writer, for the same two reasons Operations::SignalRecorder is one writer. First, the WRITE STRATEGY lives
# here and nowhere else: a provider request that succeeds is not news if the last success was a minute ago, so
# success is throttled, while a failure and a recovery are facts that must land immediately. Second, and more
# important, this is where the no-secrets rule is enforced -- the only failure input this accepts is a
# Commerce::Error, whose `code` is validated against Commerce::Error::CODES at construction and whose `reason`
# is one of Lynomia's own classified reasons. There is no parameter here that a provider's response body, a
# webhook payload, a customer, a token or an exception's text could travel through.
#
# RECORDING NEVER RAISES. These calls sit inside the conversation panel's provider reads and inside the webhook
# path that keeps a merchant's orders current. A bug in observability must not break either, which is the same
# reasoning -- and the same shape -- as Operations::SignalRecorder and Custom::Account#start_billing_trial.
module Commerce::StoreHealthRecorder
  # A success inside this window is already the current answer, so it is not written again. This is what keeps a
  # busy store from turning its health row into a request log: one UPDATE per store per window, at most.
  SUCCESS_THROTTLE = ENV.fetch('COMMERCE_HEALTH_SUCCESS_THROTTLE_MINUTES', 5).to_i.minutes

  # The shape a classified reason may have. Every reason Commerce produces is a lower-case identifier
  # (`not_sent`, `http_502`, `zid_login_redirect`), so anything else is not one of ours and is dropped rather
  # than stored -- the one place that decides what reaches this column.
  SAFE_REASON = /\A\w{1,60}\z/

  # A provider request answered. Throttled, EXCEPT when the store was failing: a recovery must be visible at
  # once, and `consecutive_failures` must go back to zero the moment the provider answers again.
  def self.api_success(store, at: Time.current)
    write(store) do |scope|
      scope.where('last_api_success_at IS NULL OR last_api_success_at < :cutoff OR consecutive_failures > 0',
                  cutoff: at - SUCCESS_THROTTLE)
           .update_all(['last_api_success_at = :at, consecutive_failures = 0, updated_at = :at', { at: at }]) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # A provider request failed, as Lynomia classified it. Always written: a failure is the fact an operator is
  # looking for, and throttling it would hide the moment a store broke.
  #
  # One statement, so the count cannot be lost to a race: two workers failing at the same time each increment
  # the column as the database holds it, rather than both writing back the value they read in Ruby.
  def self.api_failure(store, error, at: Time.current)
    write(store) do |scope|
      scope.update_all( # rubocop:disable Rails/SkipsModelValidations
        ['last_api_failure_at = :at, last_error_code = :code, last_error_reason = :reason, last_error_at = :at,
          consecutive_failures = consecutive_failures + 1, updated_at = :at',
         { at: at, code: error.code, reason: classified_reason(error.reason) }]
      )
    end
  end

  # An AUTHENTICATED webhook delivery arrived. Every caller sits past the provider's signature or credential
  # check, which is the whole point: a rejected unauthenticated delivery says nothing about this store's health
  # and anyone on the internet could send one, so it must never move this timestamp.
  #
  # Throttled like a success, because a provider sending one event per order would otherwise write per order.
  def self.webhook_received(store, at: Time.current)
    stamp(store, :last_webhook_received_at, at)
  end

  # Lynomia finished applying one. Recorded separately from receipt so that a receipt timestamp running ahead of
  # a processed one is visible: that gap is a stuck queue, and nothing else in the product says so per store.
  def self.webhook_processed(store, at: Time.current)
    stamp(store, :last_webhook_processed_at, at)
  end

  # One throttled timestamp column. The two webhook columns differ only by name, and writing the same five
  # lines twice is how the two drift apart later.
  def self.stamp(store, column, at)
    write(store) do |scope|
      scope.where("#{column} IS NULL OR #{column} < :cutoff", cutoff: at - SUCCESS_THROTTLE)
           .update_all(["#{column} = :at, updated_at = :at", { at: at }]) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # The row for this store, then the caller's guarded UPDATE against it. A SELECT on a unique index next to a
  # provider request that just crossed the network is not a cost worth optimising away, and it keeps the
  # throttle in SQL, where two workers cannot both decide to write.
  def self.write(store)
    return nil unless store.is_a?(Commerce::Store) && store.persisted?

    ensure_row(store)
    yield Commerce::StoreHealth.where(commerce_store_id: store.id)
  rescue StandardError => e
    Rails.logger.error("[Commerce] could not record store health store=#{store.id} #{e.class}")
    nil
  end

  def self.ensure_row(store)
    return if Commerce::StoreHealth.exists?(commerce_store_id: store.id)

    Commerce::StoreHealth.create!(commerce_store_id: store.id)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.classified_reason(reason)
    reason.to_s[SAFE_REASON]
  end

  private_class_method :write, :ensure_row, :stamp, :classified_reason
end
