# THE APPEND-ONLY LOG BEHIND partner_consents, and the reason a late grant cannot resurrect a
# withdrawal (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# WHY CLIENT TIMESTAMPS CANNOT ORDER THESE. `captured_at` is whatever the partner's server
# said, and a clock that is wrong, skewed or simply lying would decide whether somebody who
# opted out gets marketed to. It is kept -- it is real evidence of what the customer was told
# and when -- but it orders nothing. ORDER IS THE EVENT'S OWN id, assigned by Postgres at
# insert, so it is server-controlled, monotonic in assignment order and unforgeable by a
# caller. `received_at` records when this side saw it, for reconciliation rather than ordering.
#
# IDEMPOTENCY IS A UNIQUE INDEX, NOT A CHECK. UNIQUE (commerce_store_id, decision_ref) means a
# redelivered event is refused by the database on insert, so a retry storm, an at-least-once
# feed and a replayed backlog are all no-ops by construction. Scoped to the store because
# decision_ref is the PARTNER's identifier and two partners may legitimately mint the same one.
#
# STATE IS DERIVED, NOT TRUSTED. partner_consents holds the current answer so eligibility can
# read it in one indexed row; `revision` on that row is the id of the event that produced it,
# which is what lets an out-of-order or replayed event be recognised and dropped.
class CreatePartnerConsentEvents < ActiveRecord::Migration[7.1]
  def change
    create_event_log
    add_event_indexes
    add_state_revision
  end

  def create_event_log
    create_table :partner_consent_events do |t|
      t.references :platform_app, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :commerce_store, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true

      # The partner's own durable identifier for this decision. Required: an event that cannot
      # be recognised on redelivery cannot be made idempotent.
      t.string :decision_ref, limit: 128, null: false
      t.string :external_subject_id, limit: 128, null: false
      t.integer :purpose, :channel, :state, null: false
      t.string :source, limit: 40, null: false
      t.string :policy_version, limit: 40
      # EVIDENCE ONLY. What the partner says the customer did, and when they say it happened.
      t.datetime :captured_at, null: false
      # Server time, for reconciliation and for seeing delivery lag. Not an ordering key.
      t.datetime :received_at, null: false
      # An explicit, verified opt-in that is allowed to follow a withdrawal. Without this a
      # grant can never overturn a refusal, whatever its timestamps say.
      t.boolean :re_consent, null: false, default: false
      # Why an event was not applied, when it was accepted for audit but changed nothing.
      t.string :outcome, limit: 32, null: false
      t.jsonb :evidence, null: false, default: {}
      t.references :recorded_by, foreign_key: { to_table: :users }

      t.timestamps
    end
  end

  def add_event_indexes
    add_index :partner_consent_events, %i[commerce_store_id decision_ref],
              unique: true, name: 'index_partner_consent_events_idempotency'
    add_index :partner_consent_events, %i[commerce_store_id contact_id purpose channel],
              name: 'index_partner_consent_events_on_scope'
    add_index :partner_consent_events, %i[account_id received_at], name: 'index_partner_consent_events_on_account_time'
  end

  def add_state_revision
    # The event that produced the current state. An arriving event whose id is not greater
    # than this one has already been superseded and is dropped.
    add_column :partner_consents, :revision, :bigint
    add_column :partner_consents, :decision_ref, :string, limit: 128
  end
end
