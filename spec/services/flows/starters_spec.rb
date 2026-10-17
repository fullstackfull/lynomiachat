require 'rails_helper'

# THE POINT OF THIS FILE IS THE FIRST EXAMPLE.
#
# A starter template is only worth offering if the graph it produces will publish. Templates
# authored in a client are graphs nobody checked until a merchant pressed Publish and was told
# their starting point was invalid -- so every starter here is run through the real
# Flows::GraphValidator, against a real account, with the features it declares it needs.
RSpec.describe Flows::Starters do
  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder', 'lynomia_commerce') } }

  it 'ships only graphs the real validator accepts' do
    described_class::ALL.each do |starter|
      errors = Flows::GraphValidator.new(account, starter[:graph].deep_dup).errors

      expect(errors).to be_empty, "starter #{starter[:id]} does not validate: #{errors.inspect}"
    end
  end

  it 'declares the node count it really has, so a client can describe it without parsing it' do
    described_class::ALL.each do |starter|
      expect(starter[:graph]['nodes'].size).to eq(starter[:nodes]), starter[:id].to_s
    end
  end

  # A label, team, agent or custom attribute is validated against the ACCOUNT, so a starter
  # naming one would be valid for the account it was written against and refused for everybody
  # else. This is the check that keeps that true as starters are added.
  it 'names none of an account own records' do
    described_class::ALL.each do |starter|
      keys = starter[:graph]['nodes'].flat_map { |node| node['data'].keys }

      expect(keys).not_to include('labels', 'agent_id', 'team_id'), starter[:id].to_s
    end
  end

  it 'publishes end to end, through the service a merchant would use' do
    bot = create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil)
    versions = Flows::Versions.new(bot)

    versions.save!(described_class.welcome_menu, lock_version: 0)

    expect { versions.publish! }.to change { bot.reload.published_flow_version }.from(nil)
  end

  describe '.for' do
    it 'reports a starter the account cannot use rather than hiding it' do
      plain = create(:account)

      starters = described_class.for(plain).index_by { |starter| starter[:id] }

      expect(starters['welcome_menu']).to include(available: true, missing: [])
      expect(starters['order_status']).to include(available: false, missing: ['lynomia_commerce'])
    end

    it 'offers every starter to an account with the features' do
      expect(described_class.for(account).pluck(:available)).to all(be(true))
    end
  end
end
