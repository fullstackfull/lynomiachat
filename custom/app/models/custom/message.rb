# Meta's refusal is stored verbatim in `content_attributes.external_error` and always has been. What it *means* --
# and whether re-sending the same message to the same person could possibly help -- is decided once, here on the
# server (Whatsapp::DeliveryFailure), so the dashboard never carries a second copy of that policy and the two cannot
# drift apart.
#
# It is derived on read rather than written at failure time, which is the point: the 131049 refusals this
# classification exists for are already in the database, and a field written only on new failures would leave every
# one of them unexplained.
module Custom::Message
  # THE ONE PLACE EVERY OUTCOME WRITER PASSES THROUGH.
  #
  # A partner that sends through this installation is told what became of its message
  # (Delivery::StatusFeed). The hook is here, on the model, rather than on
  # Messages::StatusUpdateService -- which looks like the chokepoint and is not. The provider's
  # own failure write (Whatsapp::Providers::BaseService) and every eligibility gate
  # (Custom::Whatsapp::SendOnWhatsappService) call `message.update!` directly and would walk
  # straight past a hook placed on that service.
  def self.prepended(base)
    base.after_update_commit :publish_delivery_status, if: :delivery_outcome_changed?
  end

  # TWO COLUMNS, BECAUSE A SUCCESSFUL SUBMISSION DOES NOT TOUCH THE FIRST ONE.
  #
  #   status     the obvious one: delivered, read, and the failures -- a provider's and the
  #              eligibility gates' alike.
  #   source_id  the provider's own id for the message, and the ONLY evidence it accepted it.
  #              `Whatsapp::SendOnWhatsappService` writes it with `update!(source_id:)` and
  #              does not touch `status`, which stays at the `sent` the column defaulted to on
  #              INSERT. So on status alone the provider accepting a message is invisible, and
  #              a partner's first news of it would be a delivery receipt that may be hours
  #              away or never come -- which leaves the notice reading as merely accepted, the
  #              exact ambiguity this feed exists to remove.
  #
  # NOT a general update hook: a content edit, an attachment or a label changes neither column
  # and publishes nothing. This is an outcome feed, not an edit feed.
  def delivery_outcome_changed?
    saved_change_to_status? || saved_change_to_source_id?
  end

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

  private

  def publish_delivery_status
    Delivery::StatusFeed.publish(self)
  end
end
