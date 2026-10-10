# frozen_string_literal: true

# Billing failures, reported through P9's Operations Center rather than a second place to look
# (docs/p11/07-security-performance.md).
#
# Everything here goes through Operations::SignalRecorder, which is the only writer of Operations::Signal and
# the only thing that enforces the no-secrets rule on what lands in that table: `reason` is bounded and has
# credentials redacted structurally, and `detail` accepts only allow-listed scalar keys. A Stripe error message
# or a webhook payload therefore cannot reach the operations feed through this path even by accident, which is
# exactly why it is not written directly.
#
# Deliberately NOT recorded: a customer's failed card attempt. That is an ordinary commercial event Stripe
# already tells the customer about, and a signal per attempt would bury the operator in noise -- the brief's
# own warning. What is recorded is the installation failing at its own job: an entitlement write that did not
# apply, a webhook that could not be matched to an account, a subscription that could not be synchronized.
module Billing::OperationsSignal
  SOURCE = :billing

  module_function

  # A plan's entitlements could not be written to the account. The account is left on its previous
  # entitlements, which is a commercial mismatch nobody would otherwise see.
  def record_sync_failure(account, error)
    recorder(account).record(
      :entitlement_sync_failed,
      severity: :critical,
      reason: error.message,
      detail: { plan_id: account&.billing_subscription&.plan_id }
    )
  end

  # A verified Stripe event whose customer or subscription matches no account here. Verified, so it is not an
  # attack; it means this installation and the Stripe account have drifted apart.
  def record_unknown_customer(event_type:, subscription_status: nil)
    recorder(nil).record(
      :unknown_provider_customer,
      severity: :warning,
      reason: 'a verified billing event matched no account in this installation',
      detail: { event_type: event_type, subscription_status: subscription_status }
    )
  end

  # Processing a verified event raised. Recorded as well as re-raised, because the raise is what makes the
  # provider retry and the signal is what makes a repeated failure visible.
  def record_event_failure(account, event_type, error)
    recorder(account).record(
      :billing_event_failed,
      severity: :critical,
      reason: error.message,
      detail: { event_type: event_type }
    )
  end

  def resolve(account)
    recorder(account).resolve_all
  end

  def recorder(account)
    Operations::SignalRecorder.new(source: SOURCE, account: account)
  end
end
