# Lynomia: a membership's permissions are its custom role's when it has one, which is how
# `commerce_order_manage` reaches custom/app/policies/commerce/action_policy.rb. Without a role this falls
# through to Chatwoot's role-derived list, so an ungranted agent is unaffected.
module Custom::AccountUser
  def permissions
    custom_role.present? ? (custom_role.permissions + ['custom_role']) : super
  end
end
