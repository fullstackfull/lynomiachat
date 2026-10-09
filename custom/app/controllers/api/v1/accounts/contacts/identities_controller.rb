# One contact's additional phone numbers and email addresses (docs/p10/03-unified-customer-identity.md §6).
#
# Reading follows the CONTACT, like the contact's notes, attachments and activity timeline: an agent who may
# open a contact may see how that customer can be reached. Writing does not. Linking an identity decides where
# the next message from that number is delivered and it is what makes two customer records one, so it carries
# the same boundary as the merge it complements -- administrator, or an agent whose custom role grants
# `contact_manage`.
#
# A disabled feature is 404 rather than 403, the same stance the support module takes: the account has no
# linked-identity feature, so the endpoint does not exist for it. The service checks the same flag, because the
# other writer -- a contact merge absorbing the value it would have destroyed -- does not pass through here.
class Api::V1::Accounts::Contacts::IdentitiesController < Api::V1::Accounts::Contacts::BaseController
  before_action :ensure_identities_enabled

  def index
    authorize @contact, :show?

    render json: { payload: @contact.contact_identities.order(:identity_type, :created_at).map { |row| serialize(row) } }
  end

  def create
    authorize ::Contact, :manage_identities?

    result = Contacts::IdentityLinker.new(
      contact: @contact, identity_type: params[:identity_type], value: params[:value], linked_by: Current.user
    ).link

    render_link_result(result)
  end

  def destroy
    authorize ::Contact, :manage_identities?

    @contact.contact_identities.find(params[:id]).destroy!
    head :ok
  end

  private

  def ensure_identities_enabled
    return if Current.account.feature_enabled?(Contacts::IdentityLinker::FEATURE)

    render json: { error: I18n.t('errors.contacts.identities.feature_disabled') }, status: :not_found
  end

  def render_link_result(result)
    case result.status
    when :linked, :already_linked then render json: { payload: serialize(result.identity) }
    when :conflict then render_error(I18n.t('errors.contacts.identities.conflict', contact_id: result.conflict_contact_id))
    when :disabled then render json: { error: I18n.t('errors.contacts.identities.feature_disabled') }, status: :not_found
    else render_error(invalid_message)
    end
  end

  # One message for both bad inputs, because the client sends both in one field pair: a type the enum does not
  # have, or a value this app cannot turn into a phone number or an email address.
  def invalid_message
    return I18n.t('errors.contacts.identities.unknown_type', types: ContactIdentity.identity_types.keys.join(', ')) unless
      ContactIdentity.identity_types.key?(params[:identity_type].to_s)

    I18n.t('errors.contacts.identities.unusable')
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def serialize(identity)
    {
      id: identity.id, identity_type: identity.identity_type, value: identity.value,
      source: identity.source, linked_by_name: identity.linked_by&.name, created_at: identity.created_at
    }
  end
end
