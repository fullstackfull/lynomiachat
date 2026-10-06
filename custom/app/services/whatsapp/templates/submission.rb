# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md section 5.1): hands a
# draft to Meta for review.
#
# The claim is taken under a row lock and committed BEFORE the HTTP call, so a double-clicked Submit finds
# submitted_at already set and refuses instead of creating a second template at Meta. If Meta refuses the call the
# claim is released and the reason stored -- the draft itself is never touched, because it is the only copy.
class Whatsapp::Templates::Submission < Whatsapp::Templates::Operation
  def perform
    ensure_allowed!(:submit, submit_refusal_code)
    ensure_valid!
    claim!

    apply(client.create_template(waba_id, payload))
    template
  rescue Whatsapp::Templates::MetaClient::TemplateApiError => e
    error = mapped(e)
    release!(error)
    raise error
  end

  private

  def submit_refusal_code
    return 'CSAT_MANAGED_ELSEWHERE' if template.name.to_s.start_with?(CsatTemplateNameService::CSAT_BASE_NAME)
    return 'ALREADY_AT_META' if template.meta_status.present?
    return 'SUBMIT_IN_FLIGHT' if template.submitted_at.present?

    'NOT_SUBMITTABLE'
  end

  def claim!
    template.with_lock do
      raise Whatsapp::Templates::Error, 'ALREADY_AT_META' if template.meta_status.present?
      raise Whatsapp::Templates::Error, 'SUBMIT_IN_FLIGHT' if submit_in_flight?

      template.update!(submitted_at: Time.current, submission_error: nil)
    end
  end

  def submit_in_flight?
    template.submitted_at.present? && template.submission_error.blank?
  end

  def payload
    { name: template.name, language: template.language, category: template.category,
      parameter_format: template.parameter_format, components: template.components }
  end

  # Meta's response carries the id, the status it starts in and the category it actually assigned, which can differ
  # from the one submitted -- so the category is taken from the response, never from the request.
  def apply(response)
    template.update!(
      meta_template_id: response['id'].presence&.to_s,
      meta_status: response['status'].presence || 'PENDING',
      category: response['category'].presence || template.category,
      submission_error: nil
    )
  end

  def release!(error)
    template.update!(submitted_at: nil, submission_error: [error.code, error.reason].compact.join(': ').first(1000))
  end
end
