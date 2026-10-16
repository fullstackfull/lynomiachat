# WHAT THE PERSON AGREED TO, ASKED ON THE ONE OUTBOUND PATH THAT NEVER ASKED.
#
# `Whatsapp::SendOnWhatsappService#send_template_message` is the chokepoint for every
# message-borne WhatsApp template: the agent composer, the Compose-new-conversation form, the
# automation template action, the flow Send-template node and the contact-info request. Two of
# those already refuse an ineligible recipient before they ever build a message
# (Custom::AutomationRules::TemplateAction, Flows::Nodes::SendTemplate). The two composer
# paths did not, and nothing between `messages_controller#create` and `channel.send_template`
# looked -- so an agent could pick an approved MARKETING template and send it to a shopper who
# had replied STOP, in an open conversation or in a brand new one.
#
# It is not a hypothetical pairing. The picker offers marketing: `isSendableTemplate` excludes
# AUTHENTICATION and CSAT and nothing else. And because a template send deliberately skips the
# 24-hour window (`perform_reply` returns before `can_reply?`), the usual thing that would have
# stopped an unsolicited message does not apply here either.
#
# WHY HERE AND NOT IN THE BUILDER. `Messages::MessageBuilder` looks like the shared entry
# point and is not: `Flows::Run#say` calls `conversation.messages.create!` directly and would
# route straight around a gate placed there. This service is what every template send actually
# reaches.
#
# THE CLASS IS META'S, AS IT IS EVERYWHERE ELSE IN THIS SYSTEM. UTILITY is transactional and
# anything else is promotional. A composer send has no commerce trigger to read, so the
# template is the whole of the answer -- the same rule, and the same lookup, as the flow node.
#
# HOW STRICT, AND WHY IT DEPENDS ON THE ACCOUNT.
#
#   commerce accounts      a promotional template needs a grant. This is what the flow node
#                          and the automation action already enforce, so the composer being
#                          the one surface that did not was an inconsistency, not a policy.
#   every other account    only a decision somebody actually made can stop a send: a STOP
#                          reply or a provider suppression. `Commerce::MessagingEligibility`
#                          refuses a promotional send unless a grant EXISTS, and an account
#                          that never turned the consent subsystem on has no merchant-facing
#                          way to record one -- so asking that question there would refuse
#                          every marketing template in the product, which is breaking a
#                          working feature rather than closing a hole.
#
# The compliance-critical case is closed in BOTH: `Commerce::ConsentListener` is registered
# unconditionally, so a shopper typing STOP writes a `withdrawn` row in any account at all,
# and a withdrawal blocks either way.
module Custom::Whatsapp::SendOnWhatsappService
  def send_template_message
    refusal = platform_refusal || consent_refusal
    return message.update!(status: :failed, external_error: I18n.t("errors.whatsapp.consent.#{refusal}")) if refusal

    super
  end

  private

  # WHAT THE INSTALLATION'S OWN WORKSPACE MAY SEND (P6E).
  #
  # Store Syria's platform workspace exists to tell merchants about their accounts --
  # onboarding, a broken integration, a security notice. The owner authorised essential
  # operational communication and explicitly did NOT authorise promotional campaigns, feature
  # marketing, cross-selling or bulk announcements.
  #
  # ENFORCED ON META'S OWN CLASSIFICATION, not on anything the sender declares. `UTILITY` is
  # what Meta calls a message about an existing relationship, it is read off the channel's
  # synced template list, and it is the same constant every other outbound surface here
  # already uses. An operator cannot relabel a MARKETING template as operational, because
  # nothing they can type is consulted -- the category comes from the provider.
  #
  # WHY IT IS A SEPARATE GATE FROM CONSENT, and must run first. `consent_purpose` falls back
  # to nil for a promotional template in an account without the commerce feature, and the
  # platform workspace has no commerce store, so consent alone would let a MARKETING template
  # through to anybody who had not explicitly refused. That is the opposite of what the
  # authorisation says.
  #
  # AND IT IS METERED HERE. P6D requires the platform plan to set `campaign_sends` precisely
  # so platform sending is counted, but that meter lives on the campaign path and this is the
  # conversation path, which would otherwise bypass it entirely -- an unmetered, unrecorded
  # channel out of a workspace whose whole point was that its sending is bounded.
  def platform_refusal
    return nil unless conversation.account.platform_owned?
    return :platform_promotional_refused unless template_category == 'UTILITY'

    Billing::MeteredUsage.consume(conversation.account) ? :platform_allowance_exhausted : nil
  end

  def consent_refusal
    Commerce::MessagingEligibility.refusal(contact, consent_purpose)
  end

  # nil asks "did anybody decide against this", which is the question for an account with no
  # consent surface. A symbol asks the full question for that class.
  def consent_purpose
    return :transactional if Campaigns::Eligibility::TRANSACTIONAL_CATEGORIES.include?(template_category)

    conversation.account.feature_enabled?('lynomia_commerce') ? :promotional : nil
  end

  # `approved: false`: an unapproved marketing template is still marketing, and upstream will
  # refuse it a moment later for its own reasons. The shared lookup, not a fifth spelling of
  # it -- Whatsapp::ChannelTemplates names the four that already exist.
  def template_category
    template = Whatsapp::ChannelTemplates.find(channel, template_params)

    template&.fetch('category', nil).to_s.upcase
  end
end
