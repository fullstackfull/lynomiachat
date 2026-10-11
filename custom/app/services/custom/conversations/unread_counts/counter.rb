# DECISION 1, the COUNT half.
#
# This counter was the only place in the product where the three `conversation_*` capabilities had any
# server-side effect, and it had its own expression of the rule (counter.rb:157-172). Now that the same rule
# decides what the list and the record return, the two must not be able to drift: `permission_mode` reads the
# one definition instead of re-deciding.
#
# NOTHING ABOUT THE CACHE CHANGES. The mode names are the same four this counter already branches on -- :base,
# :unassigned_and_mine, :mine, :none -- so the Redis key families it chooses between (counter.rb:105-142) and
# the `:none` short-circuit are untouched.
#
# TWO ANSWERS DO CHANGE, and both are corrections rather than widenings:
#
#   * A set grandfathered by the migration (one that predates this release and names none of the three) gets
#     :base here rather than :none. Its holders can read those conversations -- that is what grandfathering
#     means -- and a holder who can read a conversation but whose unread badge is pinned to zero is the trap
#     the earlier analysis of this rule flagged. A count is derived from access; it grants none.
#   * An account that has lost the `custom_roles` entitlement is no longer narrowed here, because the single
#     definition keys off the capability list where DECISION 2 applies the entitlement bound rather than off
#     `custom_role_id`. Withholding counts for a capability the account is not entitled to hold would have been
#     the wrong half of that decision.
#
# Both are invisible on a default installation: `conversation_unread_counts` ships disabled
# (config/features.yml:28-31) and the endpoint refuses without it.
module Custom::Conversations::UnreadCounts::Counter
  def permission_mode
    @permission_mode ||= ::Conversations::CapabilityScope.for(account_user).mode
  end
end
