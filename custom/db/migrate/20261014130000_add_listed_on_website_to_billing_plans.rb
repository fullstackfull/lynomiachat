# The flag that lets the public pricing page publish a plan.
#
# WHY A FLAG AND NOT `active`. `active` means "a customer may be subscribed to this plan", which is a
# different question from "this plan's name and price may appear on the marketing website". An operator needs
# a plan live for a migration, a pilot or a single negotiated customer long before -- or without ever --
# wanting it on a public page, and `BillingPlan.active` is read by the billing surfaces for that first meaning
# (custom/app/services/billing/*). Publishing from `active` would have made a private plan public the moment
# it was created.
#
# DEFAULT FALSE, which is the whole point. docs/official-website/02-verified-feature-inventory.md section 4
# establishes that no plan row, price or tier exists anywhere in this repository, so the pricing page ships
# with nothing to publish and asks for a quote instead. When the operator creates real plans and ticks this
# box, the same page renders them -- no rebuild, and no number invented in the meantime.
class AddListedOnWebsiteToBillingPlans < ActiveRecord::Migration[7.0]
  def up
    add_column :billing_plans, :listed_on_website, :boolean, default: false, null: false
    add_index :billing_plans, :listed_on_website, where: 'listed_on_website'
  end

  def down
    remove_index :billing_plans, :listed_on_website
    remove_column :billing_plans, :listed_on_website
  end
end
