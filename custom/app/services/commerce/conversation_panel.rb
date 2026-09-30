# What the conversation's Commerce section shows for one store, and the agent actions on it (search, link, unlink).
# The caller has already authorized the conversation; everything here is scoped to that conversation's contact and to
# a store of the same account.
#
# Candidates reach the browser masked, with an encrypted token (store, contact, customer, 15 min): linking accepts only
# a token issued for this conversation's contact, so a customer id cannot be forged to read another customer's orders,
# and the token does not reveal the masked email or phone.
class Commerce::ConversationPanel
  ORDER_LIMIT = 5
  TOKEN_TTL = 15.minutes
  TOKEN_PURPOSE = :commerce_customer_link

  def initialize(store:, conversation:, user:)
    @store = store
    @conversation = conversation
    @contact = conversation.contact
    @user = user
  end

  def show
    match = Commerce::CustomerMatcher.new(store: @store, conversation: @conversation).call
    match.link ? linked(match.link) : unlinked(match)
  rescue Commerce::Error => e
    store_error!(e)
    base.merge(state: 'unavailable', error: e.code)
  end

  def search(query)
    criteria = search_criteria(query.to_s.strip)
    raise Commerce::Error, 'INVALID_QUERY' if criteria.nil?

    { candidates: provider.find_customers(**criteria).map { |customer| candidate(customer) } }
  rescue Commerce::Error => e
    store_error!(e)
    raise
  end

  def link(token)
    data = decrypt(token)
    raise Commerce::Error, 'NOT_FOUND' unless data && data['store_id'] == @store.id && data['contact_id'] == @contact.id

    save_link(data['external_customer_id'])
    show
  end

  def unlink
    link = @store.customer_links.find_by!(contact: @contact)
    link.destroy!
    Commerce::AuditTrail.record('commerce.customer_link_removed', auditable: link, user: @user, changes: { match_source: link.match_source })
  end

  private

  def linked(link)
    orders = Commerce::Cache.fetch(@store, :orders, link.external_customer_id) do
      provider.list_customer_orders(link.external_customer_id, limit: ORDER_LIMIT)
    end
    base.merge(state: 'linked', link: link_json(link), orders: orders.value, fetched_at: orders.fetched_at, stale: orders.stale,
               error: orders.error)
  rescue Commerce::Error => e
    store_error!(e)
    base.merge(state: 'linked', link: link_json(link), orders: nil, error: e.code)
  end

  def unlinked(match)
    candidates = match.verified.presence || match.suggested
    state = if candidates.empty? then 'not_found'
            elsif candidates.many? then 'multiple'
            else
              'suggested'
            end
    base.merge(state: state, candidates: candidates.map { |customer| candidate(customer) }, fetched_at: match.fetched_at,
               stale: match.stale, error: match.error)
  end

  def save_link(external_customer_id)
    link = @store.customer_links.find_or_initialize_by(contact: @contact)
    event = link.new_record? ? 'commerce.customer_link_created' : 'commerce.customer_link_changed'
    previous_source = link.match_source
    link.update!(account: @store.account, external_customer_id: external_customer_id, match_source: :manual, confirmed_by: @user)
    Commerce::AuditTrail.record(event, auditable: link, user: @user, changes: { match_source: [previous_source, 'manual'].compact })
  end

  # Email: exact after trim + downcase. Phone: international format only ("+966..." or "00966..."). Anything else,
  # names included, is not searchable.
  def search_criteria(query)
    return { email: query.downcase } if query.match?(URI::MailTo::EMAIL_REGEXP)

    phone = Commerce::Phone.e164(query)
    { phone: phone } if phone
  end

  def candidate(customer)
    {
      token: encryptor.encrypt_and_sign({ 'store_id' => @store.id, 'contact_id' => @contact.id, 'external_customer_id' => customer.external_id },
                                        expires_in: TOKEN_TTL, purpose: TOKEN_PURPOSE),
      name: customer.name, email: mask_email(customer.emails.first), phone: mask_phone(customer.phones.first), registered: customer.registered
    }
  end

  def link_json(link)
    { match_source: link.match_source, linked_at: link.updated_at.to_i, confirmed_by: link.confirmed_by&.slice(:id, :name) }
  end

  def base
    { store: { id: @store.id, name: @store.name, provider: @store.provider } }
  end

  # Keys that no longer work: the store is flagged for an administrator and its cached data is dropped.
  def store_error!(error)
    return unless error.code == 'AUTH_INVALID' && @store.active?

    @store.update!(status: :needs_reauth)
    Commerce::Cache.purge(@store)
    Commerce::AuditTrail.record('commerce.store_needs_reauth', auditable: @store)
  end

  def mask_email(email)
    return if email.blank?

    local, domain = email.split('@', 2)
    "#{local.first(2)}***@#{domain}"
  end

  def mask_phone(phone)
    return if phone.blank?

    "#{phone.first(4)}#{'*' * [phone.length - 6, 0].max}#{phone.last(2)}"
  end

  def decrypt(token)
    encryptor.decrypt_and_verify(token.to_s, purpose: TOKEN_PURPOSE)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def encryptor
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key(TOKEN_PURPOSE.to_s, 32))
  end

  def provider
    @provider ||= Commerce::Providers.for(@store)
  end
end
