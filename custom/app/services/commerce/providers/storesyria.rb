# Store Syria, the commerce platform this integration is built for, as Lynomia's fifth provider.
#
# IT IS A PROVIDER LIKE THE OTHER FOUR, and deliberately nothing more. Store Syria is the
# authoritative commerce system and Lynomia the authoritative communication one; the boundary is
# this adapter, which READS. There are no order actions here -- supports_actions? stays false --
# because writing to a merchant's orders from a chat window is a product decision nobody has
# made, and the contract on the other side does not expose it.
#
# AUTHENTICATION IS A STORE-BOUND CREDENTIAL, NOT AN ADMIN TOKEN. Store Syria's existing admin
# API tenants every handler through getCurrentStore(), which reads users.current_store -- a
# mutable column written by the store switcher and shared across that person's sessions and
# devices. An adapter bound to it would silently change tenant whenever a merchant clicked a
# different store. So Store Syria exposes a separate /api/lynomia/commerce/v1 surface whose
# credential NAMES the store, and this provider sends nothing that identifies a store at all:
# there is no store id in any path or parameter here, which is also why there is no
# self-declared identifier for an attacker to tamper with.
#
# THE STORE'S OWN VOCABULARY IS MAPPED HERE, NOT THERE. Store Syria has no status enum:
# orders.delivered_status is a plain integer and payment_status is free text with at least ten
# spellings across its ~52 gateway controllers. Normalisation into Commerce::Order's canonical
# values lives in this adapter's Normalizer, exactly as it does for the other four providers,
# so the store is never asked to learn Lynomia's words.
class Commerce::Providers::Storesyria < Commerce::Providers::Base
  API_PATH = '/api/lynomia/commerce/v1'.freeze
  ORDER_PAGE = 50

  def self.enabled? = Commerce::Storesyria::Config.enabled?

  # Store Syria pushes conversation events over the Phase 2 webhook ingress, not commerce ones,
  # and it registers nothing in the store. Both stay false until Phase 3D wires the outbox.
  def self.supports_realtime? = false

  def self.registers_webhooks? = false

  # Read-only, by design. See the class note.
  def self.supports_actions? = false

  # The store reports carts, but offering RECOVERY is a separate decision that Phase 3E gates on
  # a consent model Lynomia does not yet have. Reporting them is safe; messaging about them is not.
  def self.supports_carts? = true

  def self.searches_orders? = true

  def health
    identity = store_identity

    # THE CHECK THAT STOPS A CREDENTIAL REBINDING A CONNECTION. The credential proved WHICH store;
    # where this connection already names one, this proves they are the same store. A mismatch
    # means the token was issued for a different store than the one this row is bound to, and
    # accepting it would serve one merchant's customers and orders under another's connection --
    # which is precisely what rotating a credential must not be able to do.
    #
    # A connection being made for the first time names no store yet: it TAKES the identity the
    # store answers with (Commerce::StoreConnection#claim), and the unique index on
    # (provider, external_store_id) is what stops two accounts claiming the same one.
    claimed = @store.external_store_id
    raise Commerce::Error, 'AUTH_INVALID' if claimed.present? && identity[:external_store_id] != claimed

    true
  end

  def store_identity
    @store_identity ||= begin
      body = get('/store')
      raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_store') unless body.is_a?(Hash)

      external = body['external_store_id'].to_s
      raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_store') if external.empty?

      { external_store_id: external, name: body['name'].to_s.presence || external }
    end
  end

  def find_customers(email: nil, phone: nil)
    raise ArgumentError, 'pass exactly one of email or phone' unless [email, phone].compact.one?

    return by_email(email.to_s.strip.downcase) if email

    by_phone(phone)
  end

  def list_customer_orders(external_customer_id, limit:)
    list("/customers/#{CGI.escape(external_customer_id.to_s)}/orders", limit: [limit, ORDER_PAGE].min)
      .map { |raw| normalize_order(raw) }
  end

  def get_order(external_order_id)
    body = get("/orders/#{CGI.escape(external_order_id.to_s)}")
    raise Commerce::Error, 'NOT_FOUND' unless body.is_a?(Hash) && body['id'].present?

    normalize_order(body)
  end

  # Store Syria numbers an order separately from its id (orders.product_order_id), so the default
  # "look it up by id and keep it if the number matches" would never find one.
  def find_orders(number)
    list('/orders', number: number.to_s).map { |raw| normalize_order(raw) }
  rescue Commerce::Error => e
    raise unless e.code == 'NOT_FOUND'

    []
  end

  def admin_order_url(external_order_id)
    # Built from the store's VALIDATED base_url and a validated id -- never from a URL in a
    # response, which a compromised or misconfigured store could point anywhere.
    URI.join("#{base_uri}/", "order/#{Integer(external_order_id.to_s, 10)}").to_s
  rescue ArgumentError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_order_id')
  end

  def cart_access_problem = nil

  def abandoned_carts(customer_reference: nil, limit: 20)
    params = { limit: limit }
    params[:customer] = customer_reference if customer_reference.present?

    list('/carts/abandoned', params).map { |raw| normalizer.cart(raw) }
  end

  def abandoned_cart(external_cart_id)
    abandoned_carts.find { |cart| cart.external_cart_id == external_cart_id.to_s } ||
      raise(Commerce::Error, 'NOT_FOUND')
  end

  def normalize_customer(raw) = normalizer.customer(raw)

  def normalize_order(raw) = normalizer.order(raw)

  private

  def normalizer = @normalizer ||= Commerce::Providers::Storesyria::Normalizer.new(self, @store)

  # VERIFIED IDENTIFIERS ONLY, on both paths: what the lookup returns is kept only where it really
  # carries the identifier that was asked for, so a loose match in the store cannot become a wrong
  # match here. There is no name search in the contract -- matching a shopper to a conversation by
  # name is how one customer is shown another's orders.
  def by_email(email)
    return [] if email.blank?

    lookup(email: email).select { |customer| customer.emails.include?(email) }
  end

  # The national significant number, not the E.164. A store keeps "+963955111222", "0955111222"
  # and "00963955111222" for the same person, so it matches a suffix of whatever it stored and the
  # full number is what gets verified here.
  def by_phone(phone)
    term = Commerce::Phone.search_term(phone)
    return [] if term.blank?

    lookup(phone: term).select { |customer| customer.phones.include?(phone) }
  end

  # POSTED rather than put in the query: an identifier in a URL is an identifier in the store's
  # access logs, and this one belongs to a customer.
  def lookup(body)
    rows(http.post_json("#{API_PATH}/customers/lookup", body)).map { |raw| normalize_customer(raw) }
  end

  def list(path, params = {}) = rows(get(path, params))

  # The contract always wraps a collection, so a bare array means a different server answered.
  def rows(result)
    data = result.is_a?(Hash) ? result['data'] : nil
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless data.is_a?(Array) && data.all?(Hash)

    data
  end

  def get(path, params = {})
    http.get_json("#{API_PATH}#{path}", params)
  end

  def http
    # Commerce::HttpClient is not optional: it is where SSRF filtering, the pinned-IP connect,
    # the refusal to follow redirects, the body cap, the timeouts and the store-health recording
    # all live. A hand-rolled Net::HTTP here would silently lose every one of them.
    @http ||= Commerce::HttpClient.new(
      base_uri: base_uri,
      authorization: "Bearer #{@credentials.fetch('commerce_token')}",
      log_tag: 'storesyria',
      store: @store
    )
  end

  def base_uri = @base_uri ||= Commerce::StoreUrl.parse(@store.base_url)
end
