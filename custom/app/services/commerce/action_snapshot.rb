# An order read from the store just now, for an action (docs/commerce/29-provider-action-capabilities.md).
#
# order         Commerce::Order
# version       opaque digest of the order's material state (status, payment, totals, refunds): an action confirmed
#               against one version is never sent once the store reports another
# capabilities  { action_type => { available: true, ... } | { available: false, reason: } } for every action the provider
#               implements, judged from the store's API and the order's state only; Lynomia's switches, the store's
#               opt-in and the agent's permissions are applied on top (Commerce::OrderActions)
# facts         what the provider needs to perform an action on this order (payment gateway, refundable transactions);
#               kept in memory, never stored or sent to the browser
Commerce::ActionSnapshot = Data.define(:order, :version, :capabilities, :facts)
