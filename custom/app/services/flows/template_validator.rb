# A Send template node's template and values (docs/flow-builder/04-node-contracts.md §send template), looked up in this
# account's inboxes only, so another account's template is never found. Every inbox the flow is connected to must be able
# to send the template; a flow not connected yet needs it on one of the account's WhatsApp inboxes. Every value the
# template takes must be set: text with allow-listed variables, a fixed http(s) media link (Meta fetches it), a copy code
# with the flow's own values only (its length is checked again when the flow fills it in).
class Flows::TemplateValidator
  MEDIA_URL_MAX = 2000 # Whatsapp::PopulateTemplateParametersService's limit

  def initialize(account, data, inboxes)
    @account = account
    @data = data
    @inboxes = inboxes
    @errors = []
  end

  # [code, detail] pairs.
  def errors
    return [['template_required']] unless [name, language].all? { |value| value.is_a?(String) && value.present? }

    inboxes = candidates
    return [['template_no_inbox']] if inboxes.empty?

    usable(inboxes).map { |inbox| Flows::Template.find(inbox, name, language) }.uniq.each { |template| check_params(template) }
    @errors.compact.uniq
  end

  private

  def name = @data['name']

  def language = @data['language']

  def candidates
    inboxes = @inboxes.any? ? @inboxes : @account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:id).to_a
    inboxes.select { |inbox| Flows::ChannelCapabilities.for(inbox)&.dig(:template) }
  end

  # The inboxes that can send the template. Why the others cannot is reported for each connected inbox, or for every
  # candidate when none can.
  def usable(inboxes)
    problems = inboxes.index_with { |inbox| Flows::Template.problem(inbox, name, language) }
    usable = problems.filter_map { |inbox, problem| inbox if problem.nil? }
    problems.each { |inbox, problem| @errors << [problem, inbox.name] if problem && (@inboxes.any? || usable.empty?) }
    usable
  end

  def check_params(template)
    return @errors << ['invalid_template_params'] unless @data['params'].nil? || @data['params'].is_a?(Hash)

    Flows::Template.slots(template).each do |section, key, kind|
      value = Flows::Template.value(@data['params'], section, key)
      next if kind == :media_name && value.blank?

      slot = "#{section}.#{key}"
      @errors << (filled?(value) ? value_problem(value, kind, slot) : ['template_param_missing', slot])
    end
  end

  def filled?(value) = value.is_a?(String) && value.strip.present?

  def value_problem(value, kind, slot)
    return ['text_too_long', Flows::Variables::MAX_VALUE] if value.length > Flows::Variables::MAX_VALUE
    return ['invalid_media_url', slot] if kind == :media_url && !media_url?(value)

    unknown = Flows::Variables.unknown(value, flow_only: kind == :copy_code)
    return ['unknown_variable', unknown.join(', ')] if unknown.any?

    ['copy_code_too_long', Flows::Template::COPY_CODE_MAX] if kind == :copy_code && fixed_code_too_long?(value)
  end

  def fixed_code_too_long?(value) = value.exclude?('{{') && value.strip.length > Flows::Template::COPY_CODE_MAX

  def media_url?(value)
    uri = URI.parse(value)
    uri.is_a?(URI::HTTP) && uri.host.present? && value.length <= MEDIA_URL_MAX
  rescue URI::InvalidURIError
    false
  end
end
