# frozen_string_literal: true

# Staging harness bootstrap. Loaded with `rails runner` in RAILS_ENV=production against a staging DB.
# - Routes graph.facebook.com / lookaside.fbsbx.com to FakeGraph (no real Meta calls).
# - Runs ActiveJob and Sidekiq jobs inline so a webhook POST is fully processed before the next step.
# - Sends HTTP requests through the real Rails stack (routing, controllers, before_actions).
require 'webmock'
require 'sidekiq/testing'
require_relative 'fake_graph'

include WebMock::API
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)
stub_request(:any, /.*/).to_return(status: 404, body: '') # anything else (avatars, hub) fails closed
stub_request(:any, /graph\.facebook\.com|lookaside\.fbsbx\.com/).to_rack(FakeGraph)

# Immediate jobs run inline; delayed jobs (enqueue_at) are only recorded, like a paused scheduler.
# A failing follow-up job is recorded (as Sidekiq would retry it) instead of failing the request that enqueued it.
class HarnessAdapter
  DELAYED = []
  JOB_ERRORS = []
  PRIMARY = %w[Webhooks::WhatsappEventsJob SendReplyJob].freeze

  def enqueue(job)
    ActiveJob::Base.execute(job.serialize)
  rescue StandardError => e
    raise if PRIMARY.include?(job.class.name)

    JOB_ERRORS << "#{job.class.name}: #{e.class}: #{e.message[0, 120]}"
  end

  def enqueue_at(job, _ts) = DELAYED << job.class.name
  def enqueue_after_transaction_commit? = false
end
ActiveJob::Base.queue_adapter = HarnessAdapter.new
Sidekiq::Testing.inline!
ActionMailer::Base.delivery_method = :test
Rails.logger.level = :warn

module H
  RESULTS = []
  APP_SECRET = 'staging-app-secret'

  module_function

  def check(name, ok, detail = nil)
    RESULTS << { name: name, ok: ok ? true : false, detail: detail }
    puts "#{ok ? 'PASS' : 'FAIL'}  #{name}#{detail ? "  -- #{detail}" : ''}"
    ok
  end

  def session
    @session ||= ActionDispatch::Integration::Session.new(Rails.application).tap { |s| s.host! 'staging.lynomia.local' }
  end

  def post_webhook(phone_number, payload, secret: APP_SECRET)
    body = payload.to_json
    sig = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    session.post("/webhooks/whatsapp/#{phone_number}", params: body,
                                                      headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => sig })
    session.response.status
  end

  def api(method, path, user, params = {})
    session.public_send(method, path, params: params.to_json,
                                      headers: { 'CONTENT_TYPE' => 'application/json', 'api_access_token' => user.access_token.token })
    [session.response.status, (JSON.parse(session.response.body) rescue session.response.body)]
  end

  # Cloud API webhook envelope
  def envelope(waba_id, phone_id, display, value_extra, field: 'messages')
    { object: 'whatsapp_business_account',
      entry: [{ id: waba_id, changes: [{ field: field, value: { messaging_product: 'whatsapp',
                                                               metadata: { display_phone_number: display, phone_number_id: phone_id } }.merge(value_extra) }] }] }
  end

  def inbound(waba_id, phone_id, display, from:, id:, type:, content:, name: 'Customer', context: nil)
    msg = { from: from, id: id, timestamp: Time.now.to_i.to_s, type: type, type.to_sym => content }
    msg[:context] = context if context
    envelope(waba_id, phone_id, display, { contacts: [{ profile: { name: name }, wa_id: from }], messages: [msg] })
  end

  def status(waba_id, phone_id, display, wamid:, status:, recipient:)
    envelope(waba_id, phone_id, display, { statuses: [{ id: wamid, status: status, timestamp: Time.now.to_i.to_s, recipient_id: recipient }] })
  end

  def echo(waba_id, phone_id, display, to:, id:, type:, content:, from: nil)
    envelope(waba_id, phone_id, display,
             { message_echoes: [{ from: from || display.delete('+ -'), to: to, id: id, timestamp: Time.now.to_i.to_s, type: type, type.to_sym => content }] },
             field: 'smb_message_echoes')
  end

  def write_results(path)
    HarnessAdapter::JOB_ERRORS.tally.each { |e, n| puts "INFO  follow-up job error x#{n}: #{e}" }
    File.write(path, JSON.pretty_generate(RESULTS))
    failed = RESULTS.count { |r| !r[:ok] }
    puts "\n#{RESULTS.size - failed}/#{RESULTS.size} checks passed -> #{path}"
  end
end
