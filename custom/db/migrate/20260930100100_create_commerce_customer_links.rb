# Lynomia Commerce: links a Chatwoot contact to a customer of one connected store (docs/commerce/03-customer-matching.md).
class CreateCommerceCustomerLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :commerce_customer_links do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :commerce_store, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_customer_id, null: false
      t.integer :match_source, null: false
      t.references :confirmed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :commerce_customer_links, [:commerce_store_id, :contact_id],
              unique: true, name: 'index_commerce_customer_links_on_store_and_contact'
  end
end
