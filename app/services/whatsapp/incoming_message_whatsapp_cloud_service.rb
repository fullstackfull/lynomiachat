# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/

class Whatsapp::IncomingMessageWhatsappCloudService < Whatsapp::IncomingMessageBaseService
  private

  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
  end

  # Meta's OAuth error family. `Instagram::BaseSendService`, `Instagram::MessageText` and
  # `Messages::Instagram::MessageBuilder` all gate `authorization_error!` on code 190 rather than on the HTTP
  # status, and WhatsApp's media path is brought into line with them here.
  OAUTH_ERROR_TYPE = 'OAuthException'.freeze

  def download_attachment_file(attachment_payload)
    url_response = HTTParty.get(
      inbox.channel.media_url(attachment_payload[:id]),
      headers: inbox.channel.api_headers
    )

    count_authorization_error(url_response) if url_response.unauthorized?

    return unless url_response.success?

    downloaded_file = Down.download(url_response.parsed_response['url'], headers: inbox.channel.api_headers)
    # WhatsApp Cloud sends the original filename in the payload; preserve it so accented
    # names keep their correct extension instead of relying on the mangled remote metadata.
    filename = attachment_payload[:filename]
    downloaded_file.define_singleton_method(:original_filename) { filename } if filename.present?
    downloaded_file
  end

  # A 401 on a media read does not by itself mean the channel's token is dead. Media ids are scoped to the app
  # that received them and expire, so Meta answers 401 for a media id this app may no longer read as well as for a
  # bad token. Counting both latched the channel on a per-resource failure, and two of them tripped
  # AUTHORIZATION_ERROR_THRESHOLD and raised a disconnect alarm for a token that was fine.
  #
  # Only Meta's own OAuth verdict counts. A 401 whose body cannot be read still counts, so an unparseable
  # response keeps the previous, safer behaviour rather than silently ignoring a real expiry.
  def count_authorization_error(response)
    return inbox.channel.authorization_error! if oauth_error?(response)

    Rails.logger.warn(
      "[WHATSAPP INGEST] event=media_unauthorized channel_id=#{inbox.channel.id} inbox_id=#{inbox.id} " \
      'detail=401 that Meta does not attribute to OAuth; not counted against the reauthorization threshold'
    )
  end

  def oauth_error?(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    return true if error.blank?

    error['type'] == OAUTH_ERROR_TYPE || error['code'].to_i == 190
  rescue StandardError
    true
  end
end
