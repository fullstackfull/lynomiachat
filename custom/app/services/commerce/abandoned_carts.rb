# The conversation contact's abandoned carts in one store (docs/commerce/30-abandoned-carts.md). Read from the store
# through the cache, never stored in Postgres; only carts that belong to the contact by one of these, in this order:
#
#   linked_customer  the cart's customer is the contact's linked store customer (a trusted link)
#   verified_phone   the cart's phone is exactly the phone of the conversation's channel identity (WhatsApp, SMS)
#   verified_email   the cart's email is exactly the email of the conversation's channel identity (an email inbox)
#
# Never by name, never by a masked value, never by the contact's agent-editable fields. A cart of another store customer
# than the linked one, or of the customer an agent unlinked, never matches; neither does any cart when the verified
# phone or email belongs to several store customers (ambiguous). The cache keeps only the matched carts, without their
# email, phone or recovery link.
class Commerce::AbandonedCarts
  FETCH_LIMIT = 20
  SHOWN = 5
  MAX_AGE = 30.days
  PUBLIC_FIELDS = %w[external_cart_id created_at updated_at currency total items status recovered_at provider_metadata].freeze

  def self.offered?(store)
    store.active? && Commerce::Switches.provider_recovery_enabled?(store.provider) &&
      Commerce::Providers::REGISTRY.fetch(store.provider).constantize.supports_carts?
  end

  def initialize(store:, conversation:)
    @store = store
    @conversation = conversation
    @contact = conversation.contact
  end

  def list(force: false)
    blocked = blocker
    return base.merge(blocked, carts: []) if blocked

    result = Commerce::Cache.fetch(@store, :carts, cache_identifier, force: force) { matched(read_carts).map { |cart| public_json(cart) } }
    base.merge(state: 'ok', carts: shown(result.value), fetched_at: result.fetched_at, stale: result.stale, error: result.error)
  rescue Commerce::Error => e
    Commerce::StoreConnection.new(account: @store.account, user: nil).credentials_rejected(@store) if e.code == 'AUTH_INVALID'
    base.merge(state: 'unavailable', error: e.code, carts: [])
  end

  # One cart read from the store now, still the contact's (Commerce::RecoveryMessages): its match, or NOT_FOUND.
  def fresh(external_cart_id)
    cart = provider.abandoned_cart(external_cart_id)
    match = matched([cart]).first
    raise Commerce::Error, 'NOT_FOUND' if match.nil?

    [cart, match[:match]]
  end

  def cache_identifier = "contact:#{@contact.id}:#{identity[:link]}"

  def provider
    @provider ||= Commerce::Providers.for(@store)
  end

  private

  # Why the store's carts are not read for this contact, or nil.
  def blocker
    return { state: 'unavailable', error: 'RECOVERY_DISABLED' } unless self.class.offered?(@store)

    problem = provider.cart_access_problem
    return { state: 'unavailable', error: 'PERMISSION_DENIED', reason: problem } if problem

    { state: 'no_identity' } if identity.values_at(:link, :phone, :email).none?
  end

  def read_carts
    Commerce::Metrics.event('commerce.cart.fetch', provider: @store.provider, store_id: @store.id)
    provider.abandoned_carts(customer_reference: identity[:link], limit: FETCH_LIMIT)
  end

  # [{ cart:, match: }] of the carts that are the contact's.
  def matched(carts)
    by_identity = carts.reject { |cart| foreign?(cart.customer_reference) }
                       .filter_map { |cart| (match = match_of(cart)) && { cart: cart, match: match } }
    ambiguous = ambiguous?(by_identity)
    result = ambiguous ? by_identity.select { |entry| entry[:match] == 'linked_customer' } : by_identity
    Commerce::Metrics.event('commerce.cart.matched', provider: @store.provider, store_id: @store.id, carts: result.size, ambiguous: ambiguous)
    result
  end

  # A verified phone or email found on carts of several store customers says nothing about which one is the contact.
  def ambiguous?(entries)
    entries.reject { |entry| entry[:match] == 'linked_customer' }.filter_map { |entry| entry[:cart].customer_reference }.uniq.many?
  end

  def match_of(entry)
    return 'linked_customer' if identity[:link].present? && entry.customer_reference == identity[:link]
    return 'verified_phone' if identity[:phone].present? && entry.phone == identity[:phone]

    'verified_email' if identity[:email].present? && entry.email == identity[:email]
  end

  # Another store customer than the linked one, or the one an agent unlinked.
  def foreign?(reference)
    reference.present? && (reference == identity[:suppressed] || (identity[:link].present? && reference != identity[:link]))
  end

  def identity
    @identity ||= begin
      links = @store.customer_links.where(contact: @contact)
      link = links.not_suppressed.first&.external_customer_id
      { link: link&.start_with?('guest:') ? nil : link, suppressed: links.suppressed.first&.external_customer_id,
        phone: Commerce::CustomerMatcher.new(store: @store, conversation: @conversation).trusted_phone, email: trusted_email }
    end
  end

  # The address an email conversation arrived from: the channel identity, not the contact's editable email.
  def trusted_email
    return unless @conversation.inbox.channel.is_a?(Channel::Email)

    email = @conversation.contact_inbox&.source_id.to_s.strip.downcase
    email if email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def public_json(entry)
    entry[:cart].to_h.stringify_keys.slice(*PUBLIC_FIELDS).merge('match' => entry[:match])
  end

  # Abandoned and recent only: a recovered or expired cart is never offered.
  def shown(carts)
    carts.select { |cart| cart['status'] == 'abandoned' && cart['created_at'].present? && Time.iso8601(cart['created_at']) > MAX_AGE.ago }
         .sort_by { |cart| cart['updated_at'] || cart['created_at'] }.reverse.first(SHOWN)
  end

  def base
    { store: { id: @store.id, name: @store.name, provider: @store.provider } }
  end
end
