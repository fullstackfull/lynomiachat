# What one caller of the contact activity timeline may see (docs/p9/01-architecture.md §9).
#
# Three inputs that are really one concept, so they travel as one value instead of as three keyword arguments
# that every adapter has to re-declare:
#
#   conversations  this contact's conversations the caller may open, through
#                  Conversations::PermissionFilterService -- the same filter the contact's attachment list uses
#   inbox_ids      the caller's own visible inboxes, for the sources that carry an inbox but no conversation
#   user           the caller, for a source whose visibility is OWNERSHIP rather than channel and so cannot be
#                  narrowed from either of the other two (support cases)
Contacts::ActivityTimeline::Visibility = Data.define(:user, :conversations, :inbox_ids)
