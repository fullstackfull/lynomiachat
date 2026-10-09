# Lynomia: make a contact merge keep what it used to destroy, record the identities it absorbs, and leave a
# record that it happened (docs/p10/04-contact-merge-linking.md).
#
# The OSS action is sound about the four relations it knows: it is transactional, it validates that both
# contacts belong to the account, and it destroys the mergee before copying attributes onto the base so the
# base can take over a phone number or an email without tripping `contacts`' unique indexes. None of that
# changes here.
#
# What this adds is the step either side. Before: everything else that points at the mergee is moved
# (Contacts::MergeRelocation), inside the same transaction. After: the phone number and the email address the
# merge would otherwise have thrown away are recorded as linked identities on the survivor, and the outcome is
# written to Lynomia's audit log. `merge_and_remove_mergee_contact` is the hook because it is the last thing to
# run before the destroy.
#
# WHY THE IDENTITIES ARE RECORDED AFTER, NOT BEFORE. `contacts` keeps one phone number and one email address
# per contact and the OSS merge gives the base's preference, so the mergee's second number is destroyed with
# its row -- and the next inbound message carrying it, through an inbox this merge did not touch, creates the
# duplicate all over again (docs/p10/03-unified-customer-identity.md §2 measures this). Recording it can only
# happen once the mergee is gone, because until then the value is another contact's primary field and
# Contacts::IdentityLinker would rightly call it a conflict.
#
# The audit row carries ids, counts and booleans only -- never an email address, a phone number or any other
# value from either contact. It is written through Custom::AuditLog with `associated: account`, which is what
# puts it on Settings -> Audit Logs with no new reader (custom/app/models/custom/audit_log.rb).
module Custom::ContactMergeAction
  AUDIT_EVENT = 'contact.merged'.freeze
  # The two primary fields that can be absorbed, and the identity type each becomes.
  ABSORBABLE = { phone: :phone_number, email: :email }.freeze

  def merge_and_remove_mergee_contact
    relocation = Contacts::MergeRelocation.new(base: @base_contact, mergee: @mergee_contact).perform
    mergee_id = @mergee_contact.id
    candidates = absorbable_values

    super

    record_merge_audit(mergee_id, relocation, absorb_identities(candidates))
  end

  private

  # Read while both contacts still exist. After `super` the base holds one value of each type and the mergee is
  # gone, so there would be nothing left to tell apart.
  def absorbable_values
    ABSORBABLE.transform_values { |column| [@base_contact[column], @mergee_contact[column]] }
  end

  # Returns the number of identities recorded. A value the survivor kept as its primary field is not an
  # additional identity, and a row that now duplicates that primary field is noise, so both are cleared.
  def absorb_identities(candidates)
    candidates.sum do |identity_type, values|
      kept = @base_contact[ABSORBABLE[identity_type]]
      drop_redundant_rows(identity_type, kept)
      (values.compact_blank.uniq - [kept]).count { |value| link_absorbed(identity_type, value) }
    end
  end

  def drop_redundant_rows(identity_type, kept)
    return if kept.blank?

    @base_contact.contact_identities.where(identity_type: identity_type, value: kept).delete_all
  end

  # Through the linker, so a merge cannot write an identity the product would refuse elsewhere. A conflict here
  # means the value belongs to a third contact -- it is skipped, never merged into, and never a reason to roll
  # back a merge that has already happened.
  def link_absorbed(identity_type, value)
    Contacts::IdentityLinker.new(
      contact: @base_contact, identity_type: identity_type, value: value,
      source: :merged, linked_by: Current.user
    ).link.status == :linked
  end

  def record_merge_audit(mergee_id, relocation, absorbed)
    Custom::AuditLog.create!(
      auditable: @base_contact, associated: @account, user: Current.user,
      action: 'update', comment: AUDIT_EVENT,
      audited_changes: {
        'mergee_contact_id' => mergee_id,
        'base_contact_id' => @base_contact.id,
        'moved' => relocation[:moved].transform_keys(&:to_s),
        'discarded_duplicates' => relocation[:discarded].transform_keys(&:to_s),
        'identities_absorbed' => absorbed
      }
    )
  rescue StandardError => e
    # A merge that succeeded must not be rolled back because its record could not be written; the merge itself
    # is the thing the customer's data depends on. The failure is loud in the log instead.
    Rails.logger.error("[Contacts] merged #{mergee_id} into #{@base_contact.id} but could not audit it: #{e.class}")
  end
end
