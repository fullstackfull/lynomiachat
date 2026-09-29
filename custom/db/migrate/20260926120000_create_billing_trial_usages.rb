# frozen_string_literal: true

# Remembers which emails already used a free trial.
# No foreign key on purpose: rows must survive account deletion.
class CreateBillingTrialUsages < ActiveRecord::Migration[7.1]
  def change
    create_table :billing_trial_usages do |t|
      t.string   :email, null: false
      t.integer  :account_id
      t.datetime :trial_ends_at
      t.timestamps
    end

    add_index :billing_trial_usages, :email, unique: true
  end
end
