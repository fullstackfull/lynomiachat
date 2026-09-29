# frozen_string_literal: true

require 'administrate/base_dashboard'

class BillingSubscriptionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: ['name']),
    plan: Field::BelongsTo.with_options(class_name: 'BillingPlan'),
    status: Field::String,
    source: Field::String,
    trial_ends_at: Field::DateTime,
    current_period_end: Field::DateTime,
    grace_period_ends_at: Field::DateTime,
    cancel_at_period_end: Field::Boolean,
    stripe_customer_id: Field::String,
    stripe_subscription_id: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    plan
    status
    source
    trial_ends_at
    current_period_end
  ].freeze

  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze

  # Subscriptions are never edited with a form, only with the actions on the show page
  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {
    trialing: ->(resources) { resources.where(status: 'trialing') },
    active: ->(resources) { resources.where(status: 'active') },
    past_due: ->(resources) { resources.where(status: 'past_due') },
    canceled: ->(resources) { resources.where(status: 'canceled') },
    inactive: ->(resources) { resources.where(status: 'inactive') },
    manual: ->(resources) { resources.where(source: 'manual') }
  }.freeze

  def display_resource(subscription)
    "##{subscription.id} #{subscription.account&.name}"
  end
end