# AN ACCOUNT THIS INSTALLATION OWNS, rather than one it sells to.
#
# Phase 6 gives Store Syria a Lynomia workspace of its own, for talking to its merchants about
# their accounts -- onboarding, a broken integration, a security notice. It is not a merchant's
# workspace and must never be treated as one: not counted in what the installation sells, not
# offered for linking, not swept by anything that assumes every account belongs to a customer.
#
# A REAL COLUMN, NOT `custom_attributes`. The obvious place to put a marker is the jsonb bag
# every account already has, and it is the wrong one: `custom_attributes` is in
# Platform::Api::V1::AccountsController#permitted_params, so ANY platform app holding a
# permissible on an account can write it. An ownership flag a tenant's own integration can set
# on itself is not an ownership flag. This column is written by an operator and by nothing the
# Platform API exposes.
#
# THE PRECEDENT IS Portal#platform_owned, which answers the same question for help centres and
# whose docs record it as the deliberate alternative to inventing a fake internal account. A
# portal goes further -- it has no account_id at all when it is platform owned -- which cannot
# work here, because the thing being marked IS an account. So the flag stands alone and the
# scopes carry the meaning.
#
# DEFAULT FALSE AND NOT NULL: every account that exists today belongs to a customer, and an
# account whose ownership is unknown must read as a customer's, because the failure that
# matters is treating a merchant's workspace as the platform's.
class AddPlatformOwnedToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :platform_owned, :boolean, null: false, default: false

    # Partial: there is exactly one of these on an installation and thousands of the other, so
    # an index over the whole table would be read for nothing on every merchant query.
    add_index :accounts, :platform_owned, where: 'platform_owned', name: 'index_accounts_on_platform_owned'
  end
end
