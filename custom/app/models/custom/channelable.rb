# frozen_string_literal: true

# The other half of channel exclusivity: the channel row itself.
#
# WHY BOTH HALVES. Channels::ExclusivityGuard sits on Inbox and catches every way an inbox is
# created, which is where a channel is normally first attached. It does not catch a channel whose
# identity is EDITED afterwards -- `@inbox.channel.update!` in the inboxes controller touches the
# channel, not the inbox, so no inbox validation runs. Without this, the rule is evadable in two
# steps: connect a number nobody claimed, then edit it to the one you wanted.
#
# Channelable already resolves through prepend_mod_with, so this applies to all twelve channel
# models without editing any of them.
module Custom::Channelable
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
