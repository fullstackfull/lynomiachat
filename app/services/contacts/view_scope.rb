# The contacts a view is showing, resolved on the server from the same description the view was built from.
#
# A bulk action over every result rather than every visible row cannot be resolved in the browser, which holds
# one page of rows. So the browser sends what the view *is* — a search term, the online list, a filter query, or
# a label — and this answers with the relation (docs/contacts/10-phase-d.md §D4).
#
# Every branch is one of the list endpoints' own scopes: `Contacts::FilterService` for a filter or a saved
# segment, through its `#relation` — the path that resolves a filter without also counting it, which neither
# caller here wants; `OnlineStatusTracker` for the online list; the search endpoint's own predicate for a
# search; `resolved_contacts` and `tagged_with` for the list itself. None of it is a second definition of any of
# them, because a bulk action over "all the results" that resolved to a different set than the list showed would
# be worse than no feature.
#
# `Account::ContactsExportJob` asks the same question, and used to answer it with a fall-through that exported
# the whole account whenever the view was a search or the online list.
class Contacts::ViewScope
  SEARCH_PREDICATE = 'name ILIKE :search OR email ILIKE :search OR phone_number ILIKE :search OR contacts.identifier LIKE :search'.freeze

  # @param params [Hash] the view's description — `q`, `active`, `label`/`labels`, `payload`. It comes from a
  #   request, so the caller permits it; this does not take raw `ActionController::Parameters`.
  def initialize(account:, user:, params: {})
    @account = account
    @user = user
    @params = (params.presence || {}).to_h.with_indifferent_access
  end

  # The order `ContactsIndex.vue`'s own `fetchContactsBasedOnContext` picks a view in. A description only ever
  # names one, so this matters for a malformed request rather than for the product.
  def perform
    return searched if search_term.present?
    return online if @params[:active].present?
    return filtered if filter_query.present?

    listed
  end

  private

  def searched
    @account.contacts.where(SEARCH_PREDICATE, search: "%#{search_term.to_s.strip}%")
  end

  def online
    @account.contacts.where(id: ::OnlineStatusTracker.get_available_contact_ids(@account.id))
  end

  def filtered
    ::Contacts::FilterService.new(@account, @user, { payload: filter_query }.with_indifferent_access).relation
  end

  def listed
    scope = @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
    return scope if labels.blank?

    scope.tagged_with(labels, any: true)
  end

  def search_term
    @params[:q]
  end

  def filter_query
    Array(@params[:payload])
  end

  def labels
    Array(@params[:label] || @params[:labels]).compact_blank
  end
end
