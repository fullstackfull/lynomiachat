# Commerce Lookup (docs/flow-builder/04-node-contracts.md §commerce lookup): finds one of this contact's own orders with
# the existing Commerce services, never another customer's. Read only: no order is changed.
#
#   latest_order   the newest order of the contact's matched store customers (Commerce::Customer360, the same view
#                  agents see, cached)
#   order_number   the order the customer quotes (`number`, default the last reply): first among those latest orders,
#                  then by number (Commerce::OrderSearch) in the stores where the contact is matched, keeping only an
#                  order of the matched customer. A guessed number of someone else's order is simply not found.
#
# `found` puts the order in flow.order.number / status / payment_status / tracking_number / tracking_url; `not_found`;
# `unavailable` when Commerce is off for the account, no store answered, or the conversation asked too often
# (LOOKUP_LIMIT per hour).
class Flows::Nodes::CommerceLookup < Flows::Nodes::Base
  NUMBER = /\A#?(\d{1,20})\z/
  LOOKUP_LIMIT = 10
  THROTTLE_KEY = 'LYNOMIA::FLOW::COMMERCE_LOOKUP::CONVERSATION::%<id>d'.freeze

  def enter
    return Flows::Step.next('not_found') if Flows::Simulator.active? # a test contact has no store customer; no store is called
    return Flows::Step.next('unavailable') unless account.feature_enabled?('lynomia_commerce') && within_limit?

    overview = Commerce::Customer360.new(conversation: conversation, user: nil).call
    @data['mode'] == 'order_number' ? by_number(overview) : latest(overview)
  end

  private

  def latest(overview)
    order = overview[:latest_orders].first
    return found(order) if order

    nothing(overview)
  end

  def by_number(overview)
    number = quoted_number
    return Flows::Step.next('not_found') if number.nil?

    order = overview[:latest_orders].find { |candidate| candidate['order_number'].to_s == number }
    order ? found(order) : search(overview, number)
  end

  def quoted_number
    text = Flows::Variables.render(@data['number'].presence || '{{flow.reply}}', @run.context)
    Flows::Reply.latin_digits(text.strip)[NUMBER, 1]
  end

  def search(overview, number)
    links = matched_links
    return nothing(overview) if links.empty?

    owners = links.to_h { |link| [link.commerce_store_id, link.external_customer_id] }
    result = Commerce::OrderSearch.new(stores: links.map(&:store), number: number, owners: owners).call
    return found(result[:orders].first) if result[:orders].any?

    Flows::Step.next(result[:partial] ? 'unavailable' : 'not_found')
  end

  def matched_links
    Commerce::CustomerLink.not_suppressed.where(account: account, contact: @run.contact).includes(:store)
                          .select { |link| link.store.active? && Commerce::Providers.enabled?(link.store.provider) }
  end

  def found(order)
    @run.session.context = @run.context.merge('order' => {
      'number' => order['order_number'], 'status' => order['status'], 'payment_status' => order['payment_status'],
      'tracking_number' => order.dig('tracking', 'number'), 'tracking_url' => order.dig('tracking', 'url')
    }.transform_values { |value| value.to_s.first(256) })
    Flows::Step.next('found')
  end

  # No order: `unavailable` when no store could answer, else `not_found`.
  def nothing(overview)
    answered = overview[:stores].any? { |store| store[:error].blank? && %w[provider_unavailable needs_reauth].exclude?(store[:state]) }
    Flows::Step.next(answered ? 'not_found' : 'unavailable')
  end

  def within_limit?
    key = format(THROTTLE_KEY, id: conversation.id)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.hour.to_i) if count == 1
    count <= LOOKUP_LIMIT
  end
end
