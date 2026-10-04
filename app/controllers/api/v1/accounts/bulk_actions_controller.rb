class Api::V1::Accounts::BulkActionsController < Api::V1::Accounts::BaseController
  include ContactLabelParams

  # A contact bulk action over a whole view, rather than over the rows the browser has, is resolved here and
  # then sent on as the ids it resolved to — so the job, the service and the policy are untouched, and what the
  # user was told would happen is exactly what the queue is given (docs/contacts/10-phase-d.md §D4).
  #
  # The bound is the same 10,000 the pasted-numbers importer uses, and it refuses rather than truncating: a bulk
  # action that silently did 10,000 of 40,000 contacts would be worse than one that did nothing.
  CONTACT_VIEW_LIMIT = 10_000

  def create
    case normalized_type
    when 'Conversation'
      enqueue_conversation_job
      head :ok
    when 'Contact'
      check_authorization_for_contact_action
      enqueue_contact_job
      head :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def normalized_type
    params[:type].to_s.camelize
  end

  def enqueue_conversation_job
    ::BulkActionsJob.perform_later(
      account: @current_account,
      user: current_user,
      params: conversation_params
    )
  end

  def enqueue_contact_job
    Contacts::BulkActionJob.perform_later(
      @current_account.id,
      current_user.id,
      contact_params
    )
  end

  # `all_matching` present is the opt-in, not `ids` being absent: a request that forgot its ids must never mean
  # every contact in the account. `all_matching: {}` is the unfiltered list, which somebody asked for in so
  # many words.
  def whole_view_requested?
    !params[:all_matching].nil?
  end

  def contact_ids_in_view
    scope = ::Contacts::ViewScope.new(
      account: @current_account,
      user: current_user,
      # `payload` is a filter query, whose shape is the client's; `ContactsController#filter` permits it the
      # same way.
      params: params[:all_matching].permit!.to_h
    ).perform

    ids = scope.limit(CONTACT_VIEW_LIMIT + 1).pluck(:id)
    return ids if ids.size <= CONTACT_VIEW_LIMIT

    too_many_contacts!
  end

  def too_many_contacts!
    contact = @current_account.contacts.new
    contact.errors.add(:base, :too_many_contacts,
                       message: I18n.t('errors.contacts.bulk_action.too_many', count: CONTACT_VIEW_LIMIT))
    raise ActiveRecord::RecordInvalid, contact
  end

  def delete_contact_action?
    params[:action_name] == 'delete'
  end

  def check_authorization_for_contact_action
    return authorize(Contact, :destroy?) if delete_contact_action?

    # Every other contact write is authorized; this endpoint only checked deletion, so a label write bypassed the
    # policy entirely — including the overlay `ContactPolicy.prepend_mod_with` installs.
    authorize(Contact, :update?)
    validate_bulk_labels
  end

  # Checked here rather than in the job, for the same reason the create and import paths check here: the account's
  # catalogue is what the sidebar, the CSV export and campaign audiences read, so a tag outside it looks applied
  # and does nothing. `add_labels` would create one for any string.
  def validate_bulk_labels
    validated_label_titles(params.dig(:labels, :add), Current.account.contacts.new)
  end

  def conversation_params
    # TODO: Align conversation payloads with the `{ action_name, action_attributes }`
    # and then remove this method in favor of a common params method.
    base = params.permit(
      :snoozed_until,
      fields: [:status, :assignee_id, :team_id]
    )
    append_common_bulk_attributes(base)
  end

  def contact_params
    # TODO: remove this method in favor of a common params method.
    # once legacy conversation payloads are migrated.
    base = append_common_bulk_attributes({})
    return base unless whole_view_requested?

    base.merge('ids' => contact_ids_in_view)
  end

  def append_common_bulk_attributes(base_params)
    # NOTE: Conversation payloads historically diverged per action. Going forward we
    # want all objects to share a common contract: `{ action_name, action_attributes }`
    common = params.permit(:type, :action_name, ids: [], labels: [add: [], remove: []])
    base_params.merge(common)
  end
end
