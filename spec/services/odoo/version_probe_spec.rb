require 'rails_helper'

# Which Odoo is at the other end, read before any credential is sent (custom/app/services/odoo/version_probe.rb).
RSpec.describe Odoo::VersionProbe do
  subject(:probe) { described_class.new(profile) }

  let(:profile) { build(:odoo_destination_profile, odoo_version: nil, transport: nil) }

  def answering(info)
    allow(Odoo::Transport::JsonRpc).to receive(:new).with(profile).and_return(
      instance_double(Odoo::Transport::JsonRpc, version: info)
    )
  end

  it 'chooses the JSON-2 transport for Odoo 19 and above' do
    answering({ 'server_version' => '19.0', 'server_version_info' => [19, 0, 0, 'final', 0, ''] })

    result = probe.call

    expect(result).to be_ok
    expect(result.major).to eq(19)
    expect(result.transport).to eq('json2')
  end

  it 'chooses the legacy JSON-RPC transport below Odoo 19' do
    answering({ 'server_version' => '17.0', 'server_version_info' => [17, 0, 0, 'final', 0, ''] })

    expect(probe.call.transport).to eq('jsonrpc')
  end

  # THE ODOO ONLINE CASE, and the one this file exists for. Odoo's own release.py says the MAJOR version "can
  # become an arbitrary string (saas~xx)" during release, and a live call to www.odoo.com answers
  # ["saas~19", 3, 0, "final", 0, "e"]. An integer check here would refuse every real Odoo Online tenant.
  it 'reads the major version out of an Odoo Online saas~ string' do
    answering({ 'server_version' => 'saas~19.3+e', 'server_version_info' => ['saas~19', 3, 0, 'final', 0, 'e'] })

    result = probe.call

    expect(result).to be_ok
    expect(result.major).to eq(19)
    expect(result.transport).to eq('json2')
    expect(result.version).to eq('saas~19.3+e')
  end

  it 'refuses a version older than the accounting model this adapter implements' do
    answering({ 'server_version' => '15.0', 'server_version_info' => [15, 0, 0, 'final', 0, ''] })

    result = probe.call

    expect(result).not_to be_ok
    expect(result.error['reason']).to eq('unsupported_major_15')
  end

  it 'answers rather than raising when the server is unreachable' do
    allow(Odoo::Transport::JsonRpc).to receive(:new).and_raise(Odoo::Error.new('UNREACHABLE', reason: 'dns'))

    result = probe.call

    expect(result).not_to be_ok
    expect(result.error).to eq({ 'code' => 'UNREACHABLE', 'reason' => 'dns' })
  end

  it 'reports an answer with no version information instead of guessing one' do
    answering({ 'server_version_info' => [] })

    expect(probe.call.error['reason']).to eq('no_major_version')
  end
end
