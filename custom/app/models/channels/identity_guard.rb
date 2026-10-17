# frozen_string_literal: true

# The other half of channel exclusivity: the channel row itself.
#
# WHY BOTH HALVES. Channels::ExclusivityGuard sits on Inbox and catches every way an inbox is
# created, which is where a channel is normally first attached. It does not catch a channel whose
# identity is EDITED afterwards -- `@inbox.channel.update!` in the inboxes controller touches the
# channel, not the inbox, so no inbox validation runs. Without this, the rule is evadable in two
# steps: connect a number nobody claimed, then edit it to the one you wanted.
#
# WHY THIS IS NOT IN Custom::Channelable, WHICH IS THE OBVIOUS SEAM. It was, and that was a
# defect. Custom::Channelable is a PLAIN module prepended into the Channelable concern so that it
# overrides the empty `create_audit_log_entry` hook upstream declares, and what it overrides it
# with is the channel configuration audit trail -- the one that records a credential rotation by
# the NAMES of the keys that moved and never by their values. Putting this validation there meant
# rewriting that file, which silently removed that audit entry: the request still succeeded, so
# nothing failed loudly, and two audit specs went red. A guard and an audit log are different
# concerns and they now live in different files.
#
# INJECTED EXPLICITLY, into the ten channel models that have an operator-supplied identity, by
# config/initializers/billing.rb -- the same place and the same way Channels::ExclusivityGuard is
# injected into Inbox, so both halves of the rule are declared in one readable list. `website` and
# `api` are absent because they mint their own identifiers and there is nothing to collide with.
module Channels::IdentityGuard
  extend ActiveSupport::Concern

  included do
    validate :identity_not_claimed_elsewhere
  end

  private

  def identity_not_claimed_elsewhere
    return if account.nil?
    # Only when the identity is actually changing. An unrelated edit -- a provider token refresh,
    # a name change -- must not be refused because somebody else holds a number this channel is
    # not trying to take.
    return unless identity_changing?

    identity = Channels::Identity.for_channel(self)
    return if identity.nil?

    provider, value = identity
    return if Channels::Exclusivity.blocking_claim(account, provider, value).nil?

    errors.add(:base, I18n.t('errors.channels.identity_claimed',
                             default: 'That channel is already connected to another store.'))
  end

  def identity_changing?
    return true if new_record?

    attributes = Channels::Identity::IDENTITY_ATTRIBUTES.values.flatten.map(&:to_s)

    changed.intersect?(attributes)
  end
end
