# Lynomia: a contact merge is a destructive operation and needs a boundary (docs/p10/04-contact-merge-linking.md).
#
# The OSS contact merge endpoint performs no `authorize` call at all, and `ContactPolicy` has no `merge?`, so any
# account member -- including an inbox-restricted agent -- could merge any two contacts in the account. That
# merge destroys the mergee, and until P10 it also destroyed its campaign recipients, its commerce store link
# and the customer on its support cases. Meanwhile `ContactPolicy#destroy?` has always been administrator-only.
#
# The rule here is the one the product already uses for the destructive end of contact management, widened by
# the custom-role permission that exists for exactly this: `contact_manage`. An administrator may merge, and so
# may an agent whose custom role grants contact management. Everybody else may not.
#
# This does NOT gate the web widget's automatic identify-and-merge (ContactIdentifyAction), which has no acting
# agent at all and is a different question; see docs/p10/04-contact-merge-linking.md.
module Custom::ContactPolicy
  MANAGE_PERMISSION = 'contact_manage'.freeze

  def merge?
    @account_user&.administrator? || @account_user&.permissions&.include?(MANAGE_PERMISSION) || false
  end
end
