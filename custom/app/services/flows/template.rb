# The WhatsApp templates a Send template node may send (docs/flow-builder/06-whatsapp-channel-capabilities.md §templates):
# the inbox's templates as Chatwoot syncs them from Meta (`Channel::Whatsapp#message_templates`), found as Chatwoot's
# TemplateProcessorService finds them (name, language ignoring case), offered under the dashboard composer's own rule
# (@chatwoot/utils `isSendableTemplate`): approved, not an authentication or CSAT template, no list / product / catalog /
# call permission component, no location header.
#
# A node's `params` are Chatwoot's `processed_params` (@chatwoot/utils `buildWhatsAppProcessedParams`): `body` and text
# `header` values by variable, a media header's `media_url` (and a document's `media_name`), and `buttons` by position for
# URL buttons with a variable and copy-code buttons. The media type always comes from the template.
module Flows::Template
  UNSUPPORTED_COMPONENTS = %w[LIST PRODUCT CATALOG CALL_PERMISSION_REQUEST].freeze
  MEDIA_FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze
  VARIABLE = /\{\{([^}]+)\}\}/
  COPY_CODE_MAX = 15 # Whatsapp::PopulateTemplateParametersService refuses longer codes

  def self.find(inbox, name, language)
    Array(inbox.channel.try(:message_templates)).find do |template|
      template['name'] == name && template['language'].to_s.casecmp?(language.to_s)
    end
  end

  # Why the inbox cannot send the template; nil when it can.
  def self.problem(inbox, name, language)
    template = find(inbox, name, language)
    return template_missing(inbox, name) if template.nil?
    return 'template_not_approved' unless template['status'].to_s.casecmp?('approved')

    'template_not_allowed' unless sendable?(template)
  end

  def self.sendable?(template)
    !template['category'].to_s.casecmp?('authentication') && !template['name'].to_s.start_with?(CsatTemplateNameService::CSAT_BASE_NAME) &&
      Array(template['components']).none? do |component|
        UNSUPPORTED_COMPONENTS.include?(component['type']) || (component['type'] == 'HEADER' && component['format'] == 'LOCATION')
      end
  end

  # The parameters the template takes, as [section, key, kind]: kind is :text, :media_url, :media_name (optional) or
  # :copy_code.
  def self.slots(template)
    body = component(template, 'BODY')
    slots = variables(body&.dig('text')).map { |key| ['body', key, :text] }
    slots + header_slots(component(template, 'HEADER')) + button_slots(template)
  end

  # A node's value for a slot, as written in its `params`.
  def self.value(params, section, key)
    return unless params.is_a?(Hash)

    if section == 'buttons'
      button = params['buttons'].is_a?(Array) ? params['buttons'][key] : nil
      button['parameter'] if button.is_a?(Hash)
    elsif params[section].is_a?(Hash)
      params[section][key]
    end
  end

  # The template params Chatwoot sends (additional_attributes.template_params), from the node's values.
  def self.template_params(template, processed_params)
    { 'name' => template['name'], 'category' => template['category'], 'language' => template['language'],
      'namespace' => template['namespace'], 'content_mode' => 'raw_template', 'processed_params' => processed_params }.compact
  end

  def self.body_text(template) = component(template, 'BODY')&.dig('text').to_s

  # A media header's type as Chatwoot sends it (image, video, document); nil without one.
  def self.media_type(template)
    format = component(template, 'HEADER')&.dig('format')
    format.downcase if MEDIA_FORMATS.include?(format)
  end

  def self.component(template, type) = Array(template['components']).find { |item| item['type'] == type }

  def self.variables(text) = text.to_s.scan(VARIABLE).flatten.map(&:strip).uniq

  def self.template_missing(inbox, name)
    Array(inbox.channel.try(:message_templates)).any? { |template| template['name'] == name } ? 'template_language_unavailable' : 'template_not_found'
  end

  def self.header_slots(header)
    return [] if header.nil?
    return [['header', 'media_url', :media_url]] + (header['format'] == 'DOCUMENT' ? [['header', 'media_name', :media_name]] : []) if
      MEDIA_FORMATS.include?(header['format'])

    header['format'] == 'TEXT' ? variables(header['text']).map { |key| ['header', key, :text] } : []
  end

  def self.button_slots(template)
    Array(component(template, 'BUTTONS')&.dig('buttons')).each_with_index.filter_map do |button, index|
      next ['buttons', index, :copy_code] if button['type'] == 'COPY_CODE'

      ['buttons', index, :text] if button['type'] == 'URL' && button['url'].to_s.include?('{{')
    end
  end

  private_class_method :template_missing, :header_slots, :button_slots
end
