# BRINGING AN INSTALLATION INTO EXISTENCE, FOR A PARTNER THAT CAN PROVE IT OWNS THE STORE.
#
# Commerce::InstallationLifecycle deliberately refuses this -- "`activate` from nothing. Bringing
# an installation into existence is provisioning and has its own path with its own checks" -- and
# it was right to: an endpoint that could conjure an active store out of an account id and a
# transition name would be a way around every one of those checks. This is that path, with the
# checks.
#
# UNTIL NOW THERE WAS EXACTLY ONE WAY A `storesyria` STORE COULD BE CONNECTED:
# Api::V1::Accounts::Commerce::StoresController#create, which needs a browser session, an account
# ADMINISTRATOR and the `lsc_` token pasted into a form field. Each of those is correct on its
# own; together they meant a merchant could only get their orders into their inbox by asking a
# Store Syria operator to mint a token and pasting it in by hand. That manual step is the whole
# reason this class exists.
#
# WHAT MAKES IT SAFE IS NOT THE PLATFORM TOKEN. The platform token says WHICH APP is asking and,
# through platform_app_permissibles, WHICH ACCOUNTS it may touch. It says nothing about whether
# the caller is entitled to the STORE it names -- and a partner holding permissibles on a
# thousand merchant accounts must not be able to attach any store to any of them. The proof of
# the store is the credential: Lynomia takes it, presents it back to Store Syria, and keeps the
# identity that comes back only if it is the store the caller declared. A credential minted for
# store A therefore cannot install store B, whatever the request body says, because the refusal
# is made by the system that issued it.
#
# A FACADE OVER Commerce::StoreConnection, like the lifecycle service and for the same reason.
# #attach already holds the account lock, keeps the plan's store limit, reuses a disconnected row,
# refuses to move a store another account holds, asserts encryption is configured and writes the
# audit row. Re-implementing any of that here would be a second set of rules to keep in step.
#
# IDEMPOTENT, BECAUSE THE CALLER WILL RETRY. Store Syria's activation is a merchant clicking a
# button and a response that can be lost on the way back. Asking for an installation that already
# exists with the credential it already has is a no-op that answers `applied: false`, so the
# partner can distinguish "nothing needed doing" from "something changed" without either side
# having to guess whether the first attempt landed.
class Commerce::PartnerInstallation
  # Providers a partner may install server to server, and the credential each one takes. The KEYS
  # are the allow-list, so there is no second list to keep in step with this one.
  #
  # AN ALLOW-LIST RATHER THAN A CHECK FOR ABSENCE. Salla, Zid and Shopify are connected by their
  # own app installations, which carry an OAuth grant the merchant gave in the store's own
  # dashboard; WooCommerce keys belong to the person who generated them. Store Syria is the one
  # provider whose credential is minted by a partner that has already authenticated the merchant
  # itself, which is what makes installing on their behalf meaningful rather than presumptuous.
  CREDENTIAL_FORMATS = {
    'storesyria' => { commerce_token: Commerce::Providers::Storesyria::TOKEN_FORMAT }
  }.freeze

  def self.credential_format(provider) = CREDENTIAL_FORMATS[provider.to_s]

  class Refused < StandardError
    attr_reader :code

    def initialize(code, message = nil)
      @code = code
      super(message || code)
    end
  end

  def initialize(account:, platform_app:)
    @account = account
    @platform_app = platform_app
  end

  # @param external_store_id [String] the installation-qualified id the partner issues itself.
  #   Declared, then PROVED: the credential has to resolve to this same store at the partner, or
  #   nothing is written. See Commerce::Providers::Storesyria#health.
  def apply(provider:, external_store_id:, base_url:, credentials:, name: nil)
    provider = provider.to_s
    external_store_id = external_store_id.to_s
    refuse_provider!(provider)
    refuse_account!

    # One at a time per store, across accounts and across processes -- which is what makes two
    # simultaneous Connect clicks produce one installation rather than two. The unique index
    # underneath would catch a duplicate anyway; the lock is what stops the loser from being a
    # 500 the merchant has to interpret.
    Commerce::StoreLock.with(provider, external_store_id) do
      install(provider, external_store_id, base_url, credentials, name)
    end
  end

  private

  def install(provider, external_store_id, base_url, credentials, name)
    existing = Commerce::Store.find_by(provider: provider, external_store_id: external_store_id)
    return connect(provider, external_store_id, base_url, credentials, name) if existing.nil? || existing.disconnected?

    refuse_claimed!(existing) unless existing.account_id == @account.id
    # A STORE AN OPERATOR SWITCHED OFF IS LEFT ALONE. `disabled` is a Lynomia decision, and a
    # partner call that quietly re-enabled it would be a partner reaching across the boundary to
    # undo it. The state is reported instead, so the merchant's own console can say "suspended"
    # rather than showing a success that contradicts it.
    return result(existing, applied: false) if existing.disabled?
    return result(existing, applied: false) if unchanged?(existing, credentials)

    rotate(existing, credentials)
  end

  # The first connection, and the return of a disconnected one. The row is built carrying the
  # DECLARED id, which is what arms the adapter's identity check: with `external_store_id`
  # already set, #health refuses an identity that does not match it, so the declaration is proved
  # before anything is persisted. A row built without it would simply TAKE whatever identity the
  # store answered with -- correct for a merchant pasting their own key into their own account,
  # and not good enough for a partner naming a store on a merchant's behalf.
  def connect(provider, external_store_id, base_url, credentials, name)
    store = @account.commerce_stores.new(
      provider: provider,
      base_url: Commerce::StoreUrl.parse(base_url).to_s,
      external_store_id: external_store_id,
      created_by: nil,
      metadata: { 'installed_by_app' => @platform_app.name.to_s.first(120) }
    )

    adapter = Commerce::Providers.for(store, credentials: credentials)
    adapter.health

    result(connection.attach(store, adapter.store_identity, credentials, name: name.presence), applied: true)
  end

  # A credential that has moved. #rotate_credentials runs the same health check first, so a token
  # minted for another store cannot be rotated into this row either, and it is also the repair for
  # a store sitting in `needs_reauth` after a token was rejected unattended.
  def rotate(store, credentials)
    result(connection.rotate_credentials(store, credentials), applied: true)
  end

  # The same credential already stored means there is nothing to do. Compared in constant time:
  # this is the one place a caller can ask a question about a stored secret and get a yes/no, and
  # a byte-at-a-time comparison would answer how much of a guess was right.
  def unchanged?(store, credentials)
    return false unless store.active?

    stored = store.credentials
    return false unless stored.is_a?(Hash) && stored.keys.sort == credentials.keys.sort

    credentials.all? do |key, value|
      ActiveSupport::SecurityUtils.secure_compare(stored[key].to_s, value.to_s)
    end
  end

  def connection = Commerce::StoreConnection.new(account: @account, user: nil)

  def refuse_provider!(provider)
    raise Refused.new('provider_not_installable', "#{provider} is not installed by a partner") unless CREDENTIAL_FORMATS.key?(provider)
    raise Refused.new('provider_disabled', "#{provider} is switched off on this installation") unless Commerce::Providers.enabled?(provider)
  end

  # THE INSTALLATION'S OWN WORKSPACE IS NOT A MERCHANT'S. A partner holds a permissible on it --
  # it has to, to send from it -- so the permissible check alone does not exclude it, which is
  # why Platform::Api::V1::AccountsController#index filters it out of listings for exactly this
  # reason. There is no merchant store to attach to it.
  #
  # AND A FEATURE THE PLAN DOES NOT SELL IS A REFUSAL, NOT A SILENT SUCCESS. Every commerce read
  # path checks `lynomia_commerce`, so a store connected into an account without it would be a
  # row that works and a product that does not -- a green light over a dead connection, with the
  # partner's console the only place it looked fine. Granting the feature here is not the
  # alternative: AccountsController#update_resource_features establishes that a capability a plan
  # sells is written only through Billing::OverrideGrant, with a reason and an actor.
  def refuse_account!
    raise Refused.new('platform_owned_account', 'That account is not a merchant workspace') if @account.platform_owned?
    raise Refused.new('commerce_disabled', 'Commerce is not enabled for that account') unless @account.feature_enabled?('lynomia_commerce')
  end

  def refuse_claimed!(_store)
    # Deliberately says nothing about WHICH account holds it. The caller is entitled to know that
    # it cannot have this store, not to learn about another merchant's workspace.
    raise Refused.new('installation_claimed_elsewhere', 'That store is connected to another account')
  end

  # What the partner gets back: the ids it needs to record, the state it needs to render, and
  # whether this call was the one that changed something. No credential, no metadata, no URL.
  def result(store, applied:)
    { provider: store.provider, external_store_id: store.external_store_id,
      commerce_store_id: store.id, name: store.name, status: store.status, applied: applied }
  end
end
