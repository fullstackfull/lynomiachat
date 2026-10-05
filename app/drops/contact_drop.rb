class ContactDrop < BaseDrop
  def name
    @obj.try(:name).try(:split).try(:map, &:capitalize).try(:join, ' ')
  end

  def email
    @obj.try(:email)
  end

  def phone_number
    @obj.try(:phone_number)
  end

  # Lynomia: `{{contact.phone}}` is what the composer and canned-response pickers have always offered
  # (shared/constants/messages.js, @chatwoot/utils getMessageVariables), and nothing resolved it. In the composer the
  # editor substitutes it client-side so it looked fine; in a campaign it rendered empty, and a blank render skips the
  # whole recipient (Whatsapp::LiquidTemplateProcessorService) -- so one offered variable silently dropped an audience.
  def phone
    phone_number
  end

  def first_name
    @obj.try(:name).try(:split).try(:first).try(:capitalize)
  end

  def last_name
    @obj.try(:name).try(:split).try(:last).try(:capitalize) if @obj.try(:name).try(:split).try(:size) > 1
  end

  def custom_attribute
    custom_attributes = @obj.try(:custom_attributes) || {}
    custom_attributes.transform_keys(&:to_s)
  end
end
