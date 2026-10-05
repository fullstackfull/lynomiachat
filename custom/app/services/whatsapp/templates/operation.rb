# Lynomia WhatsApp Template Manager: what the three operations that talk to Meta have in common -- the channel whose
# credentials they use, the client, and turning a Graph refusal into something a person can act on.
#
# The token is the same selector the sync uses (Channel::Whatsapp#template_access_token), not the raw api_key the CSAT
# service uses: on an embedded-signup cloud install those are different tokens and template management is a
# whatsapp_business_management operation, so the api_key would read every template and fail every write
# (docs/whatsapp-template-manager/00-current-system.md section 4.3).
class Whatsapp::Templates::Operation
  # Meta: "Content in This Language Already Exists" -- code 100 with this subcode.
  DUPLICATE_NAME_SUBCODE = 2_388_024
  OAUTH_ERROR_CODE = 190

  def initialize(template)
    @template = template
  end

  private

  attr_reader :template

  def ensure_allowed!(action, code)
    return if Whatsapp::Templates::Actions.new(template).allowed?(action)

    raise Whatsapp::Templates::Error, code
  end

  def ensure_valid!
    problems = Whatsapp::Templates::Validator.new(template).problems
    return if problems.empty?

    raise Whatsapp::Templates::Error.new('INVALID_TEMPLATE', details: problems)
  end

  def client
    @client ||= Whatsapp::Templates::MetaClient.new(channel.template_access_token)
  end

  # A template belongs to a WABA; any of that WABA's channels can speak for it. There is none only when the inbox has
  # been deleted since, which is a real state the manager has to explain rather than crash on.
  def channel
    @channel ||= template.channels.first || raise(Whatsapp::Templates::Error, 'NO_WHATSAPP_INBOX')
  end

  def waba_id
    template.business_account_id
  end

  # The full Graph body goes to the log -- it carries no credential, the token travels in a header -- and the user
  # sees a code plus whatever Meta itself wrote for a person to read.
  def mapped(error)
    Rails.logger.error("[whatsapp-template] #{error.message} fbtrace_id=#{error.trace_id}")

    return Whatsapp::Templates::Error.new('NAME_TAKEN') if error.subcode == DUPLICATE_NAME_SUBCODE
    return Whatsapp::Templates::Error.new('AUTH_INVALID') if error.code == OAUTH_ERROR_CODE
    return Whatsapp::Templates::Error.new('RATE_LIMITED') if error.status.to_i == 429
    return Whatsapp::Templates::Error.new('META_UNAVAILABLE') if error.status.to_i >= 500

    Whatsapp::Templates::Error.new('META_REJECTED_REQUEST', reason: error.user_message)
  end
end
