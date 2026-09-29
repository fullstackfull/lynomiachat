# frozen_string_literal: true

# Links a Chatwoot user to a Google / Apple account (mobile sign-in).
class CreateMobileAuthIdentities < ActiveRecord::Migration[7.1]
  def change
    create_table :mobile_auth_identities do |t|
      t.references :user, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false # google | apple
      t.string :uid, null: false      # "sub" claim of the provider token
      t.string :email
      t.timestamps
    end

    add_index :mobile_auth_identities, [:provider, :uid], unique: true
  end
end