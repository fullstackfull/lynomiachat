# B10 -- an agent bot is created, changed or removed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Two exclusions. `agent_bots.secret` is the bot's own credential. `bot_config` is an unbounded document that,
# for a Flow Builder bot, holds the whole flow -- whose lifecycle has its own named events already
# (custom/app/services/flows/audit.rb), so auditing the column here would duplicate them with a payload.
#
# A global bot has no account (`belongs_to :account, optional: true`) and so cannot be attributed to a tenant.
# Package B §5 is explicit that an entry with no account must not be written, so it is not.
module Custom::Audit::AgentBot
  extend ActiveSupport::Concern

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :account, on: [:create, :update, :destroy],
            only: %i[name description outgoing_url bot_type], if: :account_scoped?
  end

  def account_scoped?
    account_id.present?
  end
end
