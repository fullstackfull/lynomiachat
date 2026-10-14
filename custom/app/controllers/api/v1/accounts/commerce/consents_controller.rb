# What a shopper has agreed to receive, and what they have refused
# (docs/commerce/31-messaging-consent.md).
#
#   GET  /commerce/consents              the account's recent decisions, newest first
#   GET  /commerce/consents/:contact_id  one shopper's two classes, and whether a send would be allowed now
#   PUT  /commerce/consents/:contact_id  record a decision: purpose, state, and where it came from
#   DELETE /commerce/consents/:contact_id  clear a SUPPRESSION; a withdrawal is never cleared from here
#
# ADMINISTRATORS ONLY. Whether a person receives automated messages from this store is not an
# agent's call to change, and a list of who opted out of marketing is not an agent's to read.
#
# A MERCHANT MAY RECORD WHAT A SHOPPER TOLD THEM, AND THAT IS WHY `source` AND `evidence` ARE
# REQUIRED RATHER THAN OPTIONAL. A grant typed in by a merchant is a claim about a conversation
# that happened somewhere else; without a note saying where, it is indistinguishable from
# someone adding a person to a marketing list. The note is stored with the decision and is
# audited, so the claim has an author and a date.
#
# WITHDRAWAL IS NOT REVERSIBLE FROM HERE. `withdrawn` is the shopper's own decision, and a
# merchant clearing it would be a merchant overturning an opt-out. A later `granted` is
# accepted -- a shopper can change their mind and tell the merchant so -- but it is written as a
# new, evidenced decision rather than as an undo, which is what keeps the audit trail honest.
# `suppressed` is this system's and is cleared through its own action, never by a grant.
class Api::V1::Accounts::Commerce::ConsentsController < Api::V1::Accounts::BaseController
  LIMIT = 100
  RECORDABLE_STATES = %w[granted withdrawn].freeze
  NOTE_MAX = 500

  before_action :ensure_commerce_enabled
  before_action :check_admin_authorization?
  before_action :fetch_contact, only: [:show, :update]

  def index
    render json: { payload: decisions.map { |decision| decision_json(decision) } }
  end

  def show
    render json: contact_json(@contact)
  end

  # AN UPSERT RATHER THAN A CREATE, which is also what it is underneath: a shopper has at most
  # one decision per class, and recording a new one replaces the old. A POST to a collection
  # would suggest a history a caller can add to, and the history lives in the audit log.
  def update
    Commerce::MessagingConsents.record(
      account: Current.account, contact: @contact,
      decision: Commerce::MessagingConsents::Decision.new(
        state: consent_params[:state], source: 'merchant', purposes: [consent_params[:purpose]],
        evidence: { note: consent_params[:note], recorded_by: Current.user.id }, user: Current.user
      )
    )

    render json: contact_json(@contact.reload)
  end

  # SUPPRESSION ONLY, and it is a separate action for the reason the writer is: clearing a
  # delivery fault must not be a way to clear somebody's opt-out.
  def destroy
    Commerce::MessagingConsents.clear_suppression(account: Current.account, contact: fetch_contact, source: 'merchant',
                                                  user: Current.user)
    render json: contact_json(@contact.reload)
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def fetch_contact
    @contact = Current.account.contacts.find(params[:id])
  end

  # A FILTER THE SERVER DOES NOT RECOGNISE IS REFUSED, NOT DROPPED. Silently ignoring it answers a
  # narrower question with the whole list, and the one place that matters is this one: a merchant who
  # asked to see who has OPTED OUT, and is shown everybody, reads the opt-ins as opt-outs.
  def decisions
    filters = decision_filters
    scope = Commerce::MessagingConsent.where(account_id: Current.account.id).includes(:contact).where(filters)
    scope.order(decided_at: :desc).limit(LIMIT)
  end

  def decision_filters
    { purpose: Commerce::MessagingConsent.purposes, state: Commerce::MessagingConsent.states }.filter_map do |filter, known|
      value = params[filter].presence
      next if value.nil?

      raise ActionController::ParameterMissing, filter unless known.key?(value)

      [filter, value]
    end.to_h
  end

  def consent_params
    purpose = params.require(:purpose).to_s
    state = params.require(:state).to_s
    note = params[:note].to_s.strip

    raise ActionController::ParameterMissing, :purpose unless Commerce::MessagingConsent.purposes.key?(purpose)
    raise ActionController::ParameterMissing, :state unless RECORDABLE_STATES.include?(state)
    raise ActionController::ParameterMissing, :note unless note.length.between?(1, NOTE_MAX)

    { purpose: purpose, state: state, note: note }
  end

  def decision_json(decision)
    { contact_id: decision.contact_id, contact_name: decision.contact&.name, purpose: decision.purpose,
      state: decision.state, source: decision.source, decided_at: decision.decided_at }
  end

  # THE TWO CLASSES, AND WHAT WOULD ACTUALLY HAPPEN. A state on its own does not answer the
  # merchant's question -- "no row" means allowed for one class and refused for the other -- so
  # the live answer comes from Commerce::MessagingEligibility, the same code the send asks.
  def contact_json(contact)
    states = Commerce::MessagingConsent.where(contact_id: contact.id).index_by(&:purpose)

    { contact_id: contact.id, contact_name: contact.name,
      purposes: Commerce::MessagingConsent.purposes.keys.index_with do |purpose|
        decision = states[purpose]
        { state: decision&.state, source: decision&.source, decided_at: decision&.decided_at,
          note: decision&.evidence&.dig('note'),
          refusal: Commerce::MessagingEligibility.refusal(contact, purpose.to_sym) }
      end }
  end
end
