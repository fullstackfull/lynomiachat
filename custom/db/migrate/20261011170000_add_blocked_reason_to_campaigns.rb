# DECISION 6. A scheduled WhatsApp campaign that cannot send because the capability is unavailable moves to an
# explicit `blocked` state, and this column says WHY in a value a reader can match on rather than in prose.
#
# ADDITIVE, and additive in the way that matters for a rollback: one nullable column with no default and no
# index. The old code does not read it, so a schema that is ahead of the code is not a schema the old code
# trips over, and nothing has to be backfilled -- a campaign that was never blocked has nothing to say here.
#
# The `blocked` state itself needs no migration: `campaign_status` is an integer and the new value is 3, which
# no existing row holds. Rolling the code back leaves any blocked campaign holding a 3 that the old enum cannot
# name, which is why `Campaign#unblock!` exists and why the rollback note in deployment/ROLLBACK.md says to
# move blocked campaigns back to active BEFORE rolling the code back.
class AddBlockedReasonToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :blocked_reason, :string
  end
end
