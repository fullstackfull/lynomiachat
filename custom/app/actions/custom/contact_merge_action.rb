# Lynomia: make a contact merge keep what it used to destroy, and leave a record that it happened
# (docs/p10/04-contact-merge-linking.md).
#
# The OSS action is sound about the four relations it knows: it is transactional, it validates that both
# contacts belong to the account, and it destroys the mergee before copying attributes onto the base so the
# base can take over a phone number or an email without tripping `contacts`' unique indexes. None of that
# changes here.
#
# What this adds is the step between: everything else that points at the mergee is moved first
# (Contacts::MergeRelocation), inside the same transaction, and the outcome is written to Lynomia's audit log.
# `merge_and_remove_mergee_contact` is the hook because it is the last thing to run before the destroy.
#
# The audit row carries ids, counts and booleans only -- never an email address, a phone number or any other
# value from either contact. It is written through Custom::AuditLog with `associated: account`, which is what
# puts it on Settings -> Audit Logs with no new reader (custom/app/models/custom/audit_log.rb).
module Custom::ContactMergeAction
  AUDIT_EVENT = 'contact.merged'.freeze

  def merge_and_remove_mergee_contact
    relocation = Contacts::MergeRelocation.new(base: @base_contact, mergee: @mergee_contact).perform
    mergee_id = @mergee_contact.id

    super

    record_merge_audit(mergee_id, relocation)
  end

  private

  def record_merge_audit(mergee_id, relocation)
    Custom::AuditLog.create!(
      auditable: @base_contact, associated: @account, user: Current.user,
      action: 'update', comment: AUDIT_EVENT,
      audited_changes: {
        'mergee_contact_id' => mergee_id,
        'base_contact_id' => @base_contact.id,
        'moved' => relocation[:moved].transform_keys(&:to_s),
        'discarded_duplicates' => relocation[:discarded].transform_keys(&:to_s)
      }
    )
  rescue StandardError => e
    # A merge that succeeded must not be rolled back because its record could not be written; the merge itself
    # is the thing the customer's data depends on. The failure is loud in the log instead.
    Rails.logger.error("[Contacts] merged #{mergee_id} into #{@base_contact.id} but could not audit it: #{e.class}")
  end
end
