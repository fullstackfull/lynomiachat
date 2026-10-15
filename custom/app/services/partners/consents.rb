# frozen_string_literal: true

# THE ONLY WRITER OF partner_consents, and the place withdrawal dominance is enforced
# (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# FOUR PROPERTIES, EACH ENFORCED BY A MECHANISM RATHER THAN BY CAREFUL CALLERS:
#
#   DURABLE EVENT IDENTITY   every decision carries the partner's own `decision_ref`, and
#                            UNIQUE (commerce_store_id, decision_ref) makes a redelivery a
#                            database refusal rather than a second application. At-least-once
#                            delivery, retry storms and replayed backlogs are all no-ops.
#
#   SERVER-CONTROLLED ORDER  the event's own id, assigned by Postgres at insert. A client
#                            cannot forge it, a wrong clock cannot skew it, and two events
#                            racing are ordered by assignment rather than by whose server was
#                            fastest. `captured_at` is kept as evidence of what the customer
#                            was told and orders nothing.
#
#   WITHDRAWAL DOMINANCE     a grant arriving while the current state is withdrawn or
#                            suppressed is REFUSED, whatever its id or its timestamps. This is
#                            the property that makes a delayed grant harmless: it cannot
#                            reactivate a refusal even when it legitimately arrives later.
#
#   RE-CONSENT, EXPLICITLY   a customer who changes their mind must still be able to say so.
#                            That is a `re_consent` event: an explicit, separately verified
#                            opt-in that names the evidence for itself. It is the one grant
#                            allowed to follow a refusal, it is never the default, and it is
#                            recorded as its own event so the sequence refusal -> re-consent
#                            is legible in the log afterwards.
#
# EVERY EVENT IS KEPT, APPLIED OR NOT. An event that changed nothing is the evidence that a
# partner tried, which is exactly what a reconciliation run and an audit need; `outcome` says
# which happened. Dropping them would make "we never received it" and "we received it and
# correctly ignored it" indistinguishable.
module Partners::Consents
  # What `outcome` records. Not an enum column: these are a log's own vocabulary and a new one
  # must not require a migration during an incident.
  APPLIED = 'applied'
  DUPLICATE = 'duplicate'
  SUPERSEDED = 'superseded'
  REFUSED_WITHDRAWAL_DOMINANT = 'refused_withdrawal_dominant'

  Decision = Data.define(:store, :contact, :external_subject_id, :decision_ref, :purpose, :channel, :state,
                         :source, :captured_at, :policy_version, :evidence, :re_consent, :recorded_by) do
    def initialize(store:, contact:, external_subject_id:, decision_ref:, state:, source:, captured_at:,
                   purpose: :promotional, channel: :any, policy_version: nil, evidence: {}, re_consent: false,
                   recorded_by: nil)
      super
    end
  end

  module_function

  # @param app [PlatformApp] the credential that authenticated this write -- provenance
  # @return [PartnerConsentEvent] always, whether or not it changed the state
  def record(app:, decision:)
    log(app, decision)
  rescue ActiveRecord::RecordNotUnique
    # The unique index did its job: this exact decision has already been processed. Return the
    # event that won, so a retrying caller sees the same answer it would have seen first time.
    existing(decision)
  end

  def log(app, decision)
    PartnerConsentEvent.transaction do
      # Saved first because the id IS the ordering key, and `apply` needs it to compare
      # against the state row's revision. The outcome is then written back as its own update
      # rather than with update_column, so the record still goes through its validations.
      event = build_event(app, decision)
      event.save!
      event.update!(outcome: apply(event))
      event
    end
  end

  # THE STATE ROW IS LOCKED BEFORE IT IS COMPARED. Two events for one scope arriving together
  # would otherwise both read the old revision and both apply, and the loser would overwrite
  # the winner. The lock is taken inside the event's own transaction, so the comparison and
  # the write cannot be split.
  def apply(event)
    state = PartnerConsent.lock.find_by(scope_of(event))
    return create_state(event) if state.nil?
    return SUPERSEDED if state.revision.present? && event.id <= state.revision
    return REFUSED_WITHDRAWAL_DOMINANT if refuses_grant?(state, event)

    state.update!(state_attributes(event))
    Consents::ChangeFeed.publish_partner(state)
    APPLIED
  end

  # The rule that makes a late grant harmless, and the one asymmetry inside it.
  #
  # A WITHDRAWAL IS THE CUSTOMER'S, SO THE CUSTOMER MAY REVERSE IT -- but only by saying so
  # explicitly, through a verified re-consent. An ordinary grant cannot, however new it claims
  # to be, which is what stops a delayed or replayed opt-in from resurrecting marketing.
  #
  # A SUPPRESSION IS NOT THE CUSTOMER'S AND THEY CANNOT REVERSE IT AT ALL. It means the
  # provider reported that the number cannot receive; no amount of agreeing makes a dead
  # number alive, and treating a re-consent as clearing it would let a checkout tick silently
  # undo a delivery fault. It is cleared by an operator, through the native
  # Commerce::MessagingConsents.clear_suppression, once the cause is actually fixed -- the
  # same reason the native model keeps the two states apart rather than collapsing them.
  def refuses_grant?(state, event)
    return false unless event.consent_granted?
    return true if state.consent_suppressed?

    state.consent_withdrawn? && !event.re_consent?
  end

  def create_state(event)
    state = PartnerConsent.create!(scope_of(event).merge(state_attributes(event)).merge(
                                     platform_app_id: event.platform_app_id, account_id: event.account_id,
                                     external_subject_id: event.external_subject_id
                                   ))
    Consents::ChangeFeed.publish_partner(state)
    APPLIED
  end

  def state_attributes(event)
    { state: event.state, source: event.source, policy_version: event.policy_version,
      captured_at: event.captured_at, evidence: event.evidence, recorded_by_id: event.recorded_by_id,
      revision: event.id, decision_ref: event.decision_ref,
      withdrawn_at: event.consent_granted? ? nil : event.received_at }
  end

  def scope_of(event)
    { commerce_store_id: event.commerce_store_id, contact_id: event.contact_id,
      purpose: event.purpose, channel: event.channel }
  end

  def build_event(app, decision)
    PartnerConsentEvent.new(
      platform_app: app, account_id: decision.store.account_id, commerce_store: decision.store,
      contact: decision.contact, decision_ref: decision.decision_ref,
      external_subject_id: decision.external_subject_id, purpose: decision.purpose, channel: decision.channel,
      state: decision.state, source: decision.source, policy_version: decision.policy_version,
      captured_at: decision.captured_at, received_at: Time.current, re_consent: decision.re_consent,
      evidence: decision.evidence, recorded_by: decision.recorded_by, outcome: DUPLICATE
    )
  end

  def existing(decision)
    PartnerConsentEvent.find_by!(commerce_store_id: decision.store.id, decision_ref: decision.decision_ref)
  end
end
