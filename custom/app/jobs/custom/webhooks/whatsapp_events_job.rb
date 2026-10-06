# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md §4): routes
# `message_template_status_update` through the webhook receiver that already exists.
#
# The branch has to run before the parent's channel resolution, which reads only
# `entry[0].changes[0].value.metadata.phone_number_id` and treats "no channel" as "inactive channel" -- a WABA-scoped
# template payload carries no metadata and no phone number at all, so today it is logged as an inactive channel and
# dropped. The tenant here is `entry[].id`, the WABA id, which is the scope a template record is keyed on anyway.
#
# Every change of every entry is applied, not just `changes[0]`: Meta can batch several template status updates in one
# delivery. A delivery that also carries non-template changes still reaches the parent, so a message is never dropped
# in order to handle a template event.
module Custom::Webhooks::WhatsappEventsJob
  TEMPLATE_STATUS_FIELD = 'message_template_status_update'.freeze

  def perform(params = {})
    template_changes = template_status_changes(params)
    return super if template_changes.empty?

    template_changes.each { |waba_id, value| ::Whatsapp::Templates::StatusUpdate.new(waba_id, value).perform }

    super if other_changes?(params)
  end

  private

  # [[waba_id, value], ...]
  def template_status_changes(params)
    return [] unless params[:object] == 'whatsapp_business_account'

    Array(params[:entry]).flat_map do |entry|
      Array(entry[:changes]).filter_map do |change|
        [entry[:id].to_s, change[:value]] if change[:field] == TEMPLATE_STATUS_FIELD
      end
    end
  end

  def other_changes?(params)
    Array(params[:entry]).any? do |entry|
      Array(entry[:changes]).any? { |change| change[:field] != TEMPLATE_STATUS_FIELD }
    end
  end
end
