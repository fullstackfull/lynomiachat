require 'rails_helper'
require 'sidekiq/api'

RSpec.describe Lynomia::QueueHealthJob do
  let(:stats) do
    instance_double(Sidekiq::Stats, enqueued: 4, scheduled_size: 1, retry_size: 0, dead_size: 7,
                                    failed: 12, processed: 900)
  end
  let(:captured) { { info: [], warn: [], error: [] } }

  before do
    allow(Sidekiq::Stats).to receive(:new).and_return(stats)
    allow(Sidekiq::Queue).to receive(:all).and_return([])
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(instance_double(Sidekiq::ProcessSet, size: 1))
    captured.each_key { |level| allow(Rails.logger).to receive(level) { |line| captured[level] << line } }
    Redis::Alfred.delete(described_class::DEAD_MARKER)
  end

  after { Redis::Alfred.delete(described_class::DEAD_MARKER) }

  it 'writes one line per run with the numbers an operator would otherwise need the dashboard for' do
    described_class.perform_now

    expect(captured[:info].grep(/QUEUE_HEALTH/).first)
      .to include('processes=1', 'enqueued=4', 'retrying=0', 'dead=7', 'processed_total=900')
  end

  it 'escalates to error when no worker process is registered, because nothing async is running' do
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(instance_double(Sidekiq::ProcessSet, size: 0))

    described_class.perform_now

    expect(captured[:error].grep(/QUEUE_HEALTH/).first).to include('processes=0')
    expect(captured[:info].grep(/QUEUE_HEALTH/)).to be_empty
  end

  it 'warns about a queue over the depth threshold, naming the queue' do
    deep = instance_double(Sidekiq::Queue, name: 'high', size: described_class::DEPTH_THRESHOLD + 1, latency: 2.0)
    allow(Sidekiq::Queue).to receive(:all).and_return([deep])

    described_class.perform_now

    expect(captured[:warn].grep(/QUEUE_BACKLOG/).first).to include('queue=high', "size=#{described_class::DEPTH_THRESHOLD + 1}")
  end

  it 'warns about a queue that is slow even when it is shallow' do
    slow = instance_double(Sidekiq::Queue, name: 'default', size: 3, latency: described_class::LATENCY_THRESHOLD + 10.0)
    allow(Sidekiq::Queue).to receive(:all).and_return([slow])

    described_class.perform_now

    expect(captured[:warn].grep(/QUEUE_BACKLOG/).first).to include('queue=default', 'latency_seconds=310')
  end

  it 'stays quiet about a healthy queue' do
    fine = instance_double(Sidekiq::Queue, name: 'low', size: 2, latency: 1.0)
    allow(Sidekiq::Queue).to receive(:all).and_return([fine])

    described_class.perform_now

    expect(captured[:warn].grep(/QUEUE_BACKLOG/)).to be_empty
  end

  describe 'dead set' do
    it 'reports nothing on the first run, because there is no baseline to compare with' do
      described_class.perform_now
      expect(captured[:warn].grep(/QUEUE_DEAD_SET_GREW/)).to be_empty
    end

    it 'warns only when the dead set has grown since the last run' do
      described_class.perform_now
      allow(stats).to receive(:dead_size).and_return(10)

      described_class.perform_now

      expect(captured[:warn].grep(/QUEUE_DEAD_SET_GREW/).first).to include('previous=7', 'current=10', 'added=3')
    end

    it 'stays quiet when the dead set is unchanged or smaller' do
      described_class.perform_now
      allow(stats).to receive(:dead_size).and_return(7)
      described_class.perform_now
      allow(stats).to receive(:dead_size).and_return(2)

      described_class.perform_now

      expect(captured[:warn].grep(/QUEUE_DEAD_SET_GREW/)).to be_empty
    end
  end
end
