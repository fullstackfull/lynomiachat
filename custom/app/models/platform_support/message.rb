# One message in a Platform Support ticket's public thread
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M4, §2).
#
# EVERY ROW HERE IS VISIBLE TO THE CUSTOMER. There is no visibility column, because a staff-only note is a row
# in PlatformSupport::InternalNote -- a different table the tenant's controllers, serializers and query objects
# have no association, no constant and no table name for.
#
# `author_type` is a frozen three-value allow-list and NOT a polymorphic association. `System` is not a record:
# it is how the product itself speaks in a thread, so a `belongs_to :author, polymorphic: true` would try to
# constantize it on every read. `author_id` is therefore NULL for `System` and required for the other two.
#
# WHAT A CUSTOMER SEES OF AN OPERATOR: the literal "Lynomia Support" and nothing else. The column holds the
# real author's name, which the staff surface renders and the audit trail needs; `#display_author_name` is the
# one place that decides what a tenant is told, so no serializer has to remember.
class PlatformSupport::Message < ApplicationRecord
  self.table_name = 'platform_support_messages'

  CUSTOMER_AUTHOR_TYPE = 'User'.freeze
  OPERATOR_AUTHOR_TYPE = 'PlatformSupport::Agent'.freeze
  SYSTEM_AUTHOR_TYPE = 'System'.freeze
  AUTHOR_TYPES = [CUSTOMER_AUTHOR_TYPE, OPERATOR_AUTHOR_TYPE, SYSTEM_AUTHOR_TYPE].freeze

  # Never an individual operator's name. One support desk speaks to the customer, not eleven people.
  OPERATOR_DISPLAY_NAME = 'Lynomia Support'.freeze

  MAX_BODY = 10_000
  FILES_ATTACHMENT_NAME = :platform_support_message_files

  # The whole realistic set for a complaint: a screenshot, an invoice and a log excerpt. Archives are excluded
  # because a zip cannot be inspected and is the standard malware carrier, and this installation has no
  # scanner.
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp application/pdf text/plain text/csv].freeze
  MAX_FILE_BYTES = 10.megabytes
  MAX_FILES = 5

  belongs_to :ticket, class_name: 'PlatformSupport::Ticket', foreign_key: :platform_support_ticket_id,
                      inverse_of: :messages

  has_many_attached FILES_ATTACHMENT_NAME

  validates :author_type, inclusion: { in: AUTHOR_TYPES }
  validates :author_name, presence: true, length: { maximum: 255 }
  # Plain text. There is no HTML column, no markdown column and no rich editor in this module, which is the
  # whole of its XSS story: both renderers escape by default, so there is nothing to sanitize.
  validates :body, presence: true, length: { maximum: MAX_BODY }
  validate :author_id_matches_author_type

  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }

  # The author triple, derived in one place rather than at each writer, so no caller can file a message under
  # the wrong party or under somebody else's name. `nil` is the product speaking as itself.
  def self.author_attributes_for(author)
    case author
    when nil
      { author_type: SYSTEM_AUTHOR_TYPE, author_id: nil, author_name: OPERATOR_DISPLAY_NAME }
    when PlatformSupport::Agent
      { author_type: OPERATOR_AUTHOR_TYPE, author_id: author.id, author_name: author.display_name }
    when ::User
      { author_type: CUSTOMER_AUTHOR_TYPE, author_id: author.id, author_name: author.available_name }
    else
      raise ArgumentError, "#{author.class.name} cannot author a platform support message"
    end
  end

  def customer? = author_type == CUSTOMER_AUTHOR_TYPE

  # What the tenant serializer emits. `lynomia` covers an operator and the product itself, because from the
  # customer's side both are Lynomia speaking.
  def author_role
    customer? ? 'customer' : 'lynomia'
  end

  def display_author_name
    customer? ? author_name : OPERATOR_DISPLAY_NAME
  end

  private

  def author_id_matches_author_type
    if author_type == SYSTEM_AUTHOR_TYPE
      errors.add(:author_id, 'must be empty for a system message') if author_id.present?
    elsif author_id.blank?
      errors.add(:author_id, 'is required')
    end
  end
end
