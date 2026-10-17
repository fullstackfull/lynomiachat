# == Schema Information
#
# Table name: odoo_sync_attempts
#
# What one attempt at one sync event actually did (docs/odoo/02-architecture.md §6).
#
# WHY A DURABLE ROW PER ATTEMPT. An accounting write is sent at most once per attempt -- the rule
# Commerce::ActionJob states as "a write is sent at most once, and a lost answer is reconciled by reading the
# store, not by sending again". That is only enforceable if the attempt is recorded BEFORE the request goes
# out and survives the worker dying between sending it and reading the answer. Without that record, a crash
# mid-write is indistinguishable from a write that never happened, and the correct recovery for the two is
# opposite.
#
# `outcome` carries the distinction explicitly. NOT_SENT means the request provably never reached Odoo and is
# safe to repeat. UNKNOWN_OUTCOME means Odoo may have acted, so the next step is to SEARCH for our own stamp
# and adopt what we find -- never to write again.
class Odoo::SyncAttempt < ApplicationRecord
  self.table_name = 'odoo_sync_attempts'

  SUCCEEDED = 'succeeded'.freeze
  # The input was wrong, or the server refuses on principle. Retrying sends the same rejected request again.
  PERMANENT = 'permanent'.freeze
  # The server was busy, locked or unreachable after the request went out. Worth repeating.
  TRANSIENT = 'transient'.freeze
  # Odoo and Lynomia disagree about something only a person can settle.
  NEEDS_REVIEW = 'needs_review'.freeze
  # Before the request was written: DNS, a refused connection, a connect timeout.
  NOT_SENT = 'not_sent'.freeze
  # After it was written, with no readable answer. The dangerous one.
  UNKNOWN_OUTCOME = 'unknown_outcome'.freeze

  OUTCOMES = [SUCCEEDED, PERMANENT, TRANSIENT, NEEDS_REVIEW, NOT_SENT, UNKNOWN_OUTCOME].freeze
  # What may be repeated without first reading Odoo back.
  SAFE_TO_REPEAT = [TRANSIENT, NOT_SENT].freeze

  MAX_REASON = 500

  belongs_to :sync_event, class_name: 'Odoo::SyncEvent', foreign_key: :odoo_sync_event_id, inverse_of: :attempts

  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :started_at, presence: true
  validates :reason, length: { maximum: MAX_REASON }, allow_nil: true

  # Odoo's own ValidationError text is the one thing that tells an operator WHICH part of their journal
  # configuration is wrong, so it is worth carrying -- but it is carried through the same structural scrub
  # Operations::SignalRecorder applies to a provider message, never raw. One rule, one place: a second copy of
  # a credential-redaction pattern is a second chance for one of the copies to be wrong.
  def self.scrub(text)
    return nil if text.blank?

    scrubbed = text.to_s.squish
    Operations::SignalRecorder::CREDENTIAL_PATTERNS.each { |pattern, replacement| scrubbed = scrubbed.gsub(pattern, replacement) }
    scrubbed.truncate(MAX_REASON)
  end

  def safe_to_repeat?
    SAFE_TO_REPEAT.include?(outcome)
  end
end
