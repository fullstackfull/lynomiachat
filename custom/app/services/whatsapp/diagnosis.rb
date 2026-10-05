# frozen_string_literal: true

# Lynomia real WhatsApp diagnosis (docs/real-whatsapp-uat/08-root-cause.md).
#
# The real WABA, phone number and access token live only on the deployed server, so the live half of P5's diagnosis
# has to run there. This orchestrates that diagnosis as one read-only report: `LocalChecks` answers what the
# installation's own configuration says (Parts A, P, R, S), `InboundEvidence` what its database says about traffic
# and the 24-hour window (Parts E, N), `MetaChecks` what Meta says (Parts B, C, D), and `Report` collects the
# lines, the pass/fail/blocked verdicts and the masking rules.
#
# Hard rules, enforced by construction:
#   * every Meta call is a GET through the installation's existing Whatsapp::FacebookApiClient
#   * nothing is written to Meta and nothing is written to the database
#   * every token, secret and customer phone number is masked, in one place
#   * the service never writes to stdout; the caller is handed each line and decides what to do with it
class Whatsapp::Diagnosis
  def initialize(inbox_id: nil, contact_identifier: nil, &emit)
    @inbox_id = inbox_id.presence
    @report = Whatsapp::Diagnosis::Report.new(&emit)
    @local = Whatsapp::Diagnosis::LocalChecks.new(@report)
    @evidence = Whatsapp::Diagnosis::InboundEvidence.new(@report, contact_identifier: contact_identifier.presence)
    @meta = Whatsapp::Diagnosis::MetaChecks.new(@report)
  end

  # @return [String] the whole report, also emitted line by line to the block given to the constructor.
  def run
    preamble
    channels = resolve_channels
    return no_channel_report if channels.empty?

    @local.installation_config
    @local.worker
    channels.each { |channel| diagnose(channel) }
    @report.summarise
    @report.to_s
  end

  private

  def preamble
    @report.heading('LYNOMIA REAL WHATSAPP DIAGNOSIS — READ ONLY')
    @report.say "generated at #{Time.current.iso8601}"
    @report.say "installation #{GlobalConfig.get_value('INSTALLATION_NAME').inspect}, Rails env #{Rails.env}"
  end

  def no_channel_report
    @report.heading('NO WHATSAPP CHANNEL FOUND')
    @report.say 'This server holds no Channel::Whatsapp record, so there is nothing to diagnose here.'
    @report.say 'Run this task on the server whose database owns the real WhatsApp inbox.'
    @report.to_s
  end

  def diagnose(channel)
    config = channel.provider_config.to_h.with_indifferent_access
    @local.identity(channel, config)
    @evidence.run(channel.inbox) if channel.inbox
    @meta.run(channel, config)
  end

  def resolve_channels
    return Channel::Whatsapp.where(id: Inbox.where(id: @inbox_id).select(:channel_id)).to_a if @inbox_id

    Channel::Whatsapp.all.to_a
  end
end
