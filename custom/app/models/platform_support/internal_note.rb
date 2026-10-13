# A staff-only working note on a Platform Support ticket
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M5, §3).
#
# NEVER PUBLIC, and that is a property of the table rather than of a predicate. There is no tenant route whose
# controller could render one of these, no tenant serializer key for one, and no association reachable from a
# tenant-visible object. The `internal_note_added` event type is excluded from
# PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES as well, so the EXISTENCE of a note is hidden too.
#
# No `author_type`: a note is always written by a Lynomia agent, so the column would hold one value forever.
# `agent_id` is required and its foreign key takes no action on delete, so the record of who wrote an internal
# decision cannot be erased by removing the person -- see the migration for why that is the deliberate choice.
#
# An attachment on a note is staff-only BECAUSE OF THIS CLASS: the download endpoint authorizes the parent
# record through the tenant policy scope, which has no path to this table, so a tenant request for a note's
# attachment 404s as a consequence of the parent lookup and not as a special case anybody has to remember.
class PlatformSupport::InternalNote < ApplicationRecord
  self.table_name = 'platform_support_internal_notes'

  MAX_BODY = 10_000
  FILES_ATTACHMENT_NAME = :platform_support_note_files

  belongs_to :ticket, class_name: 'PlatformSupport::Ticket', foreign_key: :platform_support_ticket_id,
                      inverse_of: :internal_notes
  belongs_to :agent, class_name: 'PlatformSupport::Agent', inverse_of: :internal_notes

  has_many_attached FILES_ATTACHMENT_NAME

  validates :author_name, presence: true, length: { maximum: 255 }
  validates :body, presence: true, length: { maximum: MAX_BODY }

  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }

  before_validation :snapshot_author_name

  private

  # Snapshotted from the agent row rather than accepted from a caller, so a note stays attributable and no
  # caller can file one under somebody else's name.
  def snapshot_author_name
    self.author_name = agent.display_name if agent.present?
  end
end
