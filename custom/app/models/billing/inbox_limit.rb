# frozen_string_literal: true

# Validations added to Inbox by config/initializers/billing.rb.
# Applies to every way of creating an inbox -- the dashboard, each provider's OAuth callback, the Platform API.
#
# Two separate commercial rules, which must not be conflated:
#   * how MANY inboxes the plan allows  -> Billing::ResourceLimit, a counted ceiling
#   * WHICH channel types it sells      -> Billing::Entitlements.channel_allowed?, a permission
#
# An account can be within its inbox count and still not be entitled to WhatsApp, and vice versa.
module Billing::InboxLimit
  extend ActiveSupport::Concern

  included do
    validate :billing_inbox_limit, on: :create
    validate :billing_channel_entitlement, on: :create
  end

  private

  def billing_inbox_limit
    return if account.nil?

    limit = Billing::ResourceLimit.exceeded(account, :inboxes) { account.inboxes.count }
    return if limit.nil?

    errors.add(:base, Billing::ResourceLimit.message(:inboxes, limit))
  end

  # The gap P10 named as the one real P11 dependency: nothing could stop an account connecting a channel its
  # plan does not include. Of the twelve channel types only five have an account feature flag at all, and
  # where one exists it hid the tile in the frontend and nothing more -- an administrator posting straight to
  # the inboxes endpoint got the inbox.
  #
  # A plan that names no channels denies none, so this is inert for every plan and account that exists today.
  def billing_channel_entitlement
    return if account.nil? || channel_type.blank?
    return if Billing::Entitlements.channel_allowed?(account, channel_type)

    errors.add(:base, I18n.t('errors.billing.channel_not_included', channel: channel_name_for_error))
  end

  def channel_name_for_error
    Channels::Capability.for_channel_type(channel_type)&.key&.to_s&.humanize || channel_type
  end
end
