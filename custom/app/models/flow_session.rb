# Where one conversation is in a published flow version (docs/flow-builder/05-runtime-and-session.md).
#
#   active      running automatic nodes (inside the runner's per-conversation lock)
#   waiting     at a node waiting for the customer's reply or a timer (wake_at, step_token)
#   handed_off  ended by a handoff: the conversation belongs to humans (Conversation#bot_handoff!)
#   completed   reached an End node
#   failed      stopped on an error or a safety limit (failure_code), then handed off
#   cancelled   ended from outside: disabled flow, resolved or deleted conversation, kill switch
#
# context holds only the run's own small values (answers, the chosen order number), never messages or customer records.
class FlowSession < ApplicationRecord
  LIVE = %w[active waiting].freeze

  belongs_to :account
  belongs_to :agent_bot
  belongs_to :flow_version
  belongs_to :conversation

  enum status: { active: 0, waiting: 1, handed_off: 2, completed: 3, failed: 4, cancelled: 5 }

  scope :live, -> { where(status: LIVE) }

  validate :same_account

  def live? = LIVE.include?(status)

  private

  def same_account
    return if [agent_bot&.account_id, flow_version&.account_id, conversation&.account_id].all?(account_id)

    errors.add(:account, :invalid)
  end
end
