# frozen_string_literal: true

require 'administrate/base_dashboard'

class BillingPlanDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String.with_options(searchable: true),
    description: Field::Text,
    price: Field::Number.with_options(decimals: 2),
    currency: Field::Select.with_options(collection: BillingPlan::CURRENCIES),
    interval: Field::Select.with_options(collection: BillingPlan::INTERVALS),
    pricing_type: Field::Select.with_options(collection: BillingPlan::PRICING_TYPES),
    limits: BillingPlanLimitsField,
    features: BillingPlanFeaturesField,
    channel_entitlements: BillingPlanChannelsField,
    active: Field::Boolean,
    # Whether the public pricing page may publish this plan. Separate from `active`, which means "a customer
    # may subscribe": an operator needs plans live for a migration or a negotiated customer long before -- or
    # without ever -- wanting them on a public page.
    listed_on_website: Field::Boolean,
    position: Field::Number,
    subscriptions: CountField,
    stripe_product_id: Field::String,
    stripe_price_id: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    price
    currency
    interval
    pricing_type
    active
    listed_on_website
    subscriptions
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    description
    price
    currency
    interval
    pricing_type
    limits
    features
    channel_entitlements
    active
    listed_on_website
    position
    subscriptions
    stripe_product_id
    stripe_price_id
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    description
    price
    currency
    interval
    pricing_type
    limits
    features
    channel_entitlements
    active
    listed_on_website
    position
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.where(active: true) },
    inactive: ->(resources) { resources.where(active: false) }
  }.freeze

  def display_resource(plan)
    plan.name
  end
end
