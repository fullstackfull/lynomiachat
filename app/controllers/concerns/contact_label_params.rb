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
    return [] if params[:labels].blank?

    titles = Array(params[:labels]).map { |title| title.to_s.strip.downcase }.compact_blank.uniq
    unknown = titles - Current.account.labels.where(title: titles).pluck(:title)
    return titles if unknown.empty?

    contact.errors.add(:labels, :not_in_account,
                       message: I18n.t('errors.contacts.labels.not_found', labels: unknown.join(', ')))
    raise ActiveRecord::RecordInvalid, contact
  end
end
