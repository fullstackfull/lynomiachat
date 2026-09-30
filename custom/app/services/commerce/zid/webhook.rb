# Receiving Zid webhook deliveries (docs/commerce/15-zid-webhook-security.md). This is HTTP Basic Authentication, not a
# signature: each store has its own random username and password (Commerce::Zid::Webhooks), stored encrypted, and Zid
# sends them with every delivery. Both are compared in constant time, and nothing in a body is read before they match.
#
# An authenticated delivery is queued once through Commerce::WebhookQueue: an identical body for the same store within
# its DEDUP_TTL is a redelivery and is acknowledged without being queued again.
module Commerce::Zid::Webhook
  def self.authorized?(store, username, password)
    expected_username, expected_password = store&.credentials&.values_at('webhook_username', 'webhook_password')
    return false unless [expected_username, expected_password, username, password].all?(String)

    ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &
      ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
  end

  def self.enqueue(store, raw_body)
    Commerce::WebhookQueue.enqueue('zid', "#{store.id}::#{Digest::SHA256.hexdigest(raw_body)}", Commerce::Zid::WebhookJob, store.id,
                                   body: raw_body)
  end
end
