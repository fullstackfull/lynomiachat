require 'rails_helper'

# The safety net under the accounting queue (custom/app/jobs/odoo/sync_sweep_job.rb).
#
# IT USED TO BE UNSCHEDULED, which made the retry schedule a record of intent rather than something that
# happens: Odoo::SyncRunner wrote `run_after` on a transient failure and nothing ever came back to read it, so
# a row that failed once stayed `retrying` for ever. These examples are about it actually running.
RSpec.describe Odoo::SyncSweepJob do
  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, :enabled) }

  # THE REGISTRATION ITSELF, because a sweep that is not scheduled is indistinguishable from one that finds
  # nothing. spec/configs/schedule_spec.rb separately proves every entry's class and queue resolve.
  describe 'its registration' do
    let(:entry) { YAML.safe_load(Rails.root.join('config/schedule.yml').read, aliases: true)['odoo_sync_sweep_job'] }

    it 'is registered as a recurring job on a served queue' do
      expect(entry).to be_present
      expect(entry['class']).to eq(described_class.name)
      expect(entry['cron']).to eq('*/5 * * * *')
      expect(entry['queue']).to eq('scheduled_jobs')
      # The declared queue and the scheduled queue agree, so a sweep enqueued by hand from a console behaves
      # the way the scheduled one does.
      expect(described_class.new.queue_name).to eq(entry['queue'])
    end
  end

  describe 'what it picks up' do
    it 'enqueues a row whose retry backoff has expired' do
      due = create(:odoo_sync_event, destination_profile: profile, state: :retrying, run_after: 5.minutes.ago)

      expect { described_class.perform_now }.to have_enqueued_job(Odoo::SyncJob).with(due.id)
    end

    it 'leaves a row whose backoff has not expired alone' do
      create(:odoo_sync_event, destination_profile: profile, state: :retrying, run_after: 1.hour.from_now)

      expect { described_class.perform_now }.not_to have_enqueued_job(Odoo::SyncJob)
    end

    # A worker killed mid-flight leaves `processing` and a `claimed_at`, and nothing else would ever look at
    # it again. Released rather than retried on the spot, so it goes through the normal attempt accounting.
    it 'releases a claim abandoned by a dead worker and queues it' do
      stale = create(:odoo_sync_event, destination_profile: profile, state: :processing,
                                       claimed_at: (Odoo::SyncEvent::STALE_CLAIM_AFTER + 1.minute).ago)

      expect { described_class.perform_now }.to have_enqueued_job(Odoo::SyncJob).with(stale.id)
      expect(stale.reload).to be_state_retrying
      expect(stale.claimed_at).to be_nil
    end

    it 'leaves a claim that is still fresh alone' do
      fresh = create(:odoo_sync_event, destination_profile: profile, state: :processing, claimed_at: 1.minute.ago)

      expect { described_class.perform_now }.not_to have_enqueued_job(Odoo::SyncJob)
      expect(fresh.reload).to be_state_processing
    end

    # The reason it is safe to run on every installation from the moment it is deployed: with no destination
    # there are no rows, because Odoo::EventRecorder only records when an ENABLED destination exists.
    it 'does nothing at all on an installation that has never configured Odoo' do
      expect { described_class.perform_now }.not_to have_enqueued_job(Odoo::SyncJob)
    end
  end
end
