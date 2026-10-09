# Everything a contact merge has to carry across before the mergee is destroyed
# (docs/p10/04-contact-merge-linking.md).
#
# The OSS action moves four things -- conversations, messages, contact_inboxes and notes -- and then calls
# `destroy!` on the mergee. Whatever is still pointing at that row is then settled by the DATABASE, silently,
# and the settlement is not what anyone would choose:
#
#   campaign_recipients      ON DELETE CASCADE   the mergee's whole campaign send history is deleted
#   commerce_customer_links  ON DELETE CASCADE   the store-customer link is deleted
#   support_tickets          ON DELETE SET NULL  a support case loses its customer
#   commerce_carts           ON DELETE SET NULL  cart attribution lost
#   commerce_action_runs     ON DELETE SET NULL  action attribution lost
#   csat_survey_responses    dependent: :destroy_async on Contact, and never moved
#   taggings                 destroyed by acts_as_taggable_on's own association
#   contact_identities       ON DELETE CASCADE   the linked numbers and addresses are deleted
#
# P8's campaign analytics read `campaign_recipients`, so losing those rows rewrites history that has already
# been reported. This service moves all eight instead, inside the merge's existing transaction.
#
# TWO OF THEM CANNOT SIMPLY BE MOVED. `campaign_recipients` is unique on (campaign_id, contact_id) and
# `commerce_customer_links` on (commerce_store_id, contact_id), so when both contacts already have a row for the
# same campaign or the same store, moving the mergee's would violate the index. There is no way to keep both --
# after the merge they describe one human -- so the base's row is kept, the mergee's duplicate is discarded, and
# the count is returned and recorded in the audit. A discarded row is a fact somebody may need later; a hidden
# one is not.
#
# `calls` is deliberately absent: this fork has no Call model, no foreign key on that table and nothing that
# writes it (the OSS action's `merge_calls` hook is a permanent no-op here, and its comment points at an
# `enterprise/` directory that does not exist).
class Contacts::MergeRelocation
  # Relations whose rows move with a plain update, because nothing about them is unique per contact.
  SIMPLE = {
    support_tickets: 'Support::Ticket',
    commerce_carts: 'Commerce::Cart',
    commerce_action_runs: 'Commerce::ActionRun',
    csat_survey_responses: 'CsatSurveyResponse',
    # Unique on (account_id, identity_type, value), and both contacts are in one account, so no two rows being
    # moved can collide -- the index already guarantees the mergee and the base cannot hold the same value.
    # What a move CAN produce is a row that duplicates the base's own primary field once the base has taken the
    # mergee's attributes; Custom::ContactMergeAction clears those afterwards.
    contact_identities: 'ContactIdentity'
  }.freeze

  # Relations with a uniqueness that pairs the contact with something else. The second element is the column
  # that makes the pair.
  SCOPED = {
    campaign_recipients: ['CampaignRecipient', :campaign_id],
    commerce_customer_links: ['Commerce::CustomerLink', :commerce_store_id]
  }.freeze

  def initialize(base:, mergee:)
    @base = base
    @mergee = mergee
    @moved = {}
    @discarded = {}
  end

  # Returns { moved: { relation => count }, discarded: { relation => count } }.
  def perform
    SIMPLE.each_key { |relation| move_simple(relation) }
    SCOPED.each { |relation, (_model, scope_column)| move_scoped(relation, scope_column) }
    move_labels
    { moved: without_zeros(@moved), discarded: without_zeros(@discarded) }
  end

  private

  # A relation with nothing to move says nothing, rather than saying zero: the audit payload is read by a human
  # asking what happened, and seven zeroes is noise.
  def without_zeros(counts)
    counts.reject { |_relation, count| count.to_i.zero? }
  end

  def move_simple(relation)
    @moved[relation] = scope_for(relation).update_all(contact_id: @base.id) # rubocop:disable Rails/SkipsModelValidations
  end

  # Move what the base does not already have, discard the rest. Both steps are bounded by the mergee's own rows.
  def move_scoped(relation, scope_column)
    taken = scope_for(relation, @base).pluck(scope_column)
    movable = scope_for(relation)
    movable = movable.where.not(scope_column => taken) if taken.any?

    @moved[relation] = movable.update_all(contact_id: @base.id) # rubocop:disable Rails/SkipsModelValidations
    @discarded[relation] = scope_for(relation).delete_all
  end

  # Through the gem's own API rather than the taggings table, so the tag counters stay right. `add_labels` is a
  # no-op for a blank list, and the list is deduplicated by acts_as_taggable_on.
  def move_labels
    names = @mergee.label_list
    return if names.blank?

    @base.add_labels(names)
    @moved[:labels] = names.length
  end

  # Model constants are resolved lazily so a relation this installation does not have cannot break a merge at
  # load time.
  def scope_for(relation, contact = @mergee)
    model_name = SIMPLE[relation] || SCOPED[relation].first
    model_name.constantize.where(contact_id: contact.id)
  end
end
