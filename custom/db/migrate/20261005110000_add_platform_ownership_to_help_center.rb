# Lynomia global documentation (docs/global-documentation/01-global-ownership-design.md): Lynomia's own product
# documentation is platform content, not a customer's. The Help Center already has everything it needs to carry it --
# the editor, the draft/publish lifecycle, locales, search and the public renderer -- except an owner that is not an
# account.
#
# Two halves, and both are needed. Relaxing the NOT NULL is what lets a portal exist with no account, and that is what
# makes tenant isolation a property of the data: `Current.account.portals` compiles to `WHERE account_id = $1`, which no
# NULL row can satisfy, for any account, under any role. The flag is what keeps the absence deliberate: without it a
# bug that forgot the account would silently publish a tenant's portal as Lynomia documentation.
class AddPlatformOwnershipToHelpCenter < ActiveRecord::Migration[7.0]
  def up
    add_column :portals, :platform_owned, :boolean, default: false, null: false
    add_index :portals, :platform_owned, where: 'platform_owned', name: 'index_portals_on_platform_owned'

    change_column_null :portals, :account_id, true
    change_column_null :categories, :account_id, true
    change_column_null :articles, :account_id, true
  end

  # Restoring the NOT NULL fails while any platform row exists, which is the truth rather than a flaw: a schema that
  # forbids accountless rows cannot hold them. Delete the platform portals first -- the content is reproducible from
  # source control and the seeder is idempotent.
  def down
    change_column_null :articles, :account_id, false
    change_column_null :categories, :account_id, false
    change_column_null :portals, :account_id, false

    remove_index :portals, name: 'index_portals_on_platform_owned'
    remove_column :portals, :platform_owned
  end
end
