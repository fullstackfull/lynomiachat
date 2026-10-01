# Finds the store customer for a conversation's contact (docs/commerce/07-phase2-implementation.md §matching):
#
#   1. an existing link
#   2. the phone of the conversation's own channel identity (WhatsApp / SMS source id): one exact store customer is
#      linked automatically, several are offered for manual selection
#   3. the contact's email, then its phone number: agent-editable fields, so their matches are only suggestions
#
# Matching is exact (normalized email, E.164 phone); names are never used. A signed widget identity (HMAC) covers only
# the website's user identifier, not the email or phone sent with it, so it does not auto-link.
class Commerce::CustomerMatcher
  Result = Data.define(:link, :verified, :suggested, :fetched_at, :stale, :error)

  def initialize(store:, conversation:, force: false)
    @store = store
    @conversation = conversation
    @contact = conversation.contact
    @force = force
  end

  def call
    link = @store.customer_links.find_by(contact: @contact)
    return Result.new(link: link, verified: [], suggested: [], fetched_at: nil, stale: false, error: nil) if link

    discovery = Commerce::Cache.fetch(@store, :candidates, identity_key, force: @force) { discover }
    verified = discovery.value['verified'].map { |attrs| customer(attrs) }
    suggested = discovery.value['suggested'].map { |attrs| customer(attrs) }
    link = auto_link(verified.first) if verified.one?
    Result.new(link: link, verified: verified, suggested: suggested, fetched_at: discovery.fetched_at, stale: discovery.stale,
               error: discovery.error)
  end

  # E.164 phone of the channel identity this conversation arrived on, or nil.
  def trusted_phone
    source_id = @conversation.contact_inbox&.source_id.to_s
    phone = case @conversation.inbox.channel
            when Channel::Whatsapp then "+#{source_id}" if source_id.match?(/\A\d{1,15}\z/)
            when Channel::Sms then source_id
            when Channel::TwilioSms then source_id.delete_prefix('whatsapp:')
            end
    Commerce::Phone.e164(phone)
  end

  private

  def discover
    verified = trusted_phone ? provider.find_customers(phone: trusted_phone) : []
    suggested = verified.empty? ? suggestions : []
    { verified: verified.map(&:to_h), suggested: suggested.map(&:to_h) }
  end

  def suggestions
    email = @contact.email.to_s.strip.downcase.presence
    phone = Commerce::Phone.e164(@contact.phone_number)
    found = (email ? provider.find_customers(email: email) : []) + (phone && phone != trusted_phone ? provider.find_customers(phone: phone) : [])
    found.uniq(&:external_id)
  end

  def auto_link(customer)
    link = @store.customer_links.create!(account: @store.account, contact: @contact, external_customer_id: customer.external_id,
                                         match_source: :verified_phone)
    Commerce::AuditTrail.record('commerce.customer_link_created', auditable: link, changes: { match_source: 'verified_phone' })
    link
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    @store.customer_links.find_by!(contact: @contact)
  end

  # Changes whenever an identifier used for discovery changes, so an edited contact is searched again.
  def identity_key
    [@contact.id, trusted_phone, @contact.email.to_s.strip.downcase, @contact.phone_number].join(':')
  end

  def customer(attrs)
    Commerce::Customer.new(**attrs.symbolize_keys)
  end

  def provider
    @provider ||= Commerce::Providers.for(@store)
  end
end
