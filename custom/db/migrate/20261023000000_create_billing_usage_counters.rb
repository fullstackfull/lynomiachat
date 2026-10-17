class CreateBillingUsageCounters < ActiveRecord::Migration[7.0]
  # METERED USAGE, PERIOD BY PERIOD (P5G).
  #
  # WHY A COUNTER AND NOT A QUERY. Every other ceiling in Billing::ResourceLimit counts rows
  # that EXIST -- agents, inboxes, stores, flows -- and the count is cheap because the rows
  # are the thing being limited. A send quota counts EVENTS INSIDE A PERIOD, and the natural
  # query for that is "campaign_recipients where account_id = ? and sent_at >= ?", which no
  # index on that table serves and which must run once per recipient at the send boundary.
  # On an account with a year of campaign history that is a scan per message.
  #
  # A ROW PER ACCOUNT, RESOURCE AND PERIOD, incremented once per send. The unique index is the
  # arbiter: two workers that both decide to start this period's row cannot both insert one,
  # and the loser re-reads instead of creating a second counter that would silently double the
  # allowance.
  #
  # `period_start` IS A DATE, NOT A TIMESTAMP, and it is the anchor rather than a window: a
  # period is identified by when it began, so "this period's usage" is one equality lookup
  # rather than a range scan, and a period that is later re-anchored produces a new row rather
  # than corrupting the old one. The history is kept -- a merchant disputing a bill, or an
  # operator asked why a campaign stopped, needs last period's number as much as this one's.
  def change
    create_table :billing_usage_counters do |t|
      t.bigint :account_id, null: false
      # A BillingPlan::LIMIT_KEYS key. A string rather than an enum because the key list is
      # already a constant there and a second copy as an enum would be a second thing to keep
      # in step.
      t.string :resource, null: false, limit: 40
      t.date :period_start, null: false
      t.bigint :used, null: false, default: 0
      t.timestamps

      t.index %i[account_id resource period_start], unique: true, name: 'index_billing_usage_counters_on_scope'
    end

    add_foreign_key :billing_usage_counters, :accounts, on_delete: :cascade
  end
end
