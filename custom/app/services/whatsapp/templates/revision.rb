# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md section 5.2): changes a
# template.
#
# A draft exists only here, so changing one is a local write and nothing is sent. A template Meta holds can be changed
# only while it is APPROVED, REJECTED or PAUSED, and its category only while REJECTED or PAUSED -- the rules
# Whatsapp::Templates::Actions encodes, enforced here rather than left to a hidden button.
#
# Meta replaces ALL components with the ones sent, so the complete set goes every time; there is no partial edit. Its
# response is only { success: true }, and the documented consequence is that the template re-enters review, so the
# status is set to PENDING rather than left claiming an approval that may no longer hold. Whatever Meta decides
# arrives by webhook or on the next sync, which stay the authority.
class Whatsapp::Templates::Revision < Whatsapp::Templates::Operation
  def initialize(template, attributes)
    super(template)
    @attributes = attributes
  end

  def perform
    ensure_allowed!(:edit, edit_refusal_code)
    ensure_category_allowed!
    template.assign_attributes(@attributes)
    ensure_valid!

    return save_local! if template.local?

    client.edit_template(template.meta_template_id, payload)
    template.update!(@attributes.merge(meta_status: 'PENDING'))
    template
  rescue Whatsapp::Templates::MetaClient::TemplateApiError => e
    template.reload
    raise mapped(e)
  end

  private

  def edit_refusal_code
    return 'CSAT_MANAGED_ELSEWHERE' if template.name.to_s.start_with?(CsatTemplateNameService::CSAT_BASE_NAME)

    'NOT_EDITABLE'
  end

  def ensure_category_allowed!
    return if @attributes[:category].blank? || @attributes[:category].to_s == template.category

    ensure_allowed!(:edit_category, 'CATEGORY_NOT_EDITABLE')
  end

  def save_local!
    template.save!
    template
  end

  # Only what Meta accepts on an edit: the category (when it may change), the components and the parameter format.
  # Never the name or the language, which it does not allow to be edited at all.
  def payload
    payload = { components: template.components, parameter_format: template.parameter_format }
    payload[:category] = template.category if Whatsapp::Templates::Actions.new(template).allowed?(:edit_category)
    payload
  end
end
