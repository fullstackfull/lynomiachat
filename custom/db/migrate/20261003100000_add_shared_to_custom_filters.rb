# Lynomia shared audiences (docs/automation/02-shared-audiences.md): a saved contact filter can belong to the account
# instead of one user, so automation rules can reference it. Existing filters stay personal (false), and a shared one
# outlives its creator (user_id becomes NULL when that user is deleted).
class AddSharedToCustomFilters < ActiveRecord::Migration[7.2]
  def change
    add_column :custom_filters, :shared, :boolean, null: false, default: false
    change_column_null :custom_filters, :user_id, true
  end
end
