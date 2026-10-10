# Lynomia: the dashboard never receives the mailbox passwords, so a settings save that leaves the field blank
# keeps the stored one (docs/p10/07-security-performance.md §secrets).
#
# `imap_password` and `smtp_password` are `encrypts`ed at rest when encryption is configured
# (app/models/channel/email.rb:45-48) -- the code already treats them as secrets -- and yet
# `_inbox.json.jbuilder` sent both to any administrator in plaintext, where they sat in the browser's memory,
# in devtools and in anything that could read the response. They are now reported as
# `imap_password_configured` / `smtp_password_configured` booleans instead.
#
# That alone would have been a regression: `ImapSettings.vue` pre-filled its field from the payload and sent it
# back on every save, so an empty field would have wiped the password. Blank now means "keep", which is the same
# contract the Super Admin app-config pages already use for their secrets, and the same shape
# `Channel::Whatsapp#with_stored_credentials` uses for its provider_config keys.
module Custom::Channel::Email
  SECRET_ATTRS = %i[imap_password smtp_password].freeze

  # @param channel_params [Hash] the permitted channel params from the request.
  # @return [Hash] the same params, with any blank secret replaced by what is already stored.
  def with_stored_credentials(channel_params)
    SECRET_ATTRS.each_with_object(channel_params.dup) do |attribute, params|
      key = [attribute, attribute.to_s].find { |candidate| params.key?(candidate) }
      next if key.nil? || params[key].present?

      params[key] = self[attribute]
    end
  end
end
