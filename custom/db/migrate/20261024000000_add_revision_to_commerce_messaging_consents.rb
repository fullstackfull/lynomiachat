# A MONOTONIC REVISION FOR A NATIVE CONSENT DECISION.
#
# Consents::ChangeFeed published `revision: consent.id`, and a partner's projector keeps the
# highest revision it has seen and drops anything at or below it -- which is what stops a
# delayed delivery reinstating a decision a later one replaced. The partner side's revision
# really is monotonic: `partner_consent_events` is one row per event, so its id rises with
# every decision. The native side is not built that way. `Commerce::MessagingConsents.write`
# does `find_or_initialize_by(contact_id:, purpose:)` and UPDATES the row in place, so its id
# is fixed for the life of the scope and every decision after the first carried the same
# revision as the first. The partner read it as a late duplicate and discarded it, and the
# reconciliation sweep could not repair it because it reported the same id.
#
# So the row needs a number that goes up when the decision changes, which is this column.
#
# BACKFILLED TO `id`, NOT TO ZERO OR ONE. Whatever a partner already stored for a scope came
# from this row's id, so starting the counter there means the next decision publishes id + 1
# -- strictly greater than what they hold, with no gap and nothing dropped. Starting at 1
# would publish revisions BELOW the ones already stored, and every future decision for those
# scopes would be discarded as late. (Nothing is deployed with this feed enabled today; the
# backfill is written so that stops mattering.)
class AddRevisionToCommerceMessagingConsents < ActiveRecord::Migration[7.2]
  def up
    add_column :commerce_messaging_consents, :revision, :bigint, null: false, default: 0
    execute 'UPDATE commerce_messaging_consents SET revision = id'
  end

  def down
    remove_column :commerce_messaging_consents, :revision
  end
end
