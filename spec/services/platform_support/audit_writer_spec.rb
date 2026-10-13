require 'rails_helper'

# The §10 audit proofs, on the writer itself rather than only through the services that call it.
RSpec.describe PlatformSupport::AuditWriter do
  let(:account) { create(:account) }
  let(:super_admin) { create(:super_admin) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter_name: 'Reporter', subject: 'Template stuck',
                                    category: 'whatsapp', priority: :high)
  end

  it 'refuses to write without an actor, because there is no ambient actor worth inferring here' do
    expect { described_class.new(actor: nil) }.to raise_error(ArgumentError, /actor is required/)
  end

  it 'names the real super admin as the actor and snapshots their display name' do
    described_class.new(actor: super_admin).write(ticket, 'status_changed')

    audit = Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').last
    expect(audit).to have_attributes(user_id: super_admin.id, username: super_admin.available_name)
  end

  # This is what keeps operator activity off the customer's own Audit Logs page: `for_account` matches on
  # `associated_type`/`associated_id`, and a row with neither is installation-wide.
  it 'leaves `associated` empty, so a tenant administrator never sees the row in their own trail' do
    described_class.new(actor: super_admin).write(ticket, 'assigned')

    audit = Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').last
    expect(audit).to have_attributes(associated_type: nil, associated_id: nil)
    expect(Custom::AuditLog.for_account(account).where(auditable_type: 'PlatformSupport::Ticket')).to be_empty
  end

  it 'comments with the dotted platform_support event name' do
    described_class.new(actor: super_admin).write(ticket, 'internal_note_added')

    expect(Custom::AuditLog.last.comment).to eq('platform_support.internal_note_added')
  end

  it 'records a creation as a create and everything else as an update' do
    writer = described_class.new(actor: super_admin)
    writer.write(ticket, 'created')
    writer.write(ticket, 'closed')

    expect(Custom::AuditLog.where(auditable: ticket).order(:id).pluck(:action)).to eq(%w[create update])
  end

  it 'carries ids, enum values and the reference string, and nothing free-form' do
    described_class.new(actor: super_admin).write(ticket, 'status_changed', { 'from' => 'open', 'to' => 'resolved' })

    expect(Custom::AuditLog.last.audited_changes).to eq(
      'ticket_id' => ticket.id, 'reference' => ticket.reference, 'subject_account_id' => account.id,
      'status' => 'open', 'priority' => 'high', 'category' => 'whatsapp',
      'event' => 'status_changed', 'from' => 'open', 'to' => 'resolved'
    )
  end

  it 'keeps the subject account id in the payload without associating the row to that account' do
    described_class.new(actor: super_admin).write(ticket, 'assigned')

    audit = Custom::AuditLog.last
    expect(audit.audited_changes['subject_account_id']).to eq(account.id)
    expect(audit.associated_id).to be_nil
  end

  # Not best-effort: nothing downstream depends on the audit having happened, so a decision that cannot be
  # recorded did not happen.
  it 'raises rather than swallowing a failed write' do
    allow(Custom::AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Custom::AuditLog.new))

    expect { described_class.new(actor: super_admin).write(ticket, 'closed') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end
end
