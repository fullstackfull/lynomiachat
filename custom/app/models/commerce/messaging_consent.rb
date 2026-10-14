# What a shopper has agreed to receive, and what they have refused.
#
# TWO CLASSES, BECAUSE THEY ARE NOT THE SAME QUESTION.
#
#   transactional  an update about an order this person placed: paid, shipped, delivered,
#                  cancelled, refunded. They started the transaction, and the update is the
#                  service they asked for, so it is allowed unless they said stop.
#   promotional    an abandoned basket, a campaign, anything the shopper did not ask for. It
#                  is refused unless they said yes.
#
# SO THE DEFAULTS ARE OPPOSITE, and that asymmetry is the whole point of the model. Treating
# the two the same means either silencing parcel notifications nobody objected to, or
# marketing at people who never agreed to it. Absence of a row therefore means "allowed" for
# transactional and "not allowed" for promotional; see Commerce::MessagingEligibility, which
# is the only place that reading is applied.
#
# WITHDRAWN AND SUPPRESSED BOTH BLOCK, AND THEY ARE NOT INTERCHANGEABLE. `withdrawn` is the
# shopper's decision and only the shopper reverses it. `suppressed` is this system's: the
# number is unreachable or the provider refused it, and an operator clears it once the cause
# is fixed. Collapsing them into one state would let an operator overturn a person's opt-out
# by clearing what looks like a delivery fault.
class Commerce::MessagingConsent < ApplicationRecord
  self.table_name = 'commerce_messaging_consents'

  PURPOSES = { transactional: 0, promotional: 1 }.freeze
  STATES = { granted: 0, withdrawn: 1, suppressed: 2 }.freeze

  enum :purpose, PURPOSES
  enum :state, STATES, prefix: :consent

  belongs_to :account
  belongs_to :contact

  validates :source, presence: true, length: { maximum: 40 }
  validates :decided_at, presence: true
  validates :contact_id, uniqueness: { scope: :purpose }

  # Blocks a send whoever decided it. A gate asks this, not which of the two it is.
  def blocking? = consent_withdrawn? || consent_suppressed?
end
