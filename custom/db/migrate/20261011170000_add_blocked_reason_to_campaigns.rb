# DECISION 6. A scheduled WhatsApp campaign that cannot send because the capability is unavailable moves to an
# explicit `blocked` state, and this column says WHY in a value a reader can match on rather than in prose.
#
# ADDITIVE, and additive in the way that matters for a rollback: one nullable column with no default and no
# index. The old code does not read it, so a schema that is ahead of the code is not a schema the old code
# trips over, and nothing has to be backfilled -- a campaign that was never blocked has nothing to say here.
#
# The `blocked` state itself needs no migration: `campaign_status` is an integer and the new value is 3, which
# no existing row holds. Rolling the code back leaves any blocked campaign holding a 3 the old enum cannot name,
# and that is INERT rather than broken: `ActiveRecord::Enum::EnumType#cast` returns the raw value for an
# unmapped one, so the old code reads 3, every `active?`/`processing?`/`completed?` is false, and the
# scheduler's `where(campaign_status: :active)` never selects it. `deployment/ROLLBACK.md` records this and the
# `UPDATE` that returns such a campaign to `active` if it has to run under the old code.
class AddBlockedReasonToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :blocked_reason, :string
  end
end
