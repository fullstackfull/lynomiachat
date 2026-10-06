# Lynomia Automation's Commerce triggers (docs/automation/04-commerce-triggers.md): the provider-neutral order changes
# Commerce::ContactMetric.record finds, dispatched once through Chatwoot's event dispatcher, so AutomationRuleListener
# runs `commerce_order_*` rules like any other event. Never a provider webhook: by the time a change gets here, the
# provider's endpoint has authenticated and deduplicated the delivery, and Commerce has read and normalized the orders.
#
#   event name      commerce.order_paid … (listener method commerce_order_paid, rule event_name commerce_order_paid)
#   data            contact, link, store and provider ids, the order's number and normalized states, an event id
#   conversation    the rules act on the contact's latest conversation in the account; none, nothing runs
#   once            one run per rule and event id (Redis, a week), so a retried job never repeats a rule
module Automation::CommerceEvents
  # The one cart trigger. `commerce_cart_recovered` is deliberately absent: completion does not prove that Lynomia's
  # outreach caused it, and Zid's own schema carries `reminders_count`, so the store may be reminding the shopper
  # itself. A trigger named "recovered" would invite a rule that reports a recovery nobody can stand behind.
  CART_EVENTS = %w[commerce_cart_abandoned].freeze
  EVENTS = (Commerce::OrderTransitions::EVENTS + CART_EVENTS).freeze
  RUN_TTL = 7.days

  def self.event?(name) = EVENTS.include?(name.to_s)

  def self.dispatch(link, transitions, fetched_at)
    account = link.account
    return unless Automation::Extensions.enabled? && account.feature_enabled?('lynomia_commerce')
    return unless account.automation_rules.active.exists?(event_name: transitions.map(&:event).uniq)

    transitions.each do |transition|
      Rails.configuration.dispatcher.dispatch(transition.event.sub('commerce_', 'commerce.'), Time.zone.now, data(link, transition, fetched_at))
    end
  end

  def self.data(link, transition, fetched_at)
    store = link.store
    { event_name: transition.event, contact: link.contact, link_id: link.id, store_id: store.id, provider: store.provider,
      order: transition.order, event_id: "#{link.id}:#{transition.key}:#{transition.event}:#{fetched_at.to_i}" }
  end

  # One genuine transition into abandoned, dispatched through the same path an order event takes. Called only by
  # Commerce::CartLifecycle, and only when the row actually changed state, so a duplicate or replayed provider
  # delivery cannot re-fire it. A cart with no resolved contact has nobody to act on and dispatches nothing.
  def self.dispatch_cart(cart)
    account = cart.account
    return if cart.contact_id.nil?
    return unless Automation::Extensions.enabled? && account.feature_enabled?('lynomia_commerce')
    return unless account.automation_rules.active.exists?(event_name: 'commerce_cart_abandoned')

    Rails.configuration.dispatcher.dispatch('commerce.cart_abandoned', Time.zone.now, cart_data(cart))
  end

  def self.cart_data(cart)
    { event_name: 'commerce_cart_abandoned', contact: cart.contact, store_id: cart.commerce_store_id,
      provider: cart.provider, cart: cart_context(cart), event_id: "cart:#{cart.id}:abandoned:#{cart.last_provider_event_at.to_i}" }
  end

  # What a rule and an automation webhook may see about the cart. No checkout URL, no line items, no customer
  # contact details: the conversation payload already carries the contact.
  def self.cart_context(cart)
    { id: cart.id, provider_cart_id: cart.provider_cart_id, phase: cart.provider_phase, currency: cart.currency,
      total: cart.visible_total&.to_s, item_count: cart.item_count, abandoned_at: cart.abandoned_at }
  end

  # The conversation a Commerce rule acts on: the contact's latest in the account.
  def self.conversation_for(contact)
    contact.conversations.where(account_id: contact.account_id).order(last_activity_at: :desc, id: :desc).first
  end

  # True the first time a rule runs for an event.
  def self.claim(rule, event_id)
    Redis::Alfred.set("LYNOMIA::AUTOMATION::RUN::#{rule.id}::#{event_id}", 1, nx: true, ex: RUN_TTL.to_i)
  end

  # The Commerce event being handled, for event conditions and the webhook payload.
  def self.with(data)
    previous = ActiveSupport::IsolatedExecutionState[:lynomia_commerce_event]
    ActiveSupport::IsolatedExecutionState[:lynomia_commerce_event] = data
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[:lynomia_commerce_event] = previous
  end

  def self.current = ActiveSupport::IsolatedExecutionState[:lynomia_commerce_event]

  # What an automation webhook carries about the event (no contact data: the conversation payload already has it).
  def self.webhook_context(data)
    { event: data[:event_name], store_id: data[:store_id], provider: data[:provider],
      order: data[:order], cart: data[:cart] }.compact
  end

  private_class_method :data, :cart_data, :cart_context
end
