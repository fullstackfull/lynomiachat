# An integration's claim on one channel identity.
#
# TWO STATES, AND THE MISSING ONES ARE DELIBERATE. The approved lifecycle names eight -- available,
# claiming, active, reauthorization required, disconnected, transfer pending, released, security
# suspended -- and Phase 2 implements the two that something actually writes:
#
#   active     the claim holds; the unique index enforces it
#   released   given up on purpose; kept for history, and no longer blocking
#
# `available` is the absence of a row, not a row. `claiming` needs a two-step onboarding flow that
# Phase 2 deliberately does not expose. `reauthorization required` and `disconnected` are facts
# about the CHANNEL's health, which this fork already reports through Channels::Capability and
# Reauthorizable -- duplicating them here would create a second answer that drifts. `transfer
# pending` and `security suspended` have no writer and no caller.
#
# Phase 1 made exactly this mistake and had to undo it: LinkState carried a SUSPENDED value that
# nothing ever wrote, three places branched on it, and it was reachable only by hand-editing a row.
# A state with no writer is not a state.
class ChannelIdentityClaim < ApplicationRecord
  ACTIVE = 'active'.freeze
  RELEASED = 'released'.freeze
  STATES = [ACTIVE, RELEASED].freeze

  belongs_to :platform_app
  belongs_to :account

  validates :provider, presence: true, inclusion: { in: ->(_claim) { Channels::Capability::ENTRIES.map { |entry| entry.key.to_s } } }
  validates :identity, presence: true
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where(state: ACTIVE) }
  scope :for_identity, ->(provider, identity) { where(provider: provider.to_s, identity: identity) }

  def release!(at: Time.current)
    update!(state: RELEASED, released_at: at)
  end

  def active?
    state == ACTIVE
  end
end
