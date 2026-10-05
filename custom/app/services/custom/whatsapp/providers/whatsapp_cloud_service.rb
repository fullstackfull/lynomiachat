# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md): the sync keeps writing
# the channel's message_templates snapshot exactly as before -- same full replace, same update_columns, so every
# existing consumer and the audit-log suppression are untouched -- and then projects it into
# Whatsapp::MessageTemplate rows. The projection reads only what was just written, so this adds no network call.
#
# 360dialog needs no equivalent: Whatsapp::Templates::Query reconciles from whatever snapshot is on disk before every
# read, so its channels get rows without touching its provider.
module Custom::Whatsapp::Providers::WhatsappCloudService
  def sync_templates
    super

    ::Whatsapp::Templates::Mirror.new(whatsapp_channel).perform
  end
end
