# Puts Sidekiq's own numbers somewhere an operator can see them.
#
# Before this, queue depth, retry size and dead-set growth existed only inside Sidekiq's Redis and were readable only
# by signing in to /monitoring/sidekiq as a super admin or by opening a rails console over SSH. Nothing emitted them,
# so "the worker has been behind for two hours" and "jobs have been dying since the deploy" were both invisible until
# somebody went looking.
#
# It reads Sidekiq::Stats, which is the API Sidekiq's own dashboard uses -- no new collector, no new storage. It runs
# on the schedule in config/schedule.yml alongside the other recurring jobs.
#
# Reporting rules, so this does not become noise:
#   * one info line every run, which is the time series an operator can grep for after an incident;
#   * a warning only when a queue is over its threshold, or the dead set has grown since the last run;
#   * an error only when no worker process is registered at all, because then nothing async is happening -- no
#     WhatsApp sends, no commerce sync, no campaigns -- and that is the one case worth waking someone for.
#
# A deep queue is not automatically a problem: a bulk import legitimately enqueues thousands. So the threshold is
# generous and configurable, and the dead-set signal is a DELTA rather than a level, because a dead set that has sat
# at the same size for a week needs no alert and one that grew by 50 in ten minutes does.
class Lynomia::QueueHealthJob < ApplicationJob
  queue_as :housekeeping

  DEPTH_THRESHOLD = ENV.fetch('QUEUE_DEPTH_WARN', 1_000).to_i
  LATENCY_THRESHOLD = ENV.fetch('QUEUE_LATENCY_WARN_SECONDS', 300).to_i
  DEAD_MARKER = 'LYNOMIA::QUEUE_HEALTH::DEAD_SIZE'.freeze
  DEAD_MARKER_TTL = 1.day

  def perform
    require 'sidekiq/api'

    stats = Sidekiq::Stats.new
    processes = Sidekiq::ProcessSet.new.size

    report_overall(stats, processes)
    report_backlog
    report_dead_growth(stats.dead_size)
  end

  private

  def report_overall(stats, processes)
    level = processes.zero? ? :error : :info
    Lynomia::OperatorLog.emit(
      level, 'QUEUE_HEALTH',
      processes: processes, enqueued: stats.enqueued, scheduled: stats.scheduled_size,
      retrying: stats.retry_size, dead: stats.dead_size, failed_total: stats.failed, processed_total: stats.processed
    )
    record_worker_signal(stats, processes)
  end

  # No registered worker process is the one case worth waking someone for, so it is the one that also becomes a
  # durable row: nothing async is happening at all. The info line above stays the time series an operator greps;
  # this is what the Operations Center can sort and link.
  def record_worker_signal(stats, processes)
    recorder = Operations::SignalRecorder.new(source: :queue)
    if processes.zero?
      recorder.record(:no_workers, severity: :critical, reason: 'No Sidekiq process is registered',
                                   detail: { enqueued: stats.enqueued, scheduled: stats.scheduled_size,
                                             retrying: stats.retry_size, dead: stats.dead_size })
    else
      recorder.resolve(:no_workers)
    end
  end

  # Per queue, because queues here are strict-priority: a flooded high-priority queue starves every queue below it,
  # so the total alone does not say which work has stopped.
  def report_backlog
    Sidekiq::Queue.all.each do |queue|
      next if queue.size < DEPTH_THRESHOLD && queue.latency < LATENCY_THRESHOLD

      Lynomia::OperatorLog.warn(
        'QUEUE_BACKLOG', queue: queue.name, size: queue.size, latency_seconds: queue.latency.round,
                         depth_threshold: DEPTH_THRESHOLD, latency_threshold: LATENCY_THRESHOLD
      )
      Operations::SignalRecorder.new(source: :queue).record(
        :backlog, severity: :warning, reason: "Queue #{queue.name} is over its threshold",
                  detail: { queue: queue.name, size: queue.size, latency_seconds: queue.latency.round,
                            depth_threshold: DEPTH_THRESHOLD, latency_threshold: LATENCY_THRESHOLD }
      )
    end
    resolve_recovered_backlogs
  end

  # A queue that came back under its threshold clears its own signal. Per queue, because one flooded queue
  # recovering says nothing about the others.
  def resolve_recovered_backlogs
    Operations::Signal.open_signals.where(source: 'queue', signal: 'backlog').find_each do |signal|
      name = signal.detail['queue']
      next if name.blank?

      queue = Sidekiq::Queue.new(name)
      next if queue.size >= DEPTH_THRESHOLD || queue.latency >= LATENCY_THRESHOLD

      signal.update!(resolved_at: Time.current)
    end
  end

  # The dead set only ever grows on its own, so its size is uninteresting and its growth is the signal. The previous
  # size lives in Redis with a TTL: losing it just means the next run re-baselines instead of reporting a false jump.
  def report_dead_growth(dead_size)
    previous = Redis::Alfred.get(DEAD_MARKER)&.to_i
    Redis::Alfred.set(DEAD_MARKER, dead_size, ex: DEAD_MARKER_TTL.to_i)
    return if previous.nil? || dead_size <= previous

    Lynomia::OperatorLog.warn('QUEUE_DEAD_SET_GREW', previous: previous, current: dead_size, added: dead_size - previous)
    Operations::SignalRecorder.new(source: :queue).record(
      :dead_set_grew, severity: :warning, reason: 'Jobs have been moved to the dead set since the last check',
                      detail: { previous: previous, current: dead_size, added: dead_size - previous }
    )
  end
end
