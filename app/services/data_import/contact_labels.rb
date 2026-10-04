# The taggings a contacts import writes, in two statements rather than one per contact.
#
# Additive by construction: existing taggings are read first and left alone, and the insert ignores a conflict, so
# an import that applies "vip" to a contact never disturbs the labels another agent put there
# (docs/contacts/04-bulk-import.md). Extracted from `DataImportJob`, unchanged, when the job took on the batch's
# own labels and the preview's classifier.
class DataImport::ContactLabels
  LABELS_CONTEXT = 'labels'.freeze
  TAGGABLE_TYPE = 'Contact'.freeze

  def initialize(account)
    @account = account
  end

  # @param contacts_with_labels [Array<Hash>] `{ contact:, labels: }` per accepted row. A contact that two rows
  #   named appears twice, carrying each row's labels.
  def apply(contacts_with_labels)
    taggings = taggings_for(contacts_with_labels)
    return if taggings.blank?

    ActsAsTaggableOn::Tagging.import(%i[tag_id taggable_type taggable_id context created_at],
                                     taggings, on_duplicate_key_ignore: true, validate: false, batch_size: 1000)
  end

  private

  def taggings_for(contacts_with_labels)
    tag_lookup = tags_by_label_name(contacts_with_labels)
    taggings = contacts_with_labels.flat_map do |item|
      contact = persisted_contact(item[:contact])
      next [] if contact&.id.blank?

      item[:labels].map(&:downcase).uniq.map do |label|
        [tag_lookup[label].id, TAGGABLE_TYPE, contact.id, LABELS_CONTEXT]
      end
    end.uniq

    reject_existing(taggings).map { |tagging| tagging + [Time.zone.now] }
  end

  def reject_existing(taggings)
    tag_ids = taggings.map { |tag_id, _taggable_type, _taggable_id, _context| tag_id }
    taggable_ids = taggings.map { |_tag_id, _taggable_type, taggable_id, _context| taggable_id }
    existing = ActsAsTaggableOn::Tagging
               .where(context: LABELS_CONTEXT, taggable_type: TAGGABLE_TYPE,
                      taggable_id: taggable_ids, tag_id: tag_ids)
               .pluck(:tag_id, :taggable_id)
               .index_with(true)

    taggings.reject { |tag_id, _taggable_type, taggable_id, _context| existing[[tag_id, taggable_id]] }
  end

  # A bulk insert hands back no ids for the rows it skipped, so a contact that was already there is looked up by
  # the identity its row carried.
  def persisted_contact(contact)
    return contact if contact.nil? || contact.id.present?
    return @account.contacts.find_by(identifier: contact.identifier) if contact.identifier.present?
    return @account.contacts.from_email(contact.email) if contact.email.present?

    @account.contacts.find_by(phone_number: contact.phone_number) if contact.phone_number.present?
  end

  def tags_by_label_name(contacts_with_labels)
    labels = contacts_with_labels.flat_map { |item| item[:labels] }.map(&:downcase).uniq
    ActsAsTaggableOn::Tag.find_or_create_all_with_like_by_name(labels).index_by { |tag| tag.name.downcase }
  end
end
