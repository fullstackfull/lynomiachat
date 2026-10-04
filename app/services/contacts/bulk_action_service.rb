class Contacts::BulkActionService
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.deep_symbolize_keys
  end

  def perform
    return delete_contacts if delete_requested?
    return label_results if labels_to_add.any? || labels_to_remove.any?

    Rails.logger.warn("Unknown contact bulk operation payload: #{@params.keys}")
    { success: false, error: 'unknown_operation' }
  end

  private

  # Removals before additions, as the conversation bulk job does, so a payload that moves a contact from one label
  # to another lands on the added one. A payload carrying both used to apply only the additions, because this
  # returned on the first match.
  def label_results
    removed = labels_to_remove.any? ? remove_labels : nil
    added = labels_to_add.any? ? assign_labels : nil
    added || removed
  end

  def assign_labels
    Contacts::BulkAssignLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_add
    ).perform
  end

  def remove_labels
    Contacts::BulkRemoveLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_remove
    ).perform
  end

  def delete_contacts
    Contacts::BulkDeleteService.new(
      account: @account,
      contact_ids: ids
    ).perform
  end

  def ids
    Array(@params[:ids]).compact
  end

  def labels_to_add
    @labels_to_add ||= Array(@params.dig(:labels, :add)).reject(&:blank?)
  end

  def labels_to_remove
    @labels_to_remove ||= Array(@params.dig(:labels, :remove)).reject(&:blank?)
  end

  def delete_requested?
    @params[:action_name] == 'delete'
  end
end
