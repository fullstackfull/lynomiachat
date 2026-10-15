# Writing a consent decision. The one writer, so every change is audited the same way and no
# caller can record one class while silently leaving the other as it was.
#
# A DECISION APPLIES TO BOTH CLASSES unless a caller says otherwise, because every way a
# decision is really made applies to both: a shopper typing STOP, an operator recording what a
# shopper told them, a provider reporting that a number cannot receive. The per-class argument
# exists for the case that genuinely is one class -- an at-checkout marketing opt-in -- and it
# has to be asked for explicitly rather than being the default anyone falls into.
#
# SUPPRESSION IS NOT WITHDRAWAL and the writer keeps them apart: clearing a suppression never
# clears a withdrawal, because an operator fixing a delivery fault must not be able to
# overturn a person's opt-out by doing so.
module Commerce::MessagingConsents
  PURPOSES = Commerce::MessagingConsent.purposes.keys.freeze

  # Who decided, how, and on what evidence -- one value rather than a row of arguments, so a
  # caller cannot record a state without saying where it came from.
  Decision = Data.define(:state, :source, :purposes, :evidence, :user) do
    def initialize(state:, source:, purposes: PURPOSES, evidence: {}, user: nil) = super
  end

  def self.record(account:, contact:, decision:)
    Array(decision.purposes).map { |purpose| write(account, contact, purpose.to_s, decision) }
  end

  # Clears a SUPPRESSION only. A withdrawal is the shopper's and is left exactly where it is.
  def self.clear_suppression(account:, contact:, source:, user: nil)
    Commerce::MessagingConsent.where(contact_id: contact.id, state: :suppressed).find_each do |row|
      purpose = row.purpose
      row.destroy!
      audit('commerce.consent_suppression_cleared', account, contact, user, purpose: purpose, source: source)
    end
  end

  def self.write(account, contact, purpose, decision)
    row = Commerce::MessagingConsent.find_or_initialize_by(contact_id: contact.id, purpose: purpose)
    previous = row.state
    row.assign_attributes(account_id: account.id, state: decision.state.to_s, source: decision.source,
                          decided_at: Time.current, evidence: decision.evidence)
    row.save!
    # A partner cannot see this store, so it is told. The feed is best effort by construction
    # -- it enqueues a job -- and a delivery that fails is recovered by reconciliation rather
    # than by holding up the decision, which must be recorded whatever the network is doing.
    Consents::ChangeFeed.publish_native(row)
    audit('commerce.consent_changed', account, contact, decision.user,
          purpose: purpose, state: [previous, decision.state.to_s], source: decision.source)
    row
  end

  def self.audit(event, account, contact, user, changes)
    Commerce::AuditTrail.record(event, auditable: contact, user: user, changes: changes.merge(account_id: account.id))
  end

  private_class_method :write, :audit
end
