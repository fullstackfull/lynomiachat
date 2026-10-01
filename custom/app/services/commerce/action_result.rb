# What a provider answered to an order action, or what reading the store showed afterwards (reconciliation).
#
# status              succeeded | running (the store completes it asynchronously: a Shopify cancellation job) |
#                     failed (nothing changed in the store) | unknown (the answer was lost)
# provider_reference  the store's id of what it created (refund id, job id), or nil
# message_code        a Lynomia code for the agent (never the store's own error text)
Commerce::ActionResult = Data.define(:status, :provider_reference, :message_code) do
  def self.succeeded(reference = nil) = new(status: 'succeeded', provider_reference: reference&.to_s, message_code: nil)

  def self.running(reference) = new(status: 'running', provider_reference: reference.to_s, message_code: nil)

  def self.failed(code) = new(status: 'failed', provider_reference: nil, message_code: code)

  def self.unknown(code = 'UNKNOWN_OUTCOME') = new(status: 'unknown', provider_reference: nil, message_code: code)
end
