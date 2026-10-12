# `payload` and `meta.total_count` are the two keys fetchDeliveries reads
# (app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:278-279).
json.payload do
  json.array! @recipients do |recipient|
    # `contact.id` is the row key and the link target, so it has to be on every row that is returned
    # (app/javascript/dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue:89).
    json.contact do
      json.id recipient.contact_id
      json.name recipient.contact&.name
      json.phone_number recipient.contact&.phone_number
    end
    # A short lower-case token. The badge renders one it does not know verbatim rather than hiding the row.
    json.status recipient.status
    # The text this one contact was sent. Null renders as "message not generated".
    json.message_content recipient.message_content
    # Read in the order message -> title -> code, so any one of the three is a usable reason.
    json.error_code recipient.error_code
    json.error_title recipient.error_title
    json.error_message recipient.error_message
  end
end

json.meta do
  # After the status filter, because it drives the pager for the list actually being shown.
  json.total_count @recipients.total_count
end
