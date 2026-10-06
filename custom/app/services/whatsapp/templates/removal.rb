# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md section 5.3): deletes a
# template.
#
# A draft is deleted here and nowhere else, with no Meta call -- Meta has nothing to delete. A template Meta holds is
# deleted by id WITH its name, which is the documented single-template shape; a name on its own would delete every
# language of that name, which is right for CSAT and wrong everywhere else. A DISABLED template cannot be deleted at
# all, so the action is not offered for one.
#
# The row goes once Meta confirms. If Meta still holds the template in any state -- it moves one that has been sent
# but not delivered to PENDING_DELETION for thirty days -- the next sync brings the row back carrying Meta's own
# status, which is the truthful outcome rather than a tombstone this product invented.
class Whatsapp::Templates::Removal < Whatsapp::Templates::Operation
  def perform
    ensure_allowed!(:delete, delete_refusal_code)

    client.delete_template(waba_id, name: template.name, hsm_id: template.meta_template_id) unless template.local?
    template.destroy!
    template
  rescue Whatsapp::Templates::MetaClient::TemplateApiError => e
    raise mapped(e)
  end

  private

  def delete_refusal_code
    return 'CSAT_MANAGED_ELSEWHERE' if template.name.to_s.start_with?(CsatTemplateNameService::CSAT_BASE_NAME)

    'NOT_DELETABLE'
  end
end
