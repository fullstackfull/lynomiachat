# This contact's commerce history: the carts a store reported, the order actions an agent asked for, and the
# moment the contact was first linked to a store customer.
#
# All three tables carry `contact_id` directly, so none of them needs a conversation. They are gated on the
# contact rather than on an inbox: commerce belongs to the person, not to a channel, and the caller was already
# authorized against this contact. Cart and action rows carry no inbox at all, so there is nothing narrower to
# gate on without inventing a rule.
#
# `commerce_contact_metrics` is deliberately NOT read: it is a cache refreshed in place, so it holds a current
# snapshot and no history (docs/p8/00-discovery.md §4.5). Reading it would put today's number on an old date.
#
# No money is emitted. `commerce_carts.visible_total` is paired with a per-cart currency and nothing converts
# between currencies (docs/p8/02d-commerce-analytics.md §1), so `meta` carries the currency and the item count
# and not the amount.
class Contacts::ActivityTimeline::CommerceAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'commerce'.freeze
  CART_TIMESTAMPS = %i[abandoned_at targeted_at completed_at].freeze

  def fetch(limit)
    (cart_entries(limit) + action_entries(limit) + link_entries(limit)).sort_by(&:sort_key).first(limit)
  end

  private

  # A cart's own row is its latest state, so the entry sits at the latest thing the provider said about it.
  def cart_entries(limit)
    scope = Commerce::Cart.where(account_id: @account.id, contact_id: @contact.id)
                          .reorder(last_provider_event_at: :desc, id: :desc)
                          .limit(limit)
    sourced(scope, 'commerce_cart', :last_provider_event_at).map do |cart|
      Contacts::ActivityTimeline::Entry.new(
        source: 'commerce_cart', record_id: cart.id, category: CATEGORY,
        kind: "cart_#{cart.state}", occurred_at: cart.last_provider_event_at, meta: cart_meta(cart)
      )
    end
  end

  def cart_meta(cart)
    {
      provider: cart.provider, store_id: cart.commerce_store_id, currency: cart.currency,
      item_count: cart.item_count, order_attributed: cart.order_attributed?
    }.merge(CART_TIMESTAMPS.index_with { |column| cart.public_send(column)&.utc&.iso8601 })
  end

  def action_entries(limit)
    scope = Commerce::ActionRun.where(account_id: @account.id, contact_id: @contact.id)
                               .reorder(created_at: :desc, id: :desc)
                               .limit(limit)
    sourced(scope, 'commerce_action', :created_at).map do |run|
      Contacts::ActivityTimeline::Entry.new(
        source: 'commerce_action', record_id: run.id, category: CATEGORY,
        kind: "commerce_action_#{run.status}", occurred_at: run.created_at,
        conversation_id: run.conversation_id,
        meta: {
          provider: run.provider, store_id: run.commerce_store_id, action_type: run.action_type,
          error_code: run.error_code, requested_by_id: run.requested_by_id,
          completed_at: run.completed_at&.utc&.iso8601
        }
      )
    end
  end

  # When the contact was matched to a store customer, and on what evidence. `external_customer_id` is encrypted
  # and is never emitted; `match_source` is what a reader needs to judge the match.
  def link_entries(limit)
    scope = Commerce::CustomerLink.where(account_id: @account.id, contact_id: @contact.id)
                                  .includes(:store)
                                  .reorder(created_at: :desc, id: :desc)
                                  .limit(limit)
    sourced(scope, 'commerce_link', :created_at).map do |link|
      Contacts::ActivityTimeline::Entry.new(
        source: 'commerce_link', record_id: link.id, category: CATEGORY,
        kind: 'commerce_customer_linked', occurred_at: link.created_at,
        meta: { provider: link.store&.provider, store_id: link.commerce_store_id, match_source: link.match_source }
      )
    end
  end

  # This adapter spans three tables with three source keys, so the cursor predicate is applied per source rather
  # than once for the adapter.
  def sourced(scope, source_key, column)
    return scope if @cursor.nil?

    table = scope.table_name
    older = "#{table}.#{column} < :instant"
    case @cursor.source <=> source_key
    when -1 then scope.where("#{older} OR #{table}.#{column} = :instant", instant: @cursor.occurred_at)
    when 0 then scope.where("#{older} OR (#{table}.#{column} = :instant AND #{table}.id < :id)",
                            instant: @cursor.occurred_at, id: @cursor.record_id)
    else scope.where(older, instant: @cursor.occurred_at)
    end
  end
end
