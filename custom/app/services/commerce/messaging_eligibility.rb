# The one place that decides whether an automated commerce message may reach a shopper.
#
# ONE PLACE, DELIBERATELY. Every automated outbound path in Commerce passes through here --
# the template action a Commerce trigger fires, and the recovery message an agent prepares --
# so there is exactly one definition of "may we send this", and a new path is eligible only by
# calling it. Repeating the rule at each site is how two sites end up disagreeing, and the one
# that disagrees quietly is the one that messages somebody who said stop.
#
# TRANSACTIONAL AND PROMOTIONAL ARE DIFFERENT QUESTIONS WITH OPPOSITE DEFAULTS.
#
#   transactional  allowed unless refused. The shopper placed the order; being told it shipped
#                  is the service they asked for, and withholding it for want of a marketing
#                  opt-in is a worse outcome for them than receiving it.
#   promotional    refused unless granted. An abandoned basket is not a transaction the shopper
#                  completed and not a message they asked for. No grant, no send -- and the
#                  absence of a row is not a grant.
#
# WHAT BLOCKS EVERYTHING, WHATEVER THE CLASS:
#   - the contact is blocked in Lynomia (the existing gate, kept and checked first)
#   - the shopper withdrew consent for that class (`withdrawn`)
#   - the class is suppressed for them (`suppressed`): the provider says the number cannot
#     receive, so sending is not a decision anyone gets to make
#
# NOTHING HERE DECIDES WHETHER A CHANNEL WINDOW IS OPEN, whether a template is approved, or
# whether a rule is configured. Those are separate refusals with their own reasons, checked by
# the callers that own them; this answers consent and nothing else.
module Commerce::MessagingEligibility
  # The purpose of each Commerce trigger. Order events are about an order the shopper placed;
  # a cart is about one they did not, which is why the cart trigger is the promotional one.
  PURPOSES = Commerce::OrderTransitions::EVENTS.index_with { :transactional }
                                               .merge(Automation::CommerceEvents::CART_EVENTS.index_with { :promotional })
                                               .freeze

  # @return [Symbol, nil] the class a trigger's messages belong to, or nil when it is not a
  #   commerce trigger at all.
  def self.purpose_for(event_name)
    name = event_name.to_s
    return PURPOSES[name] if PURPOSES.key?(name)
    # A COMMERCE trigger this map does not know is promotional. The conservative default is the
    # only safe one: a trigger added later without a classification must not be able to reach
    # people who never opted in just because nobody updated a hash.
    return :promotional if Automation::CommerceEvents.event?(name)

    # Not a commerce trigger. There is no commerce class to apply here, and inventing one would
    # silence ordinary service automation -- a reply to a conversation the customer themselves
    # just started is not marketing, and demanding a marketing opt-in for it would be a worse
    # outcome for them than receiving it. A withdrawal or a suppression still blocks it.
    nil
  end

  # @return [Symbol, nil] nil when the send may proceed, else a short refusal reason.
  def self.refusal(contact, purpose)
    return :contact_unavailable if contact.nil? || contact.blocked?
    # No commerce class: only a decision somebody actually made can block, and either kind
    # blocks everything. There is nothing to grant here, so nothing is required.
    return blocking_refusal(contact) if purpose.nil?

    decision = Commerce::MessagingConsent.find_by(contact_id: contact.id, purpose: purpose)
    return state_refusal(decision) if decision&.blocking?

    grant_refusal(decision, purpose)
  end

  def self.allows?(contact, purpose) = refusal(contact, purpose).nil?

  # Promotional needs a grant that is really there. Transactional needs only the absence of a
  # refusal, which is what not finding a blocking row above already established.
  def self.grant_refusal(decision, purpose)
    return nil unless purpose.to_sym == :promotional

    :promotional_consent_missing unless decision&.consent_granted?
  end

  def self.blocking_refusal(contact)
    decision = Commerce::MessagingConsent.where(contact_id: contact.id).find(&:blocking?)

    decision && state_refusal(decision)
  end

  def self.state_refusal(decision) = decision.consent_suppressed? ? :messaging_suppressed : :consent_withdrawn
  private_class_method :state_refusal, :blocking_refusal, :grant_refusal
end
