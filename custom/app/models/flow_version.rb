# A graph of a Lynomia flow bot (docs/flow-builder/03-data-model-and-versioning.md).
#
#   draft      the one editable version of a bot; saved as the builder edits it
#   published  the version new sessions start on; at most one per bot; its graph never changes again
#   archived   a version that was published before (history); sessions started on it finish on it
#
# Publishing turns the draft into the published version and archives the previous one; the next edit starts a new
# draft from the published graph.
class FlowVersion < ApplicationRecord
  belongs_to :account
  belongs_to :agent_bot
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :published_by, class_name: 'User', optional: true
  has_many :flow_sessions, dependent: :delete_all

  enum status: { draft: 0, published: 1, archived: 2 }

  validates :version, presence: true, uniqueness: { scope: :agent_bot_id }
  validate :same_account
  validate :graph_frozen, on: :update

  def nodes = Array(graph['nodes'])

  def edges = Array(graph['edges'])

  def node(id) = nodes.find { |node| node['id'] == id }

  private

  def same_account
    errors.add(:agent_bot, :invalid) unless agent_bot&.flow? && agent_bot.account_id == account_id
  end

  def graph_frozen
    errors.add(:graph, :frozen) if graph_changed? && status_was != 'draft'
  end
end
