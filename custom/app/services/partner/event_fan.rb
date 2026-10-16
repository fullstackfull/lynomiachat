# frozen_string_literal: true

# HANDING ONE EVENT TO EVERY PARTNER THAT ASKED FOR IT.
#
# ONE COPY, BECAUSE THERE ARE NOW TWO FEEDS AND THE PLUMBING IS NOT WHERE THEY DIFFER.
# `Consents::ChangeFeed` and `Delivery::StatusFeed` each have their own vocabulary, their own
# payload and their own rule for deriving a delivery id -- and had, until this was pulled out,
# the same eight lines of fan-out written twice. The two reasons below are the whole of the
# complexity, both are easy to get wrong, and a second copy is a copy that will one day be
# fixed in one place only.
#
# NO NEW DELIVERY MECHANISM. An account Webhook pointing at a partner's signed ingress already
# exists (EventSubscriptionManager#ensureSubscribed), and that ingress already verifies the
# signature, rate-limits and refuses a duplicate `delivery_id`. A feed is one more event type
# on a pipe whose retries, signing and de-duplication are built and exercised.
module Partner::EventFan
  module_function

  # @param account [Account] whose webhooks are asked
  # @param event [String] the event name a webhook must be subscribed to
  # @param body [Hash] the payload, already in the partner's terms
  # @param delivery_id [String] DERIVED, never random -- see below
  #
  # THE DELIVERY ID IS THE CALLER'S, AND IT IS DERIVED. This is the one place these feeds
  # depart from WebhookListener#deliver_account_webhooks, which mints `SecureRandom.uuid` per
  # enqueue. That is fine for a conversation event, which is harmless to re-send. It is not
  # fine for a consent change or a delivery outcome: a reconciliation sweep, a republish after
  # a deploy or a retry at a higher level would each arrive as a NEW delivery and be processed
  # again. An id derived from the fact's own identity makes every one of those a no-op at the
  # receiver, which is what the receiver's unique index on it is for.
  def publish(account, event, body, delivery_id:)
    return unless account.api_and_webhooks_enabled?

    account.webhooks.account_type.each do |webhook|
      next unless webhook.subscriptions.include?(event)

      # AFTER THE TRANSACTION, NOT INSIDE IT. A publisher may run inside one -- a contact
      # merge wraps its whole relocation in `ActiveRecord::Base.transaction` -- and this app
      # does not set `enqueue_after_transaction_commit`, so the job went to Redis immediately.
      # A rollback then left a partner being told about something this side does not hold,
      # which is the one direction these feeds must never fail in. Outside a transaction this
      # runs straight away, so nothing else changes.
      ActiveRecord.after_all_transactions_commit do
        WebhookJob.perform_later(webhook.url, body, :account_webhook, secret: webhook.secret, delivery_id: delivery_id)
      end
    end
  end
end
