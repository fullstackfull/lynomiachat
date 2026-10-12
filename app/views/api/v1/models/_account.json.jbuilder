json.settings resource.settings
json.created_at resource.created_at
if resource.custom_attributes.present?
  json.custom_attributes do
    json.plan_name resource.custom_attributes['plan_name']
    json.subscribed_quantity resource.custom_attributes['subscribed_quantity']
    json.subscription_status resource.custom_attributes['subscription_status']
    json.subscription_ends_on resource.custom_attributes['subscription_ends_on']
    json.subscription_cancels_on resource.custom_attributes['subscription_cancels_on']

    json.website resource.custom_attributes['website'] if resource.custom_attributes['website'].present?
    json.industry resource.custom_attributes['industry'] if resource.custom_attributes['industry'].present?
    json.company_size resource.custom_attributes['company_size'] if resource.custom_attributes['company_size'].present?
    json.timezone resource.custom_attributes['timezone'] if resource.custom_attributes['timezone'].present?
    json.logo resource.custom_attributes['logo'] if resource.custom_attributes['logo'].present?
    json.referral_source resource.custom_attributes['referral_source'] if resource.custom_attributes['referral_source'].present?
    json.brand_info resource.custom_attributes['brand_info'] if resource.custom_attributes['brand_info'].present?
    json.onboarding_step resource.onboarding_step if resource.onboarding_step.present?
    if resource.custom_attributes['help_center_generation_id'].present?
      json.help_center_generation_id resource.custom_attributes['help_center_generation_id']
    end
    json.marked_for_deletion_at resource.custom_attributes['marked_for_deletion_at'] if resource.custom_attributes['marked_for_deletion_at'].present?
    if resource.custom_attributes['marked_for_deletion_reason'].present?
      json.marked_for_deletion_reason resource.custom_attributes['marked_for_deletion_reason']
    end
  end
end
json.domain @account.domain
# A deprecated feature is declared but never offered: its line stays in config/features.yml so persisted bit
# positions do not shift, and it is removed here so the dashboard is never told it has a capability whose page
# no longer exists (BillingPlan.deprecated_features; docs/product-refinement/02-shopify-retirement.md).
#
# This replaces a `Shopify::FeatureGate` call that was left behind when the legacy Shopify integration was
# retired -- the class was deleted and this reference was not, which raised NameError on every dashboard load.
# `enabled_features` is a Hash of name => true (Featurable#enabled_features), so this removes BY KEY.
json.features @account.enabled_features.except(*BillingPlan.deprecated_features)
json.id @account.id
json.locale @account.locale
json.name @account.name
json.support_email @account.support_email
json.status @account.status
json.cache_keys @account.cache_keys
