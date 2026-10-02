# Lynomia Flow Builder (docs/flow-builder/02-architecture.md): a flow is an AgentBot of type `flow`. It is attached to
# inboxes like any bot (AgentBotInbox) and owns their conversations' bot phase; its graphs are flow_versions and its runs
# flow_sessions. A flow bot belongs to an account, never calls an outgoing URL, and stays a flow bot.
module Custom::AgentBot
  def self.prepended(base)
    base.has_many :flow_versions, dependent: :delete_all
    base.has_many :flow_sessions, dependent: :delete_all
    base.validate :flow_bot_shape, if: :flow?
    base.validate :bot_type_unchanged, on: :update
  end

  def published_flow_version = flow_versions.published.first

  private

  def flow_bot_shape
    errors.add(:account, :blank) if account_id.blank?
    errors.add(:outgoing_url, :present) if outgoing_url.present?
  end

  def bot_type_unchanged
    errors.add(:bot_type, :invalid) if bot_type_changed?
  end
end
