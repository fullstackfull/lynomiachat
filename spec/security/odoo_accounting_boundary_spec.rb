require 'rails_helper'

# THE COMMERCE BOUNDARY (the brief, §13; docs/odoo/00-discovery.md §1).
#
# Two completely different kinds of money pass through this installation and only one of them is Lynomia's.
# `billing_*` is the platform owner's own SaaS revenue and is what Odoo receives. `commerce_carts.visible_total`
# and `commerce_contact_metrics.spend` are a TENANT's sales to THEIR customers: Lynomia is not a party to them,
# and posting them into the platform owner's ledger would be a material misstatement of that ledger.
#
# These examples are structural rather than behavioural on purpose. A behavioural test would only catch the
# mistake once somebody had written the code to make it; reading the source catches it at review time, and a
# future contributor who adds a commerce read to this integration gets a failing spec that explains why.
ODOO_SOURCES = Dir[Rails.root.join('custom/app/services/odoo/**/*.rb'),
                   Rails.root.join('custom/app/models/odoo/**/*.rb'),
                   Rails.root.join('custom/app/jobs/odoo/**/*.rb'),
                   Rails.root.join('custom/app/controllers/super_admin/odoo_accounting_controller.rb')].freeze

# The tenant-owned commerce domain. Nothing in the Odoo integration has any reason to name any of it.
MERCHANT_CONSTANTS = %w[Commerce::Cart Commerce::Store Commerce::CustomerLink Commerce::ContactMetric
                        Commerce::Order commerce_carts commerce_stores commerce_contact_metrics
                        commerce_customer_links].freeze

RSpec.describe 'Odoo accounting boundary', type: :request do
  include_context 'with commerce encryption'

  # COMMENTS ARE STRIPPED FIRST. The Odoo sources name Commerce::HttpClient, Commerce::Store and BillingPlan
  # in their comments on purpose -- to record which precedent a decision follows and which source of truth was
  # deliberately NOT used. The rule being tested is about code that runs, so prose about the rule must not
  # fail it.
  def code_of(path)
    File.read(path).lines.reject { |line| line.strip.start_with?('#') }.join
  end

  it 'has source files to check, so this spec cannot pass by finding nothing' do
    expect(ODOO_SOURCES.length).to be >= 15
  end

  it 'never names a merchant commerce table or model in code' do
    offenders = ODOO_SOURCES.flat_map do |path|
      body = code_of(path)
      MERCHANT_CONSTANTS.filter_map { |name| "#{Pathname(path).basename}: #{name}" if body.include?(name) }
    end

    expect(offenders).to be_empty,
                         "the Odoo integration must not read merchant commerce data: #{offenders.join(', ')}"
  end

  # A tenant's own shop revenue is not the platform owner's revenue. Proven by running the thing that decides
  # what gets exported against an installation that HAS merchant revenue and nothing else.
  it 'queues nothing for a merchant cart, however much money is in it' do
    profile = create(:odoo_destination_profile, :enabled)
    account = create(:account)
    store = create(:commerce_store, account: account)
    # Built directly rather than from a factory: there is no cart factory, and the point of the example is
    # that a real merchant cart with a real total exists and produces nothing here.
    Commerce::Cart.create!(account: account, commerce_store: store, provider: 'woocommerce',
                           provider_cart_id: 'wc-9001', visible_total: 9_999.99, currency: 'KWD',
                           first_seen_at: Time.current, last_provider_event_at: Time.current)

    expect(Odoo::SyncEvent.where(destination_profile: profile).count).to eq(0)
    expect(Odoo::DocumentMapping.count).to eq(0)
  end

  # The only money this integration reads is a Stripe invoice issued to a Lynomia tenant.
  it 'reads its amounts from Stripe invoices and from nothing else' do
    source = code_of(Rails.root.join('custom/app/services/odoo/stripe_source.rb'))

    expect(source).to include('Stripe::Invoice')
    expect(source).not_to include('BillingPlan')
    expect(code_of(Rails.root.join('custom/app/services/odoo/invoice_export.rb'))).not_to include('BillingPlan')
  end

  describe 'no public surface' do
    # The brief: "Do not expose any publicly accessible Odoo credentials endpoint. Do not introduce a new
    # public payment endpoint." Asserted against the real route table rather than against the routes file.
    it 'mounts every Odoo route under the Super Admin namespace and nowhere else' do
      odoo_routes = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s
        path if path.include?('odoo')
      end

      expect(odoo_routes).not_to be_empty
      expect(odoo_routes).to all(start_with('/super_admin/'))
    end

    it 'exposes no Odoo route in the tenant API or the platform API' do
      paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

      expect(paths.grep(%r{^/api/.*odoo})).to be_empty
      expect(paths.grep(%r{^/platform/.*odoo})).to be_empty
    end
  end
end
