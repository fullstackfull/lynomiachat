# Meta's refusal is stored verbatim in `content_attributes.external_error` and always has been. What it *means* --
# and whether re-sending the same message to the same person could possibly help -- is decided once, here on the
# server (Whatsapp::DeliveryFailure), so the dashboard never carries a second copy of that policy and the two cannot
# drift apart.
#
# It is derived on read rather than written at failure time, which is the point: the 131049 refusals this
# classification exists for are already in the database, and a field written only on new failures would leave every
# one of them unexplained.
module Custom::Message
  # Only codes Lynomia has actually observed are classified, and Meta's are six digits beginning 13. No other
  # provider in this installation writes an `external_error` that opens with one of them, so a failure from any
  # other channel falls through to nil and the dashboard behaves exactly as it did before.
  def delivery_failure_data
    return unless failed?

    Whatsapp::DeliveryFailure.for(self).push_event_data
  end

  def push_event_data
    data = super
    failure = delivery_failure_data
    data[:delivery_failure] = failure if failure
    data
  end
end
