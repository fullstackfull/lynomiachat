# frozen_string_literal: true

# Lynomia real WhatsApp diagnosis (docs/real-whatsapp-uat/10-real-uat-results.md).
#
# The real WABA, phone number and access token live only on the deployed server, so the live half of P5's diagnosis
# has to run there. This orchestrates that diagnosis as one read-only report, in the seven sections an operator
# works down in order:
#
#   CHANNEL            what this installation has stored          LocalChecks#channel_section
#   META IDENTITY      what Meta says the number is               MetaChecks#identity
#   AUTH               the credential, presence then validity     LocalChecks#auth + MetaChecks#auth
#   WABA SUBSCRIPTION  who is subscribed, and to what             MetaChecks#waba_subscription
#   WEBHOOK            where Meta will actually deliver           WebhookChecks
#   LOCAL PIPELINE     route, job, worker, latest failures        PipelineChecks
#   CONTACT TEST       traffic, the 24-hour window, last failure  InboundEvidence
#
# Hard rules, enforced by construction:
#   * every Meta call is a GET through the installation's existing Whatsapp::FacebookApiClient
#   * nothing is written to Meta, to the database or to Redis — there is no write path in any collaborator
#   * no credential value is printed, masked or otherwise; customer phone numbers are masked in one place
#   * the service never writes to stdout; the caller is handed each line and decides what to do with it
class Whatsapp::Diagnosis
  def initialize(inbox_id: nil, contact_identifier: nil, &emit)
    @inbox_id = inbox_id.presence
    @report = Whatsapp::Diagnosis::Report.new(&emit)
    @local = Whatsapp::Diagnosis::LocalChecks.new(@report)
    @meta = Whatsapp::Diagnosis::MetaChecks.new(@report)
    @webhook = Whatsapp::Diagnosis::WebhookChecks.new(@report)
    @pipeline = Whatsapp::Diagnosis::PipelineChecks.new(@report)
    @evidence = Whatsapp::Diagnosis::InboundEvidence.new(@report, contact_identifier: contact_identifier.presence)
  end

  # @return [String] the whole report, also emitted line by line to the block given to the constructor.
  def run
    preamble
    channels = resolve_channels
    return no_channel_report if channels.empty?

    channels.each { |channel| diagnose(channel) }
    @report.summarise
    @report.to_s
  end

  private

  def preamble
    @report.heading('LYNOMIA REAL WHATSAPP DIAGNOSIS — READ ONLY')
    @report.say "generated at #{Time.current.iso8601}"
    @report.say "installation #{GlobalConfig.get_value('INSTALLATION_NAME').inspect}, Rails env #{Rails.env}"
    @report.say 'This task performs GETs only. It writes nothing to Meta, the database or Redis.'
  end

  def no_channel_report
    @report.heading('NO WHATSAPP CHANNEL FOUND')
    @report.say 'This server holds no Channel::Whatsapp record, so there is nothing to diagnose here.'
    @report.say 'Run this task on the server whose database owns the real WhatsApp inbox.'
    @report.to_s
  end

  # The section order is the order an operator should read them in: identity before credentials, credentials before
  # subscription, subscription before delivery, and only then the local pipeline and the traffic it produced.
  def diagnose(channel)
    config = channel.provider_config.to_h.with_indifferent_access
    @local.channel_section(channel, config)
    @meta.identity(channel, config)
    @local.auth(channel, config)
    @meta.auth(config)
    @meta.waba_subscription(channel, config)
    @webhook.run(channel, config, subscribed_fields: @meta.subscribed_fields)
    @pipeline.run(channel, config)
    @evidence.run(channel.inbox) if channel.inbox
  end

  def resolve_channels
    return Channel::Whatsapp.where(id: Inbox.where(id: @inbox_id).select(:channel_id)).to_a if @inbox_id

    Channel::Whatsapp.all.to_a
  end
end
