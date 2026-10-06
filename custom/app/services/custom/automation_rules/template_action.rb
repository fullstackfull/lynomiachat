# The one Automation action that sends an approved WhatsApp template
# (docs/pre-p7-closeout/03-template-automation-action.md).
#
# It exists because a Commerce trigger has to be able to reach a shopper whose 24-hour service window has closed, and
# the only thing WhatsApp permits there is an approved template. Everything it uses already existed:
#
#   the template gate   Flows::Template — the same gate the Send template flow node and the dashboard composer use
#   the send            a Message carrying `template_params`, which Whatsapp::SendOnWhatsappService already routes
#                       to Whatsapp::TemplateProcessorService and the provider's `send_template`
#   the cart's link     Commerce::RecoveryUrl + Commerce::RecoveryMessages.url_digest, the existing recovery path
#   the outreach record Commerce::ActionRun, with the existing `commerce-recovery:` idempotency prefix
#
# So there is no second sender, no second automation engine, no template engine and no Meta call of its own.
#
# Commerce::RecoveryMessages#prepare is deliberately NOT reused: it refuses outside `conversation.can_reply?` and it
# needs an agent `user` and `account_user`. Both are right for a free-form agent message and wrong for a template,
# which exists precisely to speak outside that window. What is reused is its digest, its safe-URL check and its
# ActionRun — the parts that make a sent message recognizable later.
#
# Nothing here falls back to free-form text. A template that cannot be sent is refused and reported; it is never
# replaced by a plain message, because a plain message outside the window is exactly what WhatsApp forbids.
class Custom::AutomationRules::TemplateAction
  Result = Data.define(:reason, :message) do
    def sent? = reason.nil?
  end

  # `{{token}}` substitutions the mapping may use. Anything else, or a token that cannot be resolved right now,
  # refuses the send rather than sending a half-filled template.
  TOKEN = /\{\{\s*([a-z_]+(?:\.[a-z_]+)*)\s*\}\}/
  COPY_CODE_MAX = Flows::Template::COPY_CODE_MAX

  def initialize(rule:, account:, conversation:, config:)
    @rule = rule
    @account = account
    @conversation = conversation
    @config = (config || {}).with_indifferent_access
  end

  def perform
    reason = refusal
    return report(reason) if reason

    template = Flows::Template.find(inbox, @config[:name], @config[:language])
    params = processed_params(template)
    return report('template_param_missing') if params.nil?

    report(nil, send_template(template, params))
  end

  private

  # Every reason the send is refused, in the order an operator should read them: the rule's own configuration first,
  # then the channel, then the template, then the contact.
  def refusal
    return 'inbox_not_in_account' if inbox.nil?
    return 'channel_not_whatsapp' unless inbox.channel.is_a?(Channel::Whatsapp)
    return 'conversation_inbox_mismatch' if @conversation.inbox_id != inbox.id
    return 'contact_unavailable' unless contact_available?

    Flows::Template.problem(inbox, @config[:name], @config[:language])
  end

  # Scoped to the rule's own account, so a rule can never name another account's inbox — and because the template
  # gate reads THIS inbox's synced snapshot, a template belonging to another WABA is simply not found.
  def inbox
    return @inbox if defined?(@inbox)

    @inbox = @account.inboxes.find_by(id: @config[:inbox_id])
  end

  def contact_available?
    contact = @conversation.contact
    contact.present? && !contact.blocked? && @conversation.contact_inbox&.source_id.present?
  end

  # Chatwoot's own processed_params, built from the template's real slots so a mapping cannot invent a parameter the
  # template does not take. nil when any slot the template requires is left unresolved.
  def processed_params(template)
    params = {}
    Flows::Template.slots(template).each do |section, key, kind|
      value = render(Flows::Template.value(@config[:params], section, key)).to_s.strip
      next if value.empty? && kind == :media_name
      return nil unless usable?(value, kind)

      put(params, section, key, kind, value)
    end
    media_type = Flows::Template.media_type(template)
    params['header']['media_type'] = media_type if media_type
    params
  end

  def usable?(value, kind) = !value.empty? && !(kind == :copy_code && value.length > COPY_CODE_MAX)

  def put(params, section, key, kind, value)
    if section == 'buttons'
      (params['buttons'] ||= [])[key] = { 'type' => kind == :copy_code ? 'copy_code' : 'url', 'parameter' => value }
    else
      (params[section] ||= {})[key] = value
    end
  end

  # A mapping value with its tokens filled in, or nil the moment one cannot be resolved.
  def render(raw)
    raw.to_s.gsub(TOKEN) do
      value = token(Regexp.last_match(1))
      return nil if value.blank?

      value
    end
  end

  def token(name)
    return @conversation.contact&.name if name == 'contact.name'
    return recovery_url if name == 'cart.recovery_url'

    cart_token(name)
  end

  # What Automation::CommerceEvents.cart_context already publishes about the cart. Deliberately not the checkout
  # URL, which has its own resolution below, and deliberately not the line items.
  def cart_token(name)
    case name
    when 'cart.total' then cart_context[:total]
    when 'cart.currency' then cart_context[:currency]
    when 'cart.item_count' then cart_context[:item_count]&.to_s
    end
  end

  def cart_context = (Automation::CommerceEvents.current || {})[:cart] || {}

  # The cart's checkout link, read fresh from the store and passed through the existing host allow-list. It is never
  # persisted and never reconstructed from a stored value: P6 deliberately keeps no checkout URL on commerce_carts,
  # because a checkout link is effectively a bearer credential for someone else's basket. When the store is
  # unreachable, the gate is shut or the link fails the allow-list, this returns nil and the send is refused — a
  # fabricated `checkout_url` would be worse than no message.
  def recovery_url
    return @recovery_url if defined?(@recovery_url)

    @recovery_url = resolve_recovery_url
  end

  def resolve_recovery_url
    store = @account.commerce_stores.find_by(id: (Automation::CommerceEvents.current || {})[:store_id])
    return nil if store.nil? || !Commerce::AbandonedCarts.offered?(store)

    cart, = Commerce::AbandonedCarts.new(store: store, conversation: @conversation).fresh(cart_context[:provider_cart_id].to_s)
    Commerce::RecoveryUrl.safe(cart.recovery_url, hosts: Commerce::Providers.for(store).recovery_hosts)
  rescue StandardError => e
    Rails.logger.error("[AUTOMATION TEMPLATE] event=recovery_url_unresolved rule_id=#{@rule.id} error=#{e.class.name}")
    nil
  end

  # One outreach record and one message. The ActionRun is what lets Commerce::RecoveryListener recognise the sent
  # message later and claim `targeted_at` — the same mechanism an agent-prepared recovery message uses, so there is
  # exactly one definition of "a real outreach was accepted for sending".
  def send_template(template, params)
    run = record_outreach
    message_params = { content: Flows::Template.body_text(template), private: false,
                       content_attributes: { automation_rule_id: @rule.id },
                       template_params: Flows::Template.template_params(template, params) }
    Messages::MessageBuilder.new(nil, @conversation, message_params)
                            .perform
                            .tap { |message| run&.update!(metadata: run.metadata.merge('message_id' => message.id)) }
  end

  # Only when the event is about a cart and a link was actually resolved: the run's digest is how the listener
  # matches the outgoing message back to this outreach.
  def record_outreach
    url = defined?(@recovery_url) ? @recovery_url : nil
    store_id = (Automation::CommerceEvents.current || {})[:store_id]
    return nil if url.blank? || store_id.blank?

    Commerce::ActionRun.create!(
      account_id: @account.id, commerce_store_id: store_id, contact_id: @conversation.contact_id,
      conversation_id: @conversation.id, provider: (Automation::CommerceEvents.current || {})[:provider],
      action_type: Commerce::ActionRun::RECOVERY_MESSAGE, external_resource_id: cart_context[:provider_cart_id].to_s,
      idempotency_key: "commerce-recovery:#{SecureRandom.uuid}",
      request_digest: Commerce::RecoveryMessages.url_digest(url),
      metadata: { 'url_digest' => Commerce::RecoveryMessages.url_digest(url), 'automation_rule_id' => @rule.id }
    )
  end

  def report(reason, message = nil)
    return Result.new(reason: nil, message: message) if reason.nil?

    Rails.logger.error("[AUTOMATION TEMPLATE] event=refused rule_id=#{@rule.id} conversation_id=#{@conversation.id} code=#{reason}")
    Result.new(reason: reason, message: nil)
  end
end
