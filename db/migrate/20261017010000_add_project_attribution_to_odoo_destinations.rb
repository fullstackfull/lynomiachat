# PROJECT-LEVEL ATTRIBUTION, because the company is not the boundary (docs/odoo/08-project-attribution.md).
#
# WHAT THIS CORRECTS. The destination profile was built on the assumption that each business sharing the
# owner's Odoo has its own Odoo COMPANY, so that `company_id` was the isolation boundary and a record in
# another company was by definition another business's record. That assumption is false for this
# installation: there is ONE legal company, and several unrelated projects operate inside it. Company and
# journal therefore say WHERE a document is written; they say nothing about WHOSE it is.
#
# WHAT ISOLATION IS INSTEAD. Two separate things, and they answer two separate questions:
#
#   * OURS? -- the source stamp in Odoo's `ref`, which no other project writes. That is the only thing that
#     makes a record ours, and it is what every lookup matches exactly (Odoo::SourceStamp).
#   * WHOSE REVENUE? -- an Odoo ANALYTIC ACCOUNT carried on every revenue line as an analytic distribution,
#     which is how Odoo segregates a project's profit and loss inside one legal entity. That is what these
#     columns configure.
#
# TWO MODES, BOTH EXPLICIT AND BOTH VALIDATED. `analytic` is the real answer. `income_account` exists because
# an Odoo that cannot do analytic accounting must not fall back to writing unattributed revenue into a shared
# company: the operator configures a dedicated income account instead, the capability probe validates it is
# an income account in the configured company, and every revenue line carries it. Neither mode can be left
# unconfigured and neither is skipped silently -- `Odoo::DestinationProfile#scope_complete?` requires the
# mode's own columns and the capability proof refuses a destination whose attribution has not been proven.
#
# Additive and `change`-based: every column is new and nullable or defaulted, so it inverts mechanically.
class AddProjectAttributionToOdooDestinations < ActiveRecord::Migration[7.2]
  def change
    # Which mechanism attributes this project's revenue. Defaulted rather than nullable so there is no third,
    # unnamed state: a profile is either attributing analytically or through a dedicated income account.
    add_column :odoo_destination_profiles, :attribution_mode, :string, null: false, default: 'analytic'

    # The analytic PLAN the configured analytic account belongs to. Captured because Odoo validates a
    # distribution per plan -- a plan whose applicability is mandatory for customer invoices will reject a
    # distribution that does not name one of ITS accounts -- so an operator reading the Settings screen needs
    # to see which plan they chose inside, not only which account.
    add_column :odoo_destination_profiles, :analytic_plan_id, :integer
    add_column :odoo_destination_profiles, :analytic_plan_name, :string

    # The `income_account` mode's account. Separate columns rather than reusing `default_product_id`: a
    # product carries an income account through its category, which is a mapping this integration does not own
    # and cannot verify, while an account id is a thing the probe can read and check the type of.
    add_column :odoo_destination_profiles, :income_account_id, :integer
    add_column :odoo_destination_profiles, :income_account_name, :string

    # WHAT EACH DOCUMENT WAS ACTUALLY ATTRIBUTED TO, recorded on the document rather than inferred from the
    # profile. The profile is mutable: an operator who repoints it at a different analytic account would
    # otherwise silently rewrite the history of every document already in Odoo, which is the opposite of an
    # audit trail. With these columns a mapping still describes itself correctly afterwards, and the Invoices
    # screen can show an attribution that disagrees with the current profile instead of hiding it.
    add_column :odoo_document_mappings, :attribution_mode, :string
    add_column :odoo_document_mappings, :odoo_analytic_account_id, :integer
    add_column :odoo_document_mappings, :odoo_income_account_id, :integer

    # Whether the attribution was CONFIRMED by reading the document back out of Odoo, as opposed to merely
    # sent. The distinction matters: Odoo computes `analytic_distribution` on lines where it was not supplied,
    # and a distribution model in the destination database could overwrite ours, so the only honest answer
    # comes from a read.
    add_column :odoo_document_mappings, :attribution_verified_at, :datetime

    # The Invoices and Transactions screens filter on this when an operator is looking for documents that
    # reached Odoo without attribution -- the one failure that would quietly mix this project's revenue into
    # the shared company's books. Partial, because the rows that satisfy it should always be none.
    add_index :odoo_document_mappings, %i[odoo_destination_profile_id occurred_at],
              where: 'attribution_verified_at IS NULL AND odoo_record_id IS NOT NULL',
              name: 'index_odoo_documents_on_unverified_attribution'
  end
end
