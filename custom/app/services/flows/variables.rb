# Variables in flow message text (docs/flow-builder/04-node-contracts.md §variables). An allow-list, no code: `{{ name }}`
# with a dotted name from the list below, no Liquid tags (`{% %}`) and no filters.
#
#   contact.name / first_name / last_name / email / phone_number / custom_attribute.<key>
#   conversation.display_id / custom_attribute.<key>     inbox.name     account.name
#                       rendered by Chatwoot's own Liquid drops when the message is created (Liquidable)
#   flow.reply          the customer's last reply the flow consumed
#   flow.<key>          a value a Question stored in the run's context (store_as context)
#   flow.order.number / status / payment_status / tracking_number / tracking_url
#                       the order a Commerce lookup found
#
# The flow fills `flow.*` itself before the message is created, with `{{`, `}}`, `{%`, `%}` removed from the values, so
# nothing a customer typed or a store returned can become a template.
module Flows::Variables
  TOKEN = /\{\{\s*(.*?)\s*\}\}/
  CHATWOOT = /\A(contact\.(name|first_name|last_name|email|phone_number|custom_attribute\.[A-Za-z0-9_-]+)|
                 conversation\.(display_id|custom_attribute\.[A-Za-z0-9_-]+)|inbox\.name|account\.name)\z/x
  ORDER_FIELDS = %w[number status payment_status tracking_number tracking_url].freeze
  CONTEXT_KEY = /\A[a-z][a-z0-9_]{0,39}\z/
  RESERVED = %w[reply order].freeze
  MAX_VALUE = 1024

  # The tokens of `text` that are not allowed (a tag counts as one).
  def self.unknown(text)
    text = text.to_s
    tags = text.include?('{%') ? ['{%'] : []
    tags + text.scan(TOKEN).flatten.reject { |name| known?(name) }
  end

  def self.known?(name)
    return true if CHATWOOT.match?(name)
    return false unless name.start_with?('flow.')

    key = name.delete_prefix('flow.')
    key == 'reply' || ORDER_FIELDS.map { |field| "order.#{field}" }.include?(key) || (CONTEXT_KEY.match?(key) && RESERVED.exclude?(key))
  end

  # `text` with the run's `flow.*` values filled in; Chatwoot's tokens are left for the message's Liquid rendering.
  def self.render(text, context)
    text.to_s.gsub(TOKEN) do |token|
      name = Regexp.last_match(1)
      name.start_with?('flow.') ? safe(lookup(context, name.delete_prefix('flow.'))) : token
    end
  end

  def self.lookup(context, key)
    return context.dig('order', key.delete_prefix('order.')) if key.start_with?('order.')

    key == 'reply' ? context['reply'] : context.dig('values', key)
  end

  def self.safe(value) = value.to_s.gsub(/\{\{|\}\}|\{%|%\}/, '').first(MAX_VALUE)

  private_class_method :lookup, :safe
end
