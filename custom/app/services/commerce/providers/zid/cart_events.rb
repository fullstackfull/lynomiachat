# Zid's abandoned-cart deliveries, turned into Commerce::CartEvent
# (docs/commerce-production/06-cart-transition-design.md §normalizer).
#
# Zid officially emits `abandoned_cart.created` and `abandoned_cart.completed`, and defines abandonment itself — a cart
# whose checkout is not completed within its own interval of inactivity. Lynomia therefore runs no cart timer: see
# Commerce::CartLifecycle.
#
# TWO THINGS HERE ARE UNVERIFIED AGAINST A LIVE STORE, and both are deliberately confined to this file.
#
# UNVERIFIED(zid-cart-identity). Zid's abandoned-cart schema carries `id`, `cart_id` AND `session_id`, and its
# documentation does not say which is stable across a cart's life. IDENTITY_KEY is the single declared choice, and a
# payload without it is REFUSED rather than falling back to another key: falling back would let two deliveries about
# one cart choose two identities and create two rows, which is worse than refusing one delivery loudly. When a real
# store settles the question, this one constant changes — never the schema, and never by concatenating identifiers.
#
# UNVERIFIED(zid-cart-envelope). Zid's documentation publishes the abandoned-cart object (the REST shape read here)
# but not the webhook envelope, so whether a delivery wraps it, and under which key, is unproven. The resource is read
# from the top level or from a single documented-plausible wrapper, and anything else is refused.
class Commerce::Providers::Zid::CartEvents
  IDENTITY_KEY = 'id'.freeze
  WRAPPER_KEYS = %w[abandoned_cart cart data].freeze
  COMPLETED_PHASE = 'completed'.freeze

  CREATED_EVENT = 'abandoned_cart.created'.freeze
  COMPLETED_EVENT = 'abandoned_cart.completed'.freeze
  EVENTS = [CREATED_EVENT, COMPLETED_EVENT].freeze

  # True when this delivery is about a cart rather than an order. Both arrive at the same endpoint, so the event name
  # is the discriminator — and when a delivery carries none, it is NOT guessed from the payload's shape: misrouting a
  # cart as an order is worse than refusing, and Commerce::Zid::WebhookJob reports the refusal.
  def self.cart_delivery?(payload) = EVENTS.include?(event_name(payload))

  def self.event_name(payload) = payload.is_a?(Hash) ? payload['event'].to_s : ''

  def initialize(payload)
    @payload = payload.is_a?(Hash) ? payload : {}
  end

  # @return [Commerce::CartEvent, nil] nil when the delivery carries no usable cart identity or timestamp.
  def event
    return if resource.blank? || provider_cart_id.blank? || occurred_at.nil?

    Commerce::CartEvent.new(
      kind: kind, provider_cart_id: provider_cart_id, occurred_at: occurred_at, first_seen_at: created_at || occurred_at,
      phase: resource['phase'].presence&.to_s, currency: resource['currency_code'].presence&.to_s, total: total,
      item_count: item_count, customer_reference: customer_reference, order_reference: order_reference
    )
  end

  private

  # The cart's own state decides the kind, not the event name. `phase == 'completed'` and a present `order_id` are the
  # same fields the existing read-through adapter already trusts, and they survive an envelope whose event name is
  # wrong or absent — whereas trusting the name alone would record an abandonment for a cart the provider is telling
  # us is finished.
  def kind
    completed = resource['phase'].to_s == COMPLETED_PHASE || order_reference.present? ||
                self.class.event_name(@payload) == COMPLETED_EVENT
    completed ? :completed : :abandoned
  end

  def resource
    @resource ||= begin
      wrapped = WRAPPER_KEYS.lazy.filter_map { |key| @payload[key] if @payload[key].is_a?(Hash) }.first
      candidate = wrapped || @payload
      candidate.key?(IDENTITY_KEY) ? candidate : {}
    end
  end

  def provider_cart_id = resource[IDENTITY_KEY].to_s.presence

  # `updated_at` is when this state was reached; `created_at` is when the cart was first seen. A delivery with neither
  # cannot be ordered against what is already stored, so #event returns nil for it.
  def occurred_at = time(resource['updated_at']) || time(resource['created_at'])

  def created_at = time(resource['created_at'])

  def time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def total
    value = resource['cart_total']
    BigDecimal(value.to_s) if value.present?
  rescue ArgumentError, TypeError
    nil
  end

  def item_count
    value = resource['products_count']
    Integer(value.to_s, 10) if value.present?
  rescue ArgumentError, TypeError
    nil
  end

  def customer_reference
    id = resource['customer_id']
    id.present? ? id.to_s : nil
  end

  # Only when Zid itself correlated the cart to an order. Lynomia never derives this.
  def order_reference
    id = resource['order_id']
    id.present? ? id.to_s : nil
  end
end
