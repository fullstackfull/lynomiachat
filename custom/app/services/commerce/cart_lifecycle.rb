# Applies one Commerce::CartEvent to the durable cart row
# (docs/commerce-production/06-cart-transition-design.md).
#
# This is NOT a second Commerce engine and NOT an Automation engine: it writes one row and, on a genuine transition
# into abandoned, hands the existing Automation::CommerceEvents registry a dispatch. Everything else — conditions,
# actions, execution logging, the once-per-rule claim — stays where it already is.
#
# THREE RULES GOVERN EVERY WRITE.
#
# 1. FORWARD ONLY. abandoned -> completed, never back. A late `created` for a cart the provider has already reported
#    completed is a state regression and is recorded, not applied.
# 2. PROVIDER TIME ONLY. An event older than the row's `last_provider_event_at` is ignored. Lynomia's clock never
#    decides ordering, so a redelivery days later cannot overtake what it carries.
# 3. NO CLOCK CREATES STATE. Abandonment arrives only as a provider event. There is no inactivity timer, so a Zid
#    outage or a webhook Zid has marked broken produces no transitions at all — silence is not a signal. This is
#    why provider-outage safety needs no code: there is nothing to switch off.
#
# Concurrency: the row is upserted under the existing Commerce::StoreLock, keyed by the store and the cart, so two
# workers handling a duplicate or a near-simultaneous created/completed pair serialize instead of racing. The unique
# index on (commerce_store_id, provider_cart_id) is the backstop if a lock is ever lost.
class Commerce::CartLifecycle
  Result = Data.define(:cart, :transition, :reason) do
    def transitioned? = transition.present?
  end

  def initialize(store)
    @store = store
  end

  # @return [Result] the row and the transition that happened, or the reason none did.
  def apply(event)
    return Result.new(cart: nil, transition: nil, reason: 'provider_carts_disabled') unless ingestible?

    result = Commerce::StoreLock.with('commerce_cart', "#{@store.id}:#{event.provider_cart_id}") { apply_to_row(event) }
    dispatch(result) if result.transitioned?
    report(result, event)
    result
  end

  private

  # The same gate the read-through viewer uses, so a provider whose carts are PRE_UAT ingests nothing either. A Zid
  # store therefore records no cart lifecycle until a real UAT clears it.
  def ingestible?
    Commerce::AbandonedCarts.offered?(@store)
  end

  def apply_to_row(event)
    cart = Commerce::Cart.find_by(commerce_store_id: @store.id, provider_cart_id: event.provider_cart_id)
    return create(event) if cart.nil?
    return Result.new(cart: cart, transition: nil, reason: 'stale_event') if stale?(cart, event)
    return Result.new(cart: cart, transition: nil, reason: 'state_regression') if regression?(cart, event)

    update(cart, event)
  end

  def create(event)
    identity = { account_id: @store.account_id, commerce_store_id: @store.id, provider: @store.provider,
                 provider_cart_id: event.provider_cart_id, first_seen_at: event.first_seen_at }
    cart = Commerce::Cart.create!(attributes(event).merge(identity, link_attributes(event)))
    # A completion that arrives before any abandonment creates the row directly in `completed`, with the provider's
    # own abandonment time: the cart was abandoned, Lynomia simply never saw that delivery.
    Result.new(cart: cart, transition: cart.state, reason: nil)
  rescue ActiveRecord::RecordNotUnique
    Result.new(cart: Commerce::Cart.find_by(commerce_store_id: @store.id, provider_cart_id: event.provider_cart_id),
               transition: nil, reason: 'already_recorded')
  end

  def update(cart, event)
    changed = cart.state != event.kind.to_s
    cart.update!(attributes(event).merge(link_attributes(event)))
    Result.new(cart: cart, transition: changed ? cart.state : nil, reason: changed ? nil : 'no_change')
  end

  # Rule 2. Equal timestamps are NOT stale: a provider that stamps a created and a completed identically must still
  # be able to move the cart forward, and rule 1 stops it moving back.
  def stale?(cart, event) = event.occurred_at < cart.last_provider_event_at

  # Rule 1.
  def regression?(cart, event) = cart.completed? && event.abandoned?

  # The state and the provider's event time are always written. The descriptive fields are written only when the
  # delivery carries them, so a sparser later event cannot blank what an earlier one established.
  def attributes(event)
    core = { state: event.kind, last_provider_event_at: event.occurred_at }
    core[:completed_at] = event.occurred_at if event.completed?
    core[:abandoned_at] = event.first_seen_at if event.first_seen_at
    descriptive = { provider_phase: event.phase, currency: event.currency, visible_total: event.total,
                    item_count: event.item_count, provider_order_id: event.order_reference }
    descriptive.compact.merge(core)
  end

  # The contact is resolved from the store's existing customer links — never by matching names or by a fresh provider
  # read. A cart whose customer is not linked is still recorded, with no contact: the row is the lifecycle, and
  # targeting needs a contact, so an unlinked cart simply cannot be targeted.
  def link_attributes(event)
    link = event.customer_reference.presence &&
           @store.customer_links.not_suppressed.find_by(external_customer_id: event.customer_reference)
    { external_customer_id: event.customer_reference, commerce_customer_link_id: link&.id, contact_id: link&.contact_id }
  end

  def dispatch(result)
    Automation::CommerceEvents.dispatch_cart(result.cart) if result.transition == 'abandoned'
  end

  def report(result, event)
    Commerce::Metrics.event('commerce.cart.transition', provider: @store.provider, store_id: @store.id,
                                                        transition: result.transition, reason: result.reason,
                                                        kind: event.kind)
  end
end
