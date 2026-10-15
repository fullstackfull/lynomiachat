require 'rails_helper'

# FOUR THINGS LOOK A TEMPLATE UP IN THE SAME COLUMN, AND TWO OF THEM DECIDE CONSENT.
#
#   Whatsapp::TemplateProcessorService#find_template   the send -- name, language, APPROVED
#   Whatsapp::AuthenticationTemplateGuard#template     the BSUID guard -- name, language
#   Campaigns::RenderedTemplateText#template           the recorded text -- name, language, APPROVED
#   Campaigns::Eligibility.purpose_for                 the message CLASS -- name, language
#
# The two in `custom/` are now one lookup. The two upstream are OSS and are left alone, so
# the drift this file prevents is real rather than hypothetical: four independent spellings
# of "which template is this" is how the class a message was sent under and the text
# recorded for it come to disagree about which row they read.
RSpec.describe Whatsapp::ChannelTemplates do
  let(:account) { create(:account) }
  let(:templates) do
    [{ 'name' => 'order_shipped', 'language' => 'en_US', 'status' => 'approved', 'category' => 'UTILITY',
       'components' => [{ 'type' => 'BODY', 'text' => 'On its way.' }] },
     { 'name' => 'autumn_sale', 'language' => 'en_US', 'status' => 'approved', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Sale!' }] },
     { 'name' => 'pending_one', 'language' => 'en_US', 'status' => 'pending', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Soon.' }] },
     { 'name' => 'verify_code', 'language' => 'en_US', 'status' => 'approved', 'category' => 'AUTHENTICATION',
       'components' => [{ 'type' => 'BODY', 'text' => 'Your code.' }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: templates)
  end

  def params(name, language = 'en_US')
    { 'name' => name, 'language' => language }
  end

  # The guard returns at its first line for anything that is not a WhatsApp business id, so
  # every example that wants its lookup to run has to pass one.
  def guard_for(name)
    Whatsapp::AuthenticationTemplateGuard.new(channel: channel, recipient: 'SY.ENT.AB12CD34',
                                              template_params: params(name))
  end

  describe '.find' do
    it 'matches on the name and the language' do
      expect(described_class.find(channel, params('autumn_sale'))&.fetch('category')).to eq('MARKETING')
    end

    it 'matches the language case-insensitively, as every caller does' do
      expect(described_class.find(channel, params('order_shipped', 'EN_us'))).to be_present
    end

    it 'finds nothing for a name the channel does not hold' do
      expect(described_class.find(channel, params('never_synced'))).to be_nil
    end

    it 'finds an unapproved template unless approval is asked for' do
      expect(described_class.find(channel, params('pending_one'))).to be_present
      expect(described_class.find(channel, params('pending_one'), approved: true)).to be_nil
    end

    # A campaign with no template params, an SMS channel, and a campaign with no inbox are
    # all ordinary and none of them may raise: the class falls back to promotional, which is
    # the conservative answer.
    it 'answers nil rather than raising for a channel that has no template list' do
      expect(described_class.find(create(:channel_sms, account: account), params('order_shipped'))).to be_nil
    end

    it 'answers nil for a nil channel or nil params' do
      expect(described_class.find(nil, params('order_shipped'))).to be_nil
      expect(described_class.find(channel, nil)).to be_nil
    end
  end

  # THE AGREEMENT THAT MATTERS. Each of the four is asked for the same template and must
  # select the same row -- the two that require approval on the approved one, and all four
  # on the question they share.
  describe 'agreement with the three other lookups' do
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off,
                        template_params: params('autumn_sale').merge('processed_params' => { 'body' => {} }))
    end

    it 'selects the same template as the send path' do
      name, = Whatsapp::TemplateProcessorService.new(channel: channel,
                                                     template_params: campaign.template_params).call

      expect(name).to eq(described_class.find(channel, campaign.template_params, approved: true)['name'])
    end

    # THE GUARD ONLY LOOKS WHEN THE RECIPIENT IS A BUSINESS ID. Asked with a phone number it
    # returns at its first line, so an example that passes one asserts nothing about which
    # row the guard reads -- which is exactly what this example did until an audit of the
    # closure caught it. Three verdicts, each of which is the guard's own lookup speaking:
    # it errors on the row it found being AUTHENTICATION, is silent on the row it found
    # being MARKETING, and reports a missing category when it found no row at all.
    it 'selects the same template as the authentication guard' do
      expect(guard_for('verify_code').error).to be_present
      expect(guard_for('autumn_sale').error).to be_nil
      expect(guard_for('never_synced').error)
        .to eq(I18n.t('errors.whatsapp.template_category_required_for_bsuid'))

      expect(described_class.find(channel, params('verify_code'))['category']).to eq('AUTHENTICATION')
      expect(described_class.find(channel, params('autumn_sale'))['category']).to eq('MARKETING')
      expect(described_class.find(channel, params('never_synced'))).to be_nil
    end

    # NOT AN INDEPENDENT AGREEMENT, AND NOT OFFERED AS ONE: the class and the recorded text
    # are the two lookups this module replaced, so they now call it rather than each other.
    # What this pins is that both still route through it instead of growing a private copy
    # again, and that the single row they get carries both the class and the text.
    it 'gives the class and the recorded text the same row' do
      rendered = Campaigns::RenderedTemplateText.new(channel: channel, template_params: campaign.template_params)

      expect(Campaigns::Eligibility.purpose_for(campaign)).to eq(:promotional)
      expect(rendered.approved?).to be(true)
      expect(rendered.text).to eq('Sale!')
    end

    # And they disagree in the one way they are meant to: the send refuses an unapproved
    # template, while the class still reads it as marketing.
    it 'keeps the one difference that is deliberate' do
      campaign.update!(template_params: params('pending_one').merge('processed_params' => { 'body' => {} }))
      name, = Whatsapp::TemplateProcessorService.new(channel: channel,
                                                     template_params: campaign.template_params).call

      expect(name).to be_nil
      expect(Campaigns::Eligibility.purpose_for(campaign)).to eq(:promotional)
    end
  end
end
