# Preparing a recovery message for one of the conversation contact's abandoned carts (docs/commerce/31-sales-recovery.md).
# Lynomia never sends it: the agent reviews the cart, prepares the message, which lands in the reply box, and presses
# Send. A prepared message is a pending Commerce::ActionRun (recovery_message); the conversation's outgoing message
# carrying its link marks it sent (Commerce::RecoveryListener).
#
# Before a message is prepared:
#   - the installation offers the store's carts (Commerce::Switches)
#   - the conversation can receive a free-form message now (Conversation#can_reply?: WhatsApp's 24-hour window and the
#     other channels' windows); outside it nothing is prepared and the agent is told why
#   - the cart is read again from the store: still the contact's, still abandoned, not expired
#   - its recovery link passes Commerce::RecoveryUrl for the store's hosts
#   - no recovery message for the cart was sent within the cooldown (Commerce::Switches.recovery_cooldown), unless an
#     administrator overrides it for this one message
#   - at most PREPARE_LIMIT preparations per agent per hour
class Commerce::RecoveryMessages
  PREPARE_LIMIT = 30
  ACTION_TYPE = Commerce::ActionRun::RECOVERY_MESSAGE

  def initialize(store:, conversation:, user:, account_user:)
    @store = store
    @conversation = conversation
    @user = user
    @account_user = account_user
  end

  # { cart id => { prepared_at:, sent_at:, cooldown_until: } } for the panel.
  def self.states(store, cart_ids)
    cooldown = Commerce::Switches.recovery_cooldown
    runs = Commerce::ActionRun.where(commerce_store_id: store.id, action_type: ACTION_TYPE, external_resource_id: cart_ids)
                              .where(created_at: [cooldown, Commerce::AbandonedCarts::MAX_AGE].max.ago..).group_by(&:external_resource_id)
    cart_ids.index_with { |cart_id| state(runs.fetch(cart_id, []), cooldown) }
  end

  def self.state(runs, cooldown)
    sent = runs.select(&:succeeded?).filter_map(&:completed_at).max
    { prepared_at: runs.map(&:created_at).max&.to_i, sent_at: sent&.to_i, cooldown_until: sent ? (sent + cooldown).to_i : nil }
  end

  private_class_method :state

  # How a sent message is recognized: the link it carries, never stored as such.
  def self.url_digest(url) = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "recovery:#{url}")

  def prepare(cart_id, override_cooldown: false)
    raise Commerce::Error, 'RECOVERY_DISABLED' unless Commerce::AbandonedCarts.offered?(@store)
    raise Commerce::Error.new('CANNOT_REPLY', reason: 'messaging_window') unless @conversation.can_reply?

    throttle!
    cart, match = Commerce::AbandonedCarts.new(store: @store, conversation: @conversation).fresh(cart_id.to_s)
    url = checked_url(cart)
    check_cooldown!(cart, override_cooldown)
    run = record(cart, url, match, override_cooldown)
    message(cart, url).merge(run_id: run.id)
  end

  private

  def checked_url(cart)
    expired = cart.created_at.present? && Time.iso8601(cart.created_at) < Commerce::AbandonedCarts::MAX_AGE.ago
    raise Commerce::Error.new('CART_NOT_ABANDONED', reason: expired ? 'expired' : cart.status) if cart.status != 'abandoned' || expired

    Commerce::RecoveryUrl.safe(cart.recovery_url, hosts: Commerce::Providers.for(@store).recovery_hosts) ||
      raise(Commerce::Error, 'INVALID_RECOVERY_URL')
  end

  def check_cooldown!(cart, override)
    sent = Commerce::ActionRun.where(commerce_store_id: @store.id, action_type: ACTION_TYPE, external_resource_id: cart.external_cart_id)
                              .succeeded.where(completed_at: Commerce::Switches.recovery_cooldown.ago..).maximum(:completed_at)
    return if sent.nil?
    raise Pundit::NotAuthorizedError if override && !@account_user.administrator?
    return if override

    raise Commerce::Error.new('RECOVERY_COOLDOWN', reason: (sent + Commerce::Switches.recovery_cooldown).to_i.to_s)
  end

  def record(cart, url, match, override)
    Commerce::ActionRun.create!(
      account_id: @store.account_id, store: @store, contact_id: @conversation.contact_id, conversation_id: @conversation.id,
      requested_by: @user, provider: @store.provider, action_type: ACTION_TYPE, external_resource_id: cart.external_cart_id,
      idempotency_key: "commerce-recovery:#{SecureRandom.uuid}", request_digest: self.class.url_digest(url),
      metadata: { 'url_digest' => self.class.url_digest(url), 'total' => cart.total, 'currency' => cart.currency, 'match' => match,
                  'override_cooldown' => override.presence }.compact
    ).tap do |run|
      Commerce::AuditTrail.record('commerce.recovery.prepared', auditable: run, user: @user,
                                                                changes: { store_id: @store.id, cart_id: cart.external_cart_id, match: match,
                                                                           override_cooldown: override.presence }.compact)
      Commerce::Metrics.event('commerce.recovery.prepared', provider: @store.provider, store_id: @store.id, run_id: run.id)
    end
  end

  # What the reply box needs; the agent's browser writes the message in the agent's language.
  def message(cart, url)
    { recovery_url: url, first_name: first_name, total: cart.total, currency: cart.currency, store: { id: @store.id, name: @store.name },
      items_count: cart.items.sum { |item| item[:quantity].to_i } }
  end

  # The contact's first name as Chatwoot knows it, when it is a name and not a phone number or an email.
  def first_name
    first = @conversation.contact.name.to_s.strip.split.first
    first if first.present? && first.match?(/\A\p{L}[\p{L}\p{M}'-]*\z/)
  end

  def throttle!
    key = "COMMERCE::RECOVERY_PREPARE::ACCOUNT::#{@store.account_id}::USER::#{@user.id}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.hour.to_i) if count == 1
    raise Commerce::Error.new('RATE_LIMITED', reason: [Redis::Alfred.ttl(key).to_i, 1].max.to_s) if count > PREPARE_LIMIT
  end
end
