# frozen_string_literal: true

# Refuses an inbox whose channel identity another store already holds.
#
# INJECTED INTO Inbox BY config/initializers/billing.rb, for the reason that initializer already
# exists: inbox creation has NINE production call sites in this fork -- the agent API, five OAuth
# callbacks, two WhatsApp services, the widget onboarding service and the email migration
# endpoint -- and only Inbox validation is downstream of all of them. A guard on the controller
# would be bypassed by six of them. Billing::InboxLimit solved the same problem the same way and
# this follows it rather than inventing a second mechanism.
#
# ON EVERY SAVE, NOT ONLY ON CREATE. A channel's identity is mutable after creation:
# :phone_number is in Channel::Whatsapp::EDITABLE_ATTRS and Channel::Sms::EDITABLE_ATTRS, :email
# in Channel::Email::EDITABLE_ATTRS, and the inboxes controller applies them with
# `@inbox.channel.update!`. A create-only rule is therefore evadable in two steps: connect an
# unclaimed number, then edit it to the one you wanted. The channel-side half of that evasion is
# closed in Custom::Channelable, which validates the channel row itself.
#
# INERT FOR EVERY ACCOUNT NO INTEGRATION HOLDS, which is every account that did not come from one.
module Channels::ExclusivityGuard
  extend ActiveSupport::Concern

  included do
    validate :channel_identity_not_claimed_elsewhere
  end

  private

  def channel_identity_not_claimed_elsewhere
    return if account.nil? || channel.nil?

    identity = Channels::Identity.for_channel(channel)
    return if identity.nil?

    provider, value = identity
    return if Channels::Exclusivity.blocking_claim(account, provider, value).nil?

    errors.add(:base, I18n.t('errors.channels.identity_claimed',
                             default: 'That channel is already connected to another store.'))
  end
end
