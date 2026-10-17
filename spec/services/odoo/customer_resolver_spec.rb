require 'rails_helper'

# Which Odoo partner is which Lynomia account (custom/app/services/odoo/customer_resolver.rb).
#
# THE EXAMPLES THAT MATTER are the two merge cases. The owner's Odoo holds several businesses' partners, and
# two unrelated Lynomia accounts can legitimately share a billing email, so a resolver that matched on email
# or name would eventually bill two customers onto one ledger.
RSpec.describe Odoo::CustomerResolver do
  subject(:resolver) { described_class.new(profile, accounting: accounting) }

  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile) }
  let(:accounting) { instance_double(Odoo::Accounting) }
  let(:account) { create(:account, name: 'Premier Care') }

  before do
    allow(accounting).to receive(:find_partners).and_return([])
    allow(accounting).to receive(:create_partner).and_return(701)
  end

  it 'creates a partner the first time and records how it was decided' do
    mapping = resolver.resolve!(account)

    expect(mapping.odoo_partner_id).to eq(701)
    expect(mapping.matched_by).to eq('created')
    expect(mapping).to be_state_synchronized
  end

  it 'names the partner so an accountant can tell two same-named accounts apart' do
    resolver.resolve!(account)

    expect(accounting).to have_received(:create_partner)
      .with(hash_including(name: "Premier Care (Lynomia Chat ##{account.id})"))
  end

  it 'does not create a second partner on a second resolve' do
    first = resolver.resolve!(account)
    allow(accounting).to receive(:create_partner).and_raise('must not be called again')

    expect(resolver.resolve!(account)).to eq(first)
  end

  # Not by email, not by name: by the stamp we wrote ourselves, inside the destination scope.
  it 'adopts a partner carrying our own stamp rather than creating another' do
    allow(accounting).to receive(:find_partners).and_return([{ 'id' => 512, 'ref' => 'x' }])

    mapping = resolver.resolve!(account)

    expect(mapping.odoo_partner_id).to eq(512)
    expect(mapping.matched_by).to eq('source_reference')
    expect(accounting).not_to have_received(:create_partner)
  end

  describe 'two accounts that share a billing email' do
    let(:other) { create(:account, name: 'Premier Care') }

    # THE CASE THE BRIEF NAMES: "Two unrelated Lynomia accounts with the same email must not be silently
    # merged into one customer."
    it 'gives each account its own partner' do
      allow(accounting).to receive(:create_partner).and_return(701, 702)

      first = resolver.resolve!(account)
      second = resolver.resolve!(other)

      expect(first.odoo_partner_id).to eq(701)
      expect(second.odoo_partner_id).to eq(702)
      expect(first.source_reference).not_to eq(second.source_reference)
    end

    # And when something DOES try to put them on one partner, the database refuses and a person is asked.
    it 'refuses the merge and flags the mapping for review when both resolve to one partner' do
      allow(accounting).to receive(:create_partner).and_return(701)
      resolver.resolve!(account)

      expect { resolver.resolve!(other) }.to raise_error(described_class::Conflict, /partner_claimed/)

      flagged = Odoo::CustomerMapping.find_by(account_id: other.id)
      expect(flagged).to be_state_needs_review
      expect(flagged.review_reason).to eq('partner_claimed_by_another_account')
    end
  end

  it 'asks a person rather than picking one when our stamp matches two partners' do
    allow(accounting).to receive(:find_partners).and_return([{ 'id' => 1 }, { 'id' => 2 }])

    expect { resolver.resolve!(account) }.to raise_error(described_class::Conflict, /several_partners/)
    expect(Odoo::CustomerMapping.find_by(account_id: account.id)).to be_state_needs_review
  end
end
