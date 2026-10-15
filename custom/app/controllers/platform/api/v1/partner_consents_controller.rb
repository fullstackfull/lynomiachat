# Consent a customer gave an approved external partner, submitted by that partner
# (docs/partner-consent/ADR-001-partner-scoped-consent.md, docs/partner-consent/AUTHORITY.md).
#
#   GET  /platform/api/v1/accounts/:account_id/partner_consents  what this app has on record
#   POST /platform/api/v1/accounts/:account_id/partner_consents  report one decision
#
# WHO MAY CALL IT. A Platform App, holding its own token, confined by
# validate_platform_app_permissible to accounts it was granted -- the same gate every other
# platform endpoint uses. A merchant's browser never reaches this; Store Syria's server does,
# and the merchant reaches Store Syria.
#
# WHY A POST RATHER THAN A PUT. Each call reports an EVENT, not a desired state. Two reports of
# the same decision are the same event and the second is a no-op; two different decisions are
# two events and both are kept. A PUT would invite "set this customer to granted", which is the
# shape that loses the sequence and with it the ability to say why somebody is where they are.
#
# A SUBMITTED GRANT IS EVIDENCE, NOT AN INSTRUCTION. Partners::Consents decides what it does to
# the stored state: a grant arriving after a withdrawal is refused however new it claims to be,
# a redelivery is a no-op, and an event assigned before the one that produced the current state
# is dropped. The response says which of those happened rather than echoing success, so a
# partner can tell "recorded and applied" from "recorded and correctly ignored".
#
# THE SUBJECT IS RESOLVED, NEVER SUPPLIED. The caller names its own customer id; this finds the
# Lynomia contact through the installation's own commerce_customer_links. A partner cannot name
# a contact id directly, so it cannot record a decision against somebody who is not its
# customer -- which is the cross-tenant hole an id parameter would open.
class Platform::Api::V1::PartnerConsentsController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible
  before_action :set_store
  before_action :set_contact, only: [:create]

  def index
    render json: { account_id: @resource.id, store: store_json, consents: consents.map { |row| present(row) } }
  end

  def create
    return render_invalid('state must be granted, withdrawn or suppressed') unless valid_state?
    return render_invalid('purpose must be transactional or promotional') unless valid_purpose?
    return render_invalid('channel must be any, whatsapp, sms or email') unless valid_channel?
    return render_invalid('decision_ref is required') if params[:decision_ref].blank?
    return render_invalid('captured_at must be a timestamp') if captured_at.nil?

    event = Partners::Consents.record(app: @platform_app, decision: decision)
    render json: present_event(event), status: :created
  end

  private

  def decision
    Partners::Consents::Decision.new(store: @store, contact: @contact, source: source,
                                     captured_at: captured_at, evidence: evidence, **reported)
  end

  # The caller's own words, defaulted where the contract allows one. Kept apart from the
  # resolved values above so it is obvious which fields a partner supplies and which this
  # side determines.
  def reported
    { external_subject_id: params[:external_subject_id].to_s, decision_ref: params[:decision_ref].to_s,
      state: params[:state].to_s, purpose: params[:purpose].presence || 'promotional',
      channel: params[:channel].presence || 'any', policy_version: params[:policy_version].presence,
      re_consent: ActiveModel::Type::Boolean.new.cast(params[:re_consent]) == true }
  end

  # The source is the partner's own word for where the capture happened, bounded because it is
  # a 40-character column and grouped in reporting. `evidence` carries the rest.
  def source = params[:source].to_s.presence&.first(40) || 'partner'

  def evidence
    supplied = params[:evidence]
    base = supplied.respond_to?(:to_unsafe_h) ? supplied.to_unsafe_h : supplied
    (base.is_a?(Hash) ? base : {}).merge('platform_app_id' => @platform_app.id)
  end

  # ISO 8601 ONLY, strictly. Time.zone.parse is lenient enough to read "last tuesday" as a
  # real Tuesday, which would quietly turn a malformed field into evidence about when a
  # customer consented. This value is kept to defend a grant later; a value nobody meant is
  # worse than no value, so the boundary refuses it.
  def captured_at
    return @captured_at if defined?(@captured_at)

    @captured_at = Time.iso8601(params[:captured_at].to_s)
  rescue ArgumentError, TypeError
    @captured_at = nil
  end

  # THE INSTALLATION, AND IT MUST BE THIS ACCOUNT'S. Looked up by the partner's own identifiers
  # rather than by a database id, so a caller cannot reach another account's store by guessing.
  def set_store
    @store = @resource.commerce_stores.find_by(provider: params[:provider].to_s,
                                               external_store_id: params[:external_store_id].to_s)

    render json: { error: 'No such installation for this account' }, status: :not_found if @store.nil?
  end

  # Resolved through the installation's own customer links. A subject this store has never seen
  # is not somebody this store may record a decision about.
  def set_contact
    link = Commerce::CustomerLink.find_by(commerce_store_id: @store.id,
                                          external_customer_id: params[:external_subject_id].to_s)
    @contact = link&.contact

    return if @contact

    render json: { error: 'No customer of this installation matches that subject' }, status: :not_found
  end

  def consents = PartnerConsent.where(commerce_store_id: @store.id).order(updated_at: :desc).limit(200)

  def valid_state? = Commerce::MessagingConsent.states.key?(params[:state].to_s)

  def valid_purpose? = params[:purpose].blank? || Commerce::MessagingConsent.purposes.key?(params[:purpose].to_s)

  def valid_channel? = params[:channel].blank? || PartnerConsent::CHANNELS.key?(params[:channel].to_s.to_sym)

  def store_json = { provider: @store.provider, external_store_id: @store.external_store_id, status: @store.status }

  # No contact id, no name, no phone, no email. A partner already knows who its own customer is
  # and has no business reading Lynomia's identifiers for them.
  def present(row)
    { external_subject_id: row.external_subject_id, purpose: row.purpose, channel: row.channel,
      state: row.state, source: row.source, policy_version: row.policy_version,
      captured_at: row.captured_at, withdrawn_at: row.withdrawn_at, revision: row.revision }
  end

  def present_event(event)
    { decision_ref: event.decision_ref, outcome: event.outcome, revision: event.id,
      received_at: event.received_at, state: event.state, purpose: event.purpose, channel: event.channel }
  end

  def render_invalid(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def set_resource
    @resource = Account.find(params[:account_id])
  end
end
