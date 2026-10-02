# Buttons and List (docs/flow-builder/04-node-contracts.md §choices): one input_select message (WhatsApp interactive
# buttons or list through Chatwoot's provider), then the customer's choice follows that option's output.
#
# Each option is sent with the value `lfb:<node id>:<option id>`; WhatsApp returns it with the reply
# (content_attributes.interactive_reply.id), so the branch never depends on the visible, translated title, and a reply to
# an older menu cannot match this one. A typed reply equal to an option's title, or its number in the list, is accepted
# too. Anything else follows `other` when connected; otherwise the menu is sent again up to MAX_REPEATS times, then the
# conversation goes to humans. No reply before the timeout follows `timeout`.
class Flows::Nodes::Choice < Flows::Nodes::Base
  MAX_REPEATS = 2

  def enter
    @run.reset_counter('attempts', @node['id'])
    show
  end

  def reply(message)
    option = chosen(message)
    return Flows::Step.next(option['id']) if option
    return Flows::Step.next('other') if connected?('other')
    return Flows::Step.finish(:handed_off, code: 'no_choice') if @run.counter('attempts', @node['id']) > MAX_REPEATS

    show
  end

  def self.value(node_id, option_id) = "lfb:#{node_id}:#{option_id}"

  private

  def show
    return Flows::Step.finish(:handed_off, code: 'window_closed') unless @run.can_reply?

    @run.say(@data['text'], content_type: :input_select, content_attributes: { 'items' => items }.merge(extra_attributes))
    Flows::Step.wait(wake_at: timeout_at)
  end

  def items
    options.map do |option|
      { 'title' => option['title'], 'value' => self.class.value(@node['id'], option['id']), 'description' => option['description'] }.compact_blank
    end
  end

  def extra_attributes = {}

  def options = Array(@data['options'])

  def chosen(message)
    by_id = message.content_attributes.dig('interactive_reply', 'id')
    return options.find { |option| self.class.value(@node['id'], option['id']) == by_id } if by_id.present?

    typed = Flows::Reply.latin_digits(message.content.to_s.strip)
    options.find { |option| option['title'].to_s.strip.casecmp?(typed) } || numbered(typed)
  end

  # "2" picks the second option, as customers answer a numbered menu.
  def numbered(typed) = (options[typed.to_i - 1] if typed.match?(/\A\d{1,2}\z/) && typed.to_i.positive?)

  def connected?(output) = @run.version.edges.any? { |edge| edge['source'] == @node['id'] && edge['sourceHandle'] == output }

  def timeout_at = @data['timeout_minutes'].present? ? Integer(@data['timeout_minutes'].to_s).minutes.from_now : nil
end
