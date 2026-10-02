# Question (docs/flow-builder/04-node-contracts.md §question): asks, waits for the customer's next message, checks it
# (Flows::Reply and, when stored in a custom attribute, the attribute's definition), stores it, and follows `reply`. A
# reply that does not fit asks again (retry text) until max attempts, then follows `invalid`; no reply before the timeout
# follows `timeout`.
class Flows::Nodes::Question < Flows::Nodes::Base
  DEFAULT_ATTEMPTS = 3

  def enter
    return Flows::Step.finish(:handed_off, code: 'window_closed') unless @run.can_reply?

    @run.say(@data['text'])
    @run.reset_counter('attempts', @node['id'])
    Flows::Step.wait(wake_at: timeout_at)
  end

  def reply(message)
    value = accepted_value(message.content)
    return store(value) unless value.nil?
    return Flows::Step.next('invalid') if @run.counter('attempts', @node['id']) >= max_attempts
    return Flows::Step.finish(:handed_off, code: 'window_closed') unless @run.can_reply?

    @run.say(@data['retry_text'].presence || @data['text'])
    Flows::Step.wait(wake_at: timeout_at)
  end

  private

  def accepted_value(text)
    value = Flows::Reply.parse(@data, text)
    return value if value.nil? || attribute.nil?

    Flows::AttributeValue.cast(attribute, value)
  end

  def store(value)
    target = @data['store_as'] || {}
    case target['scope']
    when 'context' then @run.remember(target['key'], value)
    when 'contact' then @run.contact.update!(custom_attributes: @run.contact.custom_attributes.merge(target['key'] => value))
    when 'conversation' then conversation.update!(custom_attributes: conversation.custom_attributes.merge(target['key'] => value))
    end
    Flows::Step.next('reply')
  end

  def attribute
    model = Flows::NodeValidator::STORE_MODELS[@data.dig('store_as', 'scope')]
    @attribute ||= model && account.custom_attribute_definitions.find_by(attribute_model: model, attribute_key: @data.dig('store_as', 'key'))
  end

  def max_attempts = Integer(@data['max_attempts'] || DEFAULT_ATTEMPTS, exception: false) || DEFAULT_ATTEMPTS

  def timeout_at = @data['timeout_minutes'].present? ? Integer(@data['timeout_minutes'].to_s).minutes.from_now : nil
end
