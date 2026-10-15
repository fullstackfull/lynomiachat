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

  # BOTH CONSENT STORES, because a partner reconciling its own view has to see the decisions
  # it did not make. A shopper replying STOP on WhatsApp is recorded natively and is the
  # single most important fact a merchant's consent screen can show; a reconciliation that
  # returned only the rows the partner itself reported would converge happily on a view that
  # omits every opt-out made on Lynomia's own channels.
  #
  # TWO COLLECTIONS RATHER THAN ONE MERGED LIST, and deliberately. `revision` counts in a
  # different sequence in each -- a `partner_consent_events` id and a
  # `commerce_messaging_consents` id -- so a merged list would invite a consumer to order
  # across them, which decides nothing. Kept apart, each is ordered against itself, and the
  # consumer unions the negatives the way the send boundary does.
  # `native_complete` SAYS WHETHER THE NATIVE LIST IS THE WHOLE TRUTH, and a consumer that
  # deletes on absence cannot be correct without it.
  #
  # Both collections are capped (see `consents` and `native_consents`), because this is the
  # safety net behind the event feed rather than a full export. A consumer reconciling
  # against a CAPPED list can tell "this scope has no decision" from "this scope is past the
  # cap" only if it is told which it is looking at -- and Store Syria's reconciler removes a
  # projected native row that is absent here, which is how it learns that an operator cleared
  # a suppression (that path DESTROYS the row and publishes nothing, so absence is the only
  # signal there is). Without this flag that removal would delete every scope past the 200th
  # on every sweep.
  def index
    native = native_consents

    render json: { account_id: @resource.id, store: store_json,
                   consents: consents.map { |row| present(row) },
                   native: native.map { |row| present_native(row) },
                   native_complete: native.size < NATIVE_LIMIT }
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
    # `linked`: a suppressed link is an agent saying this contact is NOT this store's
    # customer, so the store may not record a decision about them either.
    link = Commerce::CustomerLink.linked.find_by(commerce_store_id: @store.id,
                                                 external_customer_id: params[:external_subject_id].to_s)
    @contact = link&.contact

    return if @contact

    # `error_code`, because the two 404s this endpoint can answer are not the same fact and
    # the caller has to tell them apart. "No such installation" is permanent for the
    # configuration that produced it; THIS one is the ordinary race for a first-time
    # shopper, whose checkout opt-in is dispatched before the order event that creates
    # their customer link. Store Syria classed every 404 as non-transient and retired the
    # decision on its first attempt, so that shopper's opt-in was simply lost -- and the
    # reconciler's drift count skipped the scope, believing the outbox still owned it, so
    # nothing said so.
    render json: { error: 'No customer of this installation matches that subject',
                   error_code: 'subject_not_linked' },
           status: :not_found
  end

  # The cap on each collection. Named because `index` reports whether the native list hit it.
  NATIVE_LIMIT = 200

  def consents = PartnerConsent.where(commerce_store_id: @store.id).order(updated_at: :desc).limit(NATIVE_LIMIT)

  # The account-wide decisions that apply to THIS installation's customers, selected through
  # the installation's own customer links -- so a partner is told about its own customers and
  # nobody else's, the same confinement `set_contact` applies on the write side.
  #
  # NEWEST FIRST AND BOUNDED, like `consents`. A reconciliation sweep repairs deliveries that
  # were LOST, and a lost delivery is overwhelmingly a recent one, so the most recent
  # decisions are the ones worth serving. A merchant with more than the limit still receives
  # every change as it happens over the event feed; this is the safety net behind that, not a
  # full export.
  def native_consents
    @native_consents ||= Commerce::MessagingConsent
                         .where(contact_id: Commerce::CustomerLink.linked.where(commerce_store_id: @store.id)
                                                                  .select(:contact_id))
                         .order(updated_at: :desc).limit(NATIVE_LIMIT).to_a
  end

  # The partner's own id for each of those people.
  #
  # LOADED AS MODELS, NOT SELECTED IN SQL, because `external_customer_id` is an encrypted
  # column: a joined `SELECT ... AS` hands back the ciphertext envelope, which is what the
  # first version of this did. Scoped to the contacts actually being presented, so a store
  # with a large customer base does not load its whole link table to answer a read.
  def native_subjects
    @native_subjects ||= Commerce::CustomerLink.linked
                                               .where(commerce_store_id: @store.id, contact_id: native_consents.map(&:contact_id))
                                               .index_by(&:contact_id)
  end

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

  # `channel: 'any'` because a native decision is account-wide and channel-agnostic, which is
  # the same value Consents::ChangeFeed publishes it under -- so a consumer that reconciles
  # and a consumer that listens arrive at the same row rather than two.
  def present_native(row)
    { external_subject_id: native_subjects[row.contact_id]&.external_customer_id,
      purpose: row.purpose, channel: 'any', state: row.state, source: row.source,
      # The same column Consents::ChangeFeed publishes, so a partner reconciling and a
      # partner listening compare like with like. Reporting the row's id here instead was
      # what made reconciliation unable to repair a scope the feed had already got stuck.
      decided_at: row.decided_at, revision: row.revision }
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
