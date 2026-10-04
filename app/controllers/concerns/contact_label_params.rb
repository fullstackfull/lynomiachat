# Reading the `labels` a contact write asks for, at the request boundary.
#
# Labels are taggings, not a Contact column, so they never belong in `permitted_params`. And only the
# account's own labels may be applied: acts-as-taggable-on will create a tag for any string, and a tag
# outside the account's catalogue is invisible to the contacts sidebar, dropped by the CSV exporter and
# ignored by campaign audiences — so an unknown title is rejected here, the way the CSV importer already
# rejects one (`DataImportJob#build_contact_from_row`), rather than stored as something that looks applied
# but does nothing.
module ContactLabelParams
  extend ActiveSupport::Concern

  private

  # @param contact [Contact] the record the rejection is reported on.
  # @return [Array<String>] the titles to assign, empty when the request asked for none.
  def requested_label_titles(contact)
    validated_label_titles(Array(params[:labels]), contact)
  end

  # The same check for a request that carries its labels somewhere else — the bulk endpoint's
  # `labels: { add: [...] }`. Only labels being *added* are checked: removing a title the catalogue no longer
  # holds is how an off-catalogue tag from before this rule gets cleaned up, so refusing that would trap it.
  #
  # @param titles [Array] the titles asked for.
  # @param contact [Contact] the record the rejection is reported on.
  # @return [Array<String>] the titles, normalized.
  def validated_label_titles(titles, contact)
    normalized = Array(titles).map { |title| title.to_s.strip.downcase }.compact_blank.uniq
    return normalized if normalized.empty?

    unknown = normalized - Current.account.labels.where(title: normalized).pluck(:title)
    return normalized if unknown.empty?

    contact.errors.add(:labels, :not_in_account,
                       message: I18n.t('errors.contacts.labels.not_found', labels: unknown.join(', ')))
    raise ActiveRecord::RecordInvalid, contact
  end
end
