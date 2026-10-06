# Lynomia real WhatsApp diagnosis (docs/real-whatsapp-uat/). A STRICTLY READ-ONLY report an operator runs on the
# server that owns the real WABA, because that is the only place the real credentials live.
#
#   bundle exec rails whatsapp:diagnose
#   bundle exec rails whatsapp:diagnose INBOX_ID=12
#   bundle exec rails whatsapp:diagnose INBOX_ID=12 CONTACT=+9655xxxxxxx
#
# It performs only GET requests, through the installation's existing Whatsapp::FacebookApiClient, and never writes
# to Meta or to the database. Every secret is masked. Nothing here subscribes, registers, rotates or deletes.
namespace :whatsapp do
  desc 'Read-only diagnosis of the real WhatsApp inbound/outbound path (no mutations, secrets masked)'
  task diagnose: :environment do
    # The service builds the report and hands back each line; printing is the task's job, so the report streams
    # while the Meta reads are still in flight.
    Whatsapp::Diagnosis.new(
      inbox_id: ENV.fetch('INBOX_ID', nil),
      contact_identifier: ENV.fetch('CONTACT', nil)
    ) { |line| puts line }.run
  end
end
