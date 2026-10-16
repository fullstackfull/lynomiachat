# THE TRANSITION CHANNEL THE TWO STATE MACHINES NEVER HAD.
#
# Lynomia holds {active, disabled, needs_reauth, disconnected} on `commerce_stores.status`.
# Store Syria holds {pending_verification, active, suspended, revoked, decommissioned} on
# `lynomia_store_links.state`. Until now NOTHING carried a change from one to the other, and
# the consequence was not cosmetic: a partner revoking an installation tore down the account
# grant and left the commerce store `active`, so `Partners::Eligibility` went on authorising
# that installation's campaigns indefinitely. The operator who revoked it had every reason to
# believe they had stopped it.
#
# A FACADE OVER Commerce::StoreConnection, NOT A SECOND LIFECYCLE. Every transition below is
# one of that service's existing methods, which already purge the cache, release provider-side
# registrations, keep the plan's store limit and write the audit row. What is added here is
# who may ask (a partner, for its own installation), the locking that makes two asks safe, and
# the partner's own attribution in the audit trail.
#
# IDEMPOTENT BY DESIGN. A partner's call may be retried -- its outbox is at-least-once like
# every other delivery in this integration -- so asking for a state the store is already in
# succeeds and changes nothing, rather than erroring and leaving the caller to guess whether
# the first attempt landed.
#
# WHAT IS DELIBERATELY NOT OFFERED: `activate` from nothing. Bringing an installation into
# existence is provisioning and has its own path with its own checks; a lifecycle endpoint
# that could conjure an active store would be a way around them.
class Commerce::InstallationLifecycle
  # What a partner may ask for, and the Lynomia state each one means. The partner's vocabulary
  # is the partner's -- it does not have to learn Lynomia's enum, and Lynomia does not have to
  # keep its enum stable for the partner's sake.
  TRANSITIONS = {
    'suspend' => :disabled,
    'resume' => :active,
    'disconnect' => :disconnected
  }.freeze

  class Refused < StandardError
    attr_reader :code

    def initialize(code, message = nil)
      @code = code
      super(message || code)
    end
  end

  def initialize(account:, platform_app:)
    @account = account
    @platform_app = platform_app
  end

  def apply(provider:, external_store_id:, transition:, reason: nil, actor: nil)
    target = TRANSITIONS[transition.to_s]
    raise Refused.new('unknown_transition', "No such transition: #{transition}") if target.nil?

    store = find_store!(provider, external_store_id)
    # One at a time per store. Two operators -- or one operator and a retry -- asking for
    # different states at the same moment would otherwise interleave their reads and writes,
    # and the loser's audit row would describe a change that did not happen.
    store.with_lock { transition_to(store, target, transition, reason, actor) }
  end

  private

  def find_store!(provider, external_store_id)
    store = @account.commerce_stores.find_by(provider: provider.to_s, external_store_id: external_store_id.to_s)
    raise Refused.new('installation_not_found', 'No such installation for this account') if store.nil?

    store
  end

  def transition_to(store, target, transition, reason, actor)
    return result(store, applied: false) if store.status.to_sym == target

    connection = Commerce::StoreConnection.new(account: @account, user: nil)
    run(connection, store, target)
    record(store, transition, reason, actor)
    result(store.reload, applied: true)
  end

  # `enable` is not a state write: it refuses a provider that is switched off, refuses a store
  # whose credentials are gone, and asks the provider whether it can actually be reached. That
  # is the right behaviour for a resume -- an installation brought back with a dead credential
  # is one that will fail silently on its first real use -- so the check is kept and its
  # refusal is reported rather than swallowed.
  def run(connection, store, target)
    case target
    when :disabled then connection.disable(store)
    when :disconnected then connection.disconnect(store)
    when :active then resume(connection, store)
    end
  end

  def resume(connection, store)
    connection.enable(store)
  rescue Commerce::Error => e
    raise Refused.new('resume_failed', "The installation could not be brought back: #{e.code}")
  end

  # WHO ASKED, ON THE OTHER SIDE. Commerce::StoreConnection already wrote its own audit row for
  # the state change itself; this one records that a partner asked for it and why, which the
  # store's own row cannot say because it has no idea a partner exists. Both rows are kept:
  # one is the fact, the other is the authority for it.
  def record(store, transition, reason, actor)
    changes = {
      transition: transition.to_s,
      requested_by_app: @platform_app.name,
      partner_actor: actor.to_s.first(120).presence,
      reason: reason.to_s.first(300).presence
    }.compact

    Commerce::AuditTrail.record('commerce.installation_lifecycle', auditable: store, user: nil, changes: changes)
  end

  def result(store, applied:)
    { provider: store.provider, external_store_id: store.external_store_id,
      status: store.status, applied: applied }
  end
end
