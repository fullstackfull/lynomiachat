# Lynomia Support (docs/p9/01-architecture.md §6): a conversation may raise several support cases, and a case
# links to at most one conversation. One thread raising two issues is the realistic shape; one case spanning
# several threads is not, and a join table for it would be speculative.
#
# No `dependent:`: support_tickets.conversation_id carries an ON DELETE SET NULL foreign key, so deleting a
# conversation leaves the case and its history intact with the link cleared.
module Custom::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    has_many :support_tickets, class_name: 'Support::Ticket', inverse_of: :conversation, dependent: nil
  end
end
