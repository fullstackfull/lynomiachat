require 'rails_helper'

# Flow versions (docs/flow-builder/03-data-model-and-versioning.md): one draft, immutable published versions, publish
# only after the server-side graph check.
RSpec.describe Flows::Versions do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:versions) { described_class.new(bot, user: admin) }
  let(:graph) do
    { 'nodes' => [{ 'id' => 'start', 'type' => 'start', 'position' => { 'x' => 0, 'y' => 0 }, 'data' => {} },
                  { 'id' => 'hello', 'type' => 'send_message', 'position' => { 'x' => 0, 'y' => 100 },
                    'data' => { 'text' => 'Hi {{contact.name}}' } },
                  { 'id' => 'end', 'type' => 'end', 'position' => { 'x' => 0, 'y' => 200 }, 'data' => {} }],
      'edges' => [{ 'id' => 'e1', 'source' => 'start', 'sourceHandle' => 'next', 'target' => 'hello' },
                  { 'id' => 'e2', 'source' => 'hello', 'sourceHandle' => 'next', 'target' => 'end' }] }
  end

  it 'starts a draft from the starter graph' do
    expect(versions.draft.graph['nodes'].pluck('type')).to eq(%w[start end])
  end

  it 'publishes the draft, and edits a new draft without touching the published version' do
    versions.save!(graph)
    published = versions.publish!
    expect(published).to have_attributes(status: 'published', version: 1, published_by: admin)

    next_draft = versions.draft
    expect(next_draft).to have_attributes(status: 'draft', version: 2)
    expect(next_draft.graph).to eq(graph)
    versions.save!(graph.merge('nodes' => graph['nodes'].map { |node| node['id'] == 'hello' ? node.merge('data' => { 'text' => 'v2' }) : node }))
    expect(published.reload.graph).to eq(graph)

    expect(versions.publish!.version).to eq(2)
    expect(published.reload).to be_archived
    expect(bot.published_flow_version.version).to eq(2)
  end

  it 'never changes a published graph' do
    versions.save!(graph)
    published = versions.publish!

    expect(published.update(graph: { 'nodes' => [], 'edges' => [] })).to be(false)
    expect(published.errors[:graph]).to be_present
  end

  it 'refuses to publish an invalid graph, with errors per node' do
    versions.save!(graph.merge('edges' => graph['edges'].first(1)))

    expect { versions.publish! }.to raise_error(described_class::Invalid) { |error|
      expect(error.errors).to include(hash_including(code: 'unconnected_output', node_id: 'hello', detail: 'next'))
    }
    expect(bot.published_flow_version).to be_nil
  end

  it 'refuses a malformed draft when saving' do
    expect { versions.save!({ 'nodes' => 'x' }) }.to raise_error(described_class::Invalid)
    expect { versions.save!(graph.merge('nodes' => graph['nodes'] + [{ 'id' => 'x', 'type' => 'eval', 'position' => { 'x' => 0, 'y' => 0 } }])) }
      .to raise_error(described_class::Invalid)
  end

  it 'keeps flow bots account-scoped flow bots without a webhook' do
    expect(build(:agent_bot, account: nil, bot_type: :flow, outgoing_url: nil)).not_to be_valid
    expect(build(:agent_bot, account: account, bot_type: :flow, outgoing_url: 'https://example.com')).not_to be_valid
    expect(bot.update(bot_type: :webhook)).to be(false)
  end
end
