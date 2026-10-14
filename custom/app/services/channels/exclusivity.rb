# frozen_string_literal: true

# "This channel identity belongs to one holder" -- asked and answered in one place.
#
# WHY A SERVICE AND NOT JUST THE INDEX. The partial unique index on channel_identity_claims is the
# arbiter and nothing here replaces it; two concurrent claims still resolve there. But a raw
# RecordNotUnique escaping to a controller is a 500 and a Sentry event, and the merchant who
# pasted a number their colleague already connected deserves a sentence instead. This turns the
# index's answer into one.
#
# SCOPED TO AN INTEGRATION, DELIBERATELY. An account with no claim is subject to none of this, and
# that is every account on the installation that did not come through a platform app. An
# independent Lynomia customer connecting their own WhatsApp number is not in conflict with
# anybody, and making it one would be a regression for the customers this integration never
# touched.
module Channels::Exclusivity
  module_function

  # @return [ChannelIdentityClaim] the claim now held
  # @raise [Conflict] when another holder has it
  class Conflict < StandardError
    attr_reader :claim

    def initialize(claim)
      @claim = claim
      super('That channel is already connected to another store.')
    end
  end

  def claim!(platform_app:, account:, provider:, identity:, external_owner_ref: nil)
    existing = ChannelIdentityClaim.active.for_identity(provider, identity)
                                   .find_by(platform_app_id: platform_app.id)

    # Re-claiming what you already hold is a no-op, which is what makes a retried request safe.
    return existing if existing && existing.account_id == account.id

    raise Conflict, existing if existing

    create_claim(platform_app, account, provider, identity, external_owner_ref)
  rescue ActiveRecord::RecordNotUnique
    # Lost the race. The winner's row is the authority, and if it is ours the request succeeded
    # twice rather than failing -- which is the correct answer for an idempotent claim.
    winner = ChannelIdentityClaim.active.for_identity(provider, identity)
                                 .find_by!(platform_app_id: platform_app.id)
    return winner if winner.account_id == account.id

    raise Conflict, winner
  end

  def release!(platform_app:, provider:, identity:)
    claim = ChannelIdentityClaim.active.for_identity(provider, identity)
                                .find_by(platform_app_id: platform_app.id)
    claim&.release!
    claim
  end

  # Every active claim an integration holds for one of its holders, for an operator and for the
  # integration's own listing.
  def held_by(platform_app, external_owner_ref: nil)
    scope = ChannelIdentityClaim.active.where(platform_app_id: platform_app.id)
    external_owner_ref.present? ? scope.where(external_owner_ref: external_owner_ref) : scope
  end

  # The claim blocking this account from using this identity, or nil. Used by the Inbox guard.
  def blocking_claim(account, provider, identity)
    ChannelIdentityClaim.active.for_identity(provider, identity)
                        .where.not(account_id: account.id)
                        .find_by(platform_app_id: platform_app_ids_for(account))
  end

  # The integrations that hold THIS account. An account nobody linked has none, and the guard is
  # therefore inert for it.
  def platform_app_ids_for(account)
    PlatformAppPermissible.where(permissible: account).pluck(:platform_app_id)
  end

  def create_claim(platform_app, account, provider, identity, external_owner_ref)
    ChannelIdentityClaim.create!(
      platform_app: platform_app,
      account: account,
      provider: provider,
      identity: identity,
      external_owner_ref: external_owner_ref,
      state: ChannelIdentityClaim::ACTIVE
    )
  end
end
