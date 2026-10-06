# frozen_string_literal: true

# The LOCAL PIPELINE section of a Lynomia WhatsApp diagnosis: the route Meta is expected to call, the job that
# processes a delivery, whether anything is consuming its queue, and the most recent failures that would explain a
# webhook accepted with 200 and then lost.
#
# Installation-wide facts (the worker, the queue config, the dead set) are reported once, on the first channel, so
# a multi-inbox report does not repeat the same check and count it several times in the summary.
#
# Reads only, and nothing here calls Meta.
class Whatsapp::Diagnosis::PipelineChecks
  include Whatsapp::Diagnosis::StoredConfig

  QUEUE_NOTE = 'A job enqueued to a queue no worker consumes is invisible and looks exactly like "Meta never ' \
               'called us": the controller answers 200, Sidekiq holds the job, and nothing processes it.'

  WORKER_NOTE = 'With no Sidekiq process alive, every webhook is accepted with 200 and never processed. Meta sees ' \
                'success and never retries.'

  INGEST_LOG_NOTE = 'Since docs/real-whatsapp-uat/09-fix.md, a refused inbound payload writes one structured line ' \
                    '`[WHATSAPP INGEST] event=... ` at error level. Grep the application log for it: a drop is no ' \
                    'longer visible only as a bare warning.'

  def initialize(report)
    @report = report
    @installation_reported = false
  end

  def run(channel, config)
    report.heading("LOCAL PIPELINE — inbox ##{channel.inbox&.id}")
    routes(channel)
    inactive_number_check(channel)
    job_and_queue(config)
    installation_wide
  end

  private

  attr_reader :report

  def routes(channel)
    report.rows(
      [
        ['FRONTEND_URL', ENV.fetch('FRONTEND_URL', '<unset>')],
        ['per-number route', "POST /webhooks/whatsapp/#{report.mask_phone(channel.phone_number)}"],
        ['app-level route', 'POST /webhooks/whatsapp (template status webhooks)']
      ]
    )
    report.say 'Meta must be able to reach the per-number route from the public internet.'
  end

  def job_and_queue(config)
    queue = Webhooks::WhatsappEventsJob.new.queue_name
    report.say "job: Webhooks::WhatsappEventsJob -> queue #{queue}"
    report.say "provider: #{config[:provider] || 'whatsapp_cloud'} -> " \
               'Whatsapp::IncomingMessageWhatsappCloudService (the one ingestion service)'
    report.say "  #{INGEST_LOG_NOTE}"
  end

  def installation_wide
    return report.say 'worker health: reported above for the first inbox' if @installation_reported

    @installation_reported = true
    queue_consumed_check
    sidekiq_runtime
  end

  def queue_consumed_check
    queue = Webhooks::WhatsappEventsJob.new.queue_name
    configured = sidekiq_queues
    report.say "queues in config/sidekiq.yml: #{configured.join(', ')}"
    report.check("the job's queue (#{queue}) is consumed by the worker config", configured.include?(queue),
                 configured.include?(queue) ? 'listed' : 'NOT LISTED', note: QUEUE_NOTE)
  end

  def sidekiq_runtime
    require 'sidekiq/api'
    sidekiq_stats
    processes = Sidekiq::ProcessSet.new
    report.check('at least one Sidekiq process is alive', processes.size.positive?, "#{processes.size} process(es)",
                 note: WORKER_NOTE)
    processes.each { |process| report.say "  process queues: #{Array(process['queues']).join(', ')}" }
    latest_failures
  rescue StandardError => e
    report.blocked('Sidekiq statistics', "#{e.class.name}: #{e.message.to_s[0, 120]}")
  end

  def sidekiq_stats
    stats = Sidekiq::Stats.new
    report.say "sidekiq processed=#{stats.processed} failed=#{stats.failed} enqueued=#{stats.enqueued} " \
               "retry=#{Sidekiq::RetrySet.new.size} dead=#{Sidekiq::DeadSet.new.size}"
    report.say "#{Webhooks::WhatsappEventsJob.queue_name} queue depth: " \
               "#{Sidekiq::Queue.new(Webhooks::WhatsappEventsJob.queue_name).size}"
  end

  # The error messages, never the job arguments: a WhatsApp webhook payload argument holds the customer's phone
  # number and the message body.
  def latest_failures
    report_set('dead', Sidekiq::DeadSet.new)
    report_set('retrying', Sidekiq::RetrySet.new)
  end

  def report_set(label, set)
    entries = set.select { |job| job.klass.to_s.include?('Whatsapp') }
    report.say "#{label} WhatsApp jobs: #{entries.size}"
    entries.first(3).each { |job| report.say "  #{label}: #{job.klass} — #{job['error_message'].to_s[0, 160]}" }
  end

  def inactive_number_check(channel)
    listed = inactive_numbers.include?(channel.phone_number)
    report.check(
      "inbox ##{channel.inbox&.id}: the number is NOT on the inactive list",
      !listed,
      listed ? 'LISTED AS INACTIVE' : 'not listed',
      note: 'Webhooks::WhatsappController answers 422 for a number on INACTIVE_WHATSAPP_NUMBERS and never enqueues ' \
            'the payload.'
    )
  end

  def inactive_numbers
    @inactive_numbers ||= stored_config('INACTIVE_WHATSAPP_NUMBERS').to_s.split(',').map(&:strip)
  end

  def sidekiq_queues
    path = Rails.root.join('config/sidekiq.yml')
    return [] unless path.exist?

    yaml = YAML.safe_load(ERB.new(path.read).result, aliases: true, permitted_classes: [Symbol])
    Array(yaml[:queues] || yaml['queues']).map { |queue| Array(queue).first.to_s }
  rescue StandardError
    []
  end
end
