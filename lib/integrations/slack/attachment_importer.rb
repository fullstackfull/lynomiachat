# Attaches the files a Slack event carries to a Lynomia message.
#
# Extracted from Integrations::Slack::SlackMessageHelper when the credential guard below was added
# (docs/p11/00-p10-security-closure.md, SEC-9): `url_private` comes from the request body, and the download
# sends the account's Slack OAuth token to it in an Authorization header. A URL pointing anywhere else is that
# token handed to whoever chose it, so it now travels only to a Slack-owned host. A Slack private file cannot
# be fetched without the token, so a URL that fails the check is skipped rather than fetched unauthenticated.
#
# Same shape as the guard on the SMS media path (Sms::IncomingMessageService#provider_hosted?): decide by the
# URL's own scheme, userinfo and host, and never by what the payload claims about itself.
class Integrations::Slack::AttachmentImporter
  IMAGE_TYPES = %w[png jpeg gif bmp tiff jpg].freeze
  VIDEO_TYPES = %w[mp4 avi mov wmv flv webm].freeze

  def initialize(message:, access_token:)
    @message = message
    @access_token = access_token
  end

  def import(attachments)
    Array(attachments).each { |attachment| attach(attachment) }
  end

  private

  def attach(attachment)
    url = attachment[:url_private]
    return unless slack_hosted?(url)

    tempfile = Down::NetHttp.download(url, headers: { 'Authorization' => "Bearer #{@access_token}" })
    object = @message.attachments.new(
      file_type: file_type(attachment),
      account_id: @message.account_id,
      external_url: url,
      file: { io: tempfile, filename: tempfile.original_filename, content_type: tempfile.content_type }
    )
    object.file.content_type = attachment[:mimetype]
  end

  def slack_hosted?(url)
    uri = URI.parse(url.to_s)
    return false unless uri.scheme == 'https' && uri.userinfo.nil?

    host = uri.host.to_s.downcase
    host == 'slack.com' || host.end_with?('.slack.com')
  rescue URI::InvalidURIError
    false
  end

  def file_type(attachment)
    return if attachment[:mimetype] == 'text/plain'

    case attachment[:filetype]
    when *IMAGE_TYPES then :image
    when *VIDEO_TYPES then :video
    else :file
    end
  end
end
