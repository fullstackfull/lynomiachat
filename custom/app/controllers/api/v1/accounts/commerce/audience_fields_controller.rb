# What the contact filter's Commerce conditions can be built from (docs/audience/02-audience-architecture.md), for anyone
# who may filter contacts in a `lynomia_commerce` account. Read from Postgres only: the counted stores (no URLs or
# credentials), the currencies Lynomia has seen in their orders, and how many linked contacts have not been read yet
# (their order conditions are unknown until an agent opens them or the store sends an update).
#
#   GET /api/v1/accounts/:account_id/commerce/audience_fields
class Api::V1::Accounts::Commerce::AudienceFieldsController < Api::V1::Accounts::BaseController
  before_action :ensure_commerce_enabled
  before_action -> { authorize(Contact, :filter?) }

  def show
    links = ::Audience::CommerceCondition.counted_links(Current.account)
    render json: {
      stores: ::Audience::CommerceCondition.counted_stores(Current.account).order(:created_at).map { |store| store.slice(:id, :name, :provider) },
      currencies: ::Commerce::ContactMetric.where(commerce_customer_link_id: links.select(:id))
                                           .pluck(Arel.sql('DISTINCT jsonb_object_keys(spend)')).sort,
      unread_contacts: links.where.missing(:contact_metric).distinct.count(:contact_id)
    }
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end
end
