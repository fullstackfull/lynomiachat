class CsatTemplateManagementService
  DEFAULT_BUTTON_TEXT = 'Please rate us'.freeze
  DEFAULT_LANGUAGE = 'en'.freeze

  def initialize(inbox)
    @inbox = inbox
  end

  def template_status
    template = @inbox.csat_config&.dig('template')
    return { template_exists: false } unless template

    if @inbox.twilio_whatsapp?
      get_twilio_template_status(template)
    else
      get_whatsapp_template_status(template)
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching CSAT template status: #{e.message}"
    { service_error: e.message }
  end

  def create_template(template_params)
    validate_template_params!(template_params)

    # The existing template is deliberately left in place. Both providers mint a fresh versioned name
    # (CsatTemplateNameService.generate_next_template_name), so the old one is never in the way -- deleting it
    # only took CSAT offline for the days Meta takes to approve the replacement.
    result = create_template_via_provider(template_params)
    update_inbox_csat_config(result) if result[:success]

    result
  rescue StandardError => e
    Rails.logger.error "Error creating CSAT template: #{e.message}"
    { success: false, service_error: 'Template creation failed' }
  end

  private

  def validate_template_params!(template_params)
    raise ActionController::ParameterMissing, 'message' if template_params[:message].blank?
  end

  def create_template_via_provider(template_params)
    if @inbox.twilio_whatsapp?
      create_twilio_template(template_params)
    else
      create_whatsapp_template(template_params)
    end
  end

  def create_twilio_template(template_params)
    template_config = build_template_config(template_params)
    template_service = Twilio::CsatTemplateService.new(@inbox.channel)
    template_service.create_template(template_config)
  end

  def create_whatsapp_template(template_params)
    template_config = build_template_config(template_params)
    Whatsapp::CsatTemplateService.new(@inbox.channel).create_template(template_config)
  end

  def build_template_config(template_params)
    {
      message: template_params[:message],
      button_text: template_params[:button_text] || DEFAULT_BUTTON_TEXT,
      base_url: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
      language: template_params[:language] || DEFAULT_LANGUAGE,
      template_name: CsatTemplateNameService.csat_template_name(@inbox.id)
    }
  end

  def update_inbox_csat_config(result)
    current_config = @inbox.csat_config || {}
    template_data = build_template_data_from_result(result)
    updated_config = current_config.merge('template' => template_data)
    @inbox.update!(csat_config: updated_config)
  end

  def build_template_data_from_result(result)
    if @inbox.twilio_whatsapp?
      build_twilio_template_data(result)
    else
      build_whatsapp_cloud_template_data(result)
    end
  end

  def build_twilio_template_data(result)
    {
      'friendly_name' => result[:friendly_name],
      'content_sid' => result[:content_sid],
      'approval_sid' => result[:approval_sid],
      'language' => result[:language],
      'status' => result[:whatsapp_status] || result[:status],
      'created_at' => Time.current.iso8601
    }.compact
  end

  def build_whatsapp_cloud_template_data(result)
    {
      'name' => result[:template_name],
      'template_id' => result[:template_id],
      'language' => result[:language],
      'created_at' => Time.current.iso8601
    }
  end

  def get_twilio_template_status(template)
    content_sid = template['content_sid']
    return { template_exists: false } unless content_sid

    template_service = Twilio::CsatTemplateService.new(@inbox.channel)
    status_result = template_service.get_template_status(content_sid)
    return { template_exists: false, error: 'Template not found' } unless status_result.is_a?(Hash)

    if status_result[:success]
      {
        template_exists: true,
        friendly_name: template['friendly_name'],
        content_sid: template['content_sid'],
        status: status_result[:template][:status],
        language: template['language']
      }
    else
      {
        template_exists: false,
        error: 'Template not found'
      }
    end
  end

  def get_whatsapp_template_status(template)
    template_name = template['name'] || CsatTemplateNameService.csat_template_name(@inbox.id)
    status_result = Whatsapp::CsatTemplateService.new(@inbox.channel).get_template_status(template_name)
    return { template_exists: false, error: 'Template not found' } unless status_result.is_a?(Hash)

    if status_result[:success]
      {
        template_exists: true,
        template_name: template_name,
        status: status_result[:template][:status],
        template_id: status_result[:template][:id]
      }
    else
      {
        template_exists: false,
        error: 'Template not found'
      }
    end
  end
end
