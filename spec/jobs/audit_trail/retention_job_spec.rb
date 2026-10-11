require 'rails_helper'

# DECISION 5. Two properties are asserted here, and they pull in opposite directions on purpose: the trail must
# be bounded by time, and it must not be bounded by anything an audited party can reach.
#
# Rows are planted with Custom::AuditLog.create! rather than driven through the capture points, for the reason
# the sibling request spec gives: this file is about the sweep, not about what writes.
RSpec.describe AuditTrail::RetentionJob do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def plant(account_record, created_at)
    Custom::AuditLog.create!(associated_type: 'Account', associated_id: account_record.id, action: 'update',
                             auditable_type: 'Account', auditable_id: account_record.id, username: 'Operator',
                             audited_changes: { 'name' => %w[before after] }, created_at: created_at)
  end

  def ids_remaining
    Custom::AuditLog.pluck(:id)
  end

  describe 'the window' do
    it 'deletes an entry older than the configured retention' do
      old = plant(account, 400.days.ago)

      described_class.perform_now

      expect(ids_remaining).not_to include(old.id)
    end

    it 'keeps an entry inside the retention window' do
      recent = plant(account, 10.days.ago)

      described_class.perform_now

      expect(ids_remaining).to include(recent.id)
    end

    # The cutoff is a UTC day boundary, so the effective window is the configured days plus up to one. That
    # errs LONGER. An entry a few hours past the nominal 365 days is therefore still inside the window, and
    # this asserts the direction of the error rather than the exact second.
    it 'errs on keeping rather than deleting at the boundary' do
      just_past = plant(account, (365.days + 2.hours).ago)

      described_class.perform_now

      expect(ids_remaining).to include(just_past.id)
    end

    it 'never deletes an entry whose created_at is null, because the shared column is nullable' do
      undated = plant(account, 400.days.ago)
      Custom::AuditLog.where(id: undated.id).update_all(created_at: nil) # rubocop:disable Rails/SkipsModelValidations

      described_class.perform_now

      expect(ids_remaining).to include(undated.id)
    end
  end

  describe 'account safety' do
    it 'bounds every account by the same window and no account by another account activity' do
      mine_old = plant(account, 400.days.ago)
      theirs_old = plant(other_account, 400.days.ago)
      theirs_recent = plant(other_account, 1.day.ago)

      described_class.perform_now

      remaining = ids_remaining
      expect(remaining).not_to include(mine_old.id, theirs_old.id)
      expect(remaining).to include(theirs_recent.id)
    end
  end

  describe 'running more than once' do
    it 'is idempotent: a second run deletes nothing and does not raise' do
      plant(account, 400.days.ago)
      recent = plant(account, 1.day.ago)

      described_class.perform_now
      expect { described_class.perform_now }.not_to(change(Custom::AuditLog, :count))

      expect(ids_remaining).to eq([recent.id])
    end

    # Two runs overlapping race only on rows that are already condemned, which is why no lock is needed.
    it 'tolerates a concurrent run having already taken the rows' do
      plant(account, 400.days.ago)
      allow(Custom::AuditLog).to receive(:where).and_call_original

      expect { 2.times { described_class.perform_now } }.not_to raise_error
      expect(Custom::AuditLog.count).to eq(0)
    end
  end

  describe 'the configured window' do
    it 'reads the installation config on every run, so a change needs no deploy' do
      entry = plant(account, 100.days.ago)
      allow(GlobalConfigService).to receive(:load).with(described_class::CONFIG_KEY, described_class::DEFAULT_DAYS).and_return(60)

      described_class.perform_now

      expect(ids_remaining).not_to include(entry.id)
    end

    it 'defaults to 365 days when the installation has no config row' do
      allow(GlobalConfigService).to receive(:load).with(described_class::CONFIG_KEY, described_class::DEFAULT_DAYS)
                                                  .and_return(described_class::DEFAULT_DAYS)
      inside = plant(account, 300.days.ago)
      outside = plant(account, 400.days.ago)

      described_class.perform_now

      expect(ids_remaining).to include(inside.id)
      expect(ids_remaining).not_to include(outside.id)
    end
  end

  describe 'refusing a value that would destroy the trail' do
    it 'deletes nothing and says so when the window is below the minimum' do
      entry = plant(account, 400.days.ago)
      allow(GlobalConfigService).to receive(:load).with(described_class::CONFIG_KEY, described_class::DEFAULT_DAYS).and_return(0)
      expect(Lynomia::OperatorLog).to receive(:error).with(:AUDIT_RETENTION_MISCONFIGURED, hash_including(reason: 'below_minimum'))

      described_class.perform_now

      expect(ids_remaining).to include(entry.id)
    end

    it 'deletes nothing and says so when the window is not an integer' do
      entry = plant(account, 400.days.ago)
      allow(GlobalConfigService).to receive(:load).with(described_class::CONFIG_KEY, described_class::DEFAULT_DAYS).and_return('soon')
      expect(Lynomia::OperatorLog).to receive(:error).with(:AUDIT_RETENTION_MISCONFIGURED, hash_including(reason: 'not_an_integer'))

      described_class.perform_now

      expect(ids_remaining).to include(entry.id)
    end
  end

  describe 'bounding one run' do
    it 'stops at the per-run ceiling and reports that it was capped' do
      stub_const("#{described_class}::MAX_PER_RUN", 2)
      stub_const("#{described_class}::BATCH_SIZE", 1)
      3.times { plant(account, 400.days.ago) }
      expect(Lynomia::OperatorLog).to receive(:info).with(:AUDIT_RETENTION_SWEEP, hash_including(deleted: 2, capped: true))

      described_class.perform_now

      expect(Custom::AuditLog.count).to eq(1)
    end

    it 'takes the remainder on the next run' do
      stub_const("#{described_class}::MAX_PER_RUN", 2)
      3.times { plant(account, 400.days.ago) }

      2.times { described_class.perform_now }

      expect(Custom::AuditLog.count).to eq(0)
    end
  end

  describe 'observability' do
    it 'reports counts and the cutoff, never an entry content' do
      plant(account, 400.days.ago)
      lines = []
      allow(Rails.logger).to receive(:info) { |line| lines << line.to_s }

      described_class.perform_now

      line = lines.grep(/AUDIT_RETENTION_SWEEP/).first
      expect(line).to be_present
      expect(line).to include('deleted=1', 'retention_days=365')
      expect(line).not_to include('Operator')
      expect(line).not_to include('audited_changes')
    end
  end

  # The security property the decision turns on. It is asserted here rather than only in the capture specs
  # because this is the file a future reader opens when they wonder whether retention gated anything else.
  describe 'capture, which this job must not gate' do
    it 'still records with audit_logs disabled for the account' do
      expect(account.feature_enabled?('audit_logs')).to be(false)

      expect { plant(account, Time.current) }.to change(Custom::AuditLog, :count).by(1)
    end

    it 'leaves the read gate alone: a disabled account still reads nothing' do
      plant(account, 1.day.ago)

      expect(AuditTrail::Query.new(account: account, params: {}).entries).to be_empty
    end
  end
end
