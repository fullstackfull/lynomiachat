# Billing, split into the two things an operator must never confuse
# (docs/product-refinement/10-operations-ui.md §billing).
#
# A DECLINED CARD IS NOT A PLATFORM INCIDENT. A customer whose payment failed is a commercial fact that Stripe
# already told them about, and the account has a grace period for exactly that reason. Nobody should be woken
# for it. So the commercial side of this page is a set of COUNTS, labelled as commercial, with no health state
# attached -- counting them as red would make the console cry wolf every month.
#
# What IS an incident is the installation failing at its own job: an entitlement write that did not apply, a
# verified Stripe event that matched no account here, a subscription that could not be synchronized. Those are
# already recorded as Operations::Signal rows by Billing::OperationsSignal, which is deliberate about the same
# distinction, and this reads them rather than re-deriving anything.
#
# Three grouped queries and one count. Nothing here calls Stripe.
class Operations::BillingState
  # How many candidate subscriptions the locked-out list reads. A list, not a total: see #locked_accounts.
  LOCKED_CANDIDATES = 200

  def call
    { commercial: commercial, incidents: incidents, locked: locked_accounts, generated_at: Time.current }
  end

  private

  # Where the installation's accounts stand commercially. A count per status, plus the two time-bounded states
  # that decide whether the product still works for them today.
  def commercial
    by_status = BillingSubscription.group(:status).count
    {
      by_status: BillingSubscription::STATUSES.index_with { |status| by_status[status].to_i },
      by_source: BillingSubscription.group(:source).count,
      trials_ending: BillingSubscription.trialing.where(trial_ends_at: ..7.days.from_now).count,
      past_due: by_status['past_due'].to_i
    }
  end

  # The recorded platform-side billing problems, worst first. `Billing::OperationsSignal::SOURCE` rather than a
  # string, so renaming the source cannot quietly empty this list.
  def incidents
    signals = Operations::Signal.open_signals.where(source: Billing::OperationsSignal::SOURCE)
    { open: signals.count, by_signal: signals.group(:signal).count,
      recent: signals.recent_first.includes(:account).limit(10).to_a }
  end

  # The accounts the product has actually stopped working for, which is the one commercial number that is also
  # an operational one: somebody is locked out and will be in touch.
  #
  # Judged in Ruby, not in SQL: `accessible?` is a time-and-config judgement (grace periods, trial ends,
  # whether billing is enforced at all) that lives in the model, and reimplementing it as a WHERE clause is how
  # the console and the product start disagreeing about who is locked out.
  #
  # So it is a RECENT LIST and says so, never a total. Bounded to the statuses that can be locked and to
  # LOCKED_CANDIDATES of them, newest first: a page that walked every cancelled subscription an installation
  # ever had would get slower every month, and the status counts above already carry the scale.
  def locked_accounts
    candidates = BillingSubscription.where(status: %w[inactive past_due canceled])
                                    .order(updated_at: :desc).limit(LOCKED_CANDIDATES).includes(:account)
    { recent: candidates.reject(&:accessible?).map { |row| { account: row.account, status: row.status } },
      candidates_read: candidates.length }
  end
end
