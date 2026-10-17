# frozen_string_literal: true

# WHICH TEMPLATE A CAMPAIGN NAMES, IN THE CHANNEL'S OWN SYNCED LIST.
#
# `channel.message_templates` is the snapshot Meta's sync writes, and four things look a
# template up in it by the same two fields:
#
#   Whatsapp::TemplateProcessorService#find_template   the send -- name, language, APPROVED
#   Whatsapp::AuthenticationTemplateGuard#template     the BSUID guard -- name, language
#   Campaigns::RenderedTemplateText#template           the recorded text -- name, language, APPROVED
#   Campaigns::Eligibility.purpose_for                 the message CLASS -- name, language
#
# Two of them now decide consent: the class decides whether a promotional grant is required
# at all, and the recorded text is what an operator reads afterwards. Four independent
# spellings of one lookup is how the campaign's class and the campaign's message come to
# disagree about which template was sent.
#
# THE TWO IN `custom/` ARE THIS ONE. The two upstream are left alone -- they are OSS and
# this is not Enterprise-only behaviour to override -- and
# spec/services/whatsapp/channel_templates_spec.rb asserts all four select the same row for
# the same inputs, which is what actually prevents the drift.
#
# `approved:` is the one real difference between them. The send requires Meta's approval,
# because an unapproved template cannot go; the class does not, because an unapproved
# MARKETING template is still marketing and reading it as transactional for want of an
# approval is exactly the wrong direction.
module Whatsapp::ChannelTemplates
  APPROVED = 'approved'

  module_function

  # @param channel [Channel::Whatsapp, Object] anything carrying `message_templates`
  # @param template_params [Hash, nil] the campaign's own, of which only name and language are read
  # @return [Hash, nil]
  def find(channel, template_params, approved: false)
    params = template_params.is_a?(Hash) ? template_params : {}
    return nil unless channel.respond_to?(:message_templates)

    Array(channel.message_templates).find do |remote|
      remote['name'] == params['name'].to_s &&
        remote['language'].to_s.casecmp?(params['language'].to_s) &&
        (!approved || remote['status'].to_s.casecmp?(APPROVED))
    end
  end
end
