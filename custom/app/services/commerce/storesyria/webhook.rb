# Receiving Store Syria commerce event deliveries.
#
# THE STORE IS NAMED, NOT NUMBERED. Every other provider's delivery URL carries Lynomia's own
# `commerce_stores.id`, because Lynomia put that URL into the store when it registered the
# webhook. Store Syria registers nothing -- registers_webhooks? is false -- and has no way to
# learn Lynomia's row id, so a delivery names the store by the external id Store Syria itself
# issues and Lynomia stores: `{installation}:{store}`, which is globally unique here by the
# index on (provider, external_store_id).
#
# THE SIGNING KEY IS DERIVED FROM THE COMMERCE CREDENTIAL, which both sides already hold --
# Store Syria can recompute it, Lynomia keeps it to read the store's orders with. Deriving
# rather than exchanging a second secret means there is nothing extra to distribute and nothing
# extra to rotate: revoking the credential changes the key, so deliveries signed with the old
# one stop verifying the instant reads do, through the same act.
#
# The signature covers the timestamp as well as the body, so a captured delivery cannot be
# replayed with a fresher one; the window bounds how long it stays replayable at all, and
# Commerce::WebhookQueue's delivery-id dedup makes a replay inside the window a no-op anyway.
module Commerce::Storesyria::Webhook
  PURPOSE = 'storesyria-commerce-events'.freeze
  TOLERANCE = 5.minutes

  def self.store_for(external_store_id)
    return if external_store_id.blank?

    Commerce::Store.where.not(status: :disconnected).find_by(provider: 'storesyria', external_store_id: external_store_id.to_s)
  end

  def self.authentic?(store, raw_body, signature, timestamp)
    token = store&.credentials&.dig('commerce_token')
    return false unless token.is_a?(String) && token.present? && signature.is_a?(String) && fresh?(timestamp)

    key = OpenSSL::HMAC.hexdigest('SHA256', token, PURPOSE)
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', key, "#{timestamp}.#{raw_body}")}"
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def self.enqueue(store, delivery_id, raw_body)
    Commerce::WebhookQueue.enqueue('storesyria', "#{store.id}::#{Digest::SHA256.hexdigest(delivery_id.presence || raw_body)}",
                                   Commerce::Storesyria::WebhookJob, store.id, body: raw_body)
  end

  # A timestamp outside the window is refused rather than tolerated: without it the signature
  # is valid forever and a captured delivery is replayable forever.
  def self.fresh?(timestamp)
    seconds = Integer(timestamp.to_s, 10, exception: false)
    seconds.present? && (Time.now.to_i - seconds).abs <= TOLERANCE.to_i
  end
  private_class_method :fresh?
end
