require 'rails_helper'

# THE DEFECT THESE EXAMPLES PIN.
#
# No campaign sender checked anything. `Campaign#audience_contacts` was
# `account.contacts.tagged_with(...)` and nothing else, so a contact who had replied STOP, a
# contact an agent had blocked, and a contact the provider had reported as unable to receive
# were all addressed exactly like anyone else -- while Commerce::MessagingEligibility, sitting
# right there, would have refused all three.
#
# DECISIONS ARE WRITTEN THROUGH Commerce::MessagingConsents.record, the real writer, rather
# than by hand. It defaults to BOTH classes, which is what the keyword listener and any
# suppression actually produce ("one keyword message changes both classes at once, because
# that is what the person meant"). Hand-built single-class rows would test a state the system
# does not create, and an earlier draft of this file did exactly that -- which is how it came
# to assert that a promotional withdrawal blocks a transactional send. It does not, and it
# should not.
RSpec.describe Campaigns::Eligibility do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:label) { create(:label, account: account, title: 'vip') }
  let(:relation) { account.contacts.where(id: everyone.map(&:id)) }

  let(:clean) { create(:contact, account: account, name: 'Clean') }
  let(:blocked) { create(:contact, account: account, name: 'Blocked', blocked: true) }
  let(:stopped) { create(:contact, account: account, name: 'Stopped') }
  let(:suppressed) { create(:contact, account: account, name: 'Suppressed') }
  let(:no_marketing) { create(:contact, account: account, name: 'NoMarketing') }
  let(:everyone) { [clean, blocked, stopped, suppressed, no_marketing] }

  def record(contact, state, purposes: nil, source: 'shopper_keyword')
    decision = if purposes
                 Commerce::MessagingConsents::Decision.new(state: state, source: source, purposes: purposes)
               else
                 Commerce::MessagingConsents::Decision.new(state: state, source: source)
               end
    Commerce::MessagingConsents.record(account: account, contact: contact, decision: decision)
  end

  before do
    record(stopped, :withdrawn)                                               # a real STOP: both classes
    record(suppressed, :suppressed)                                           # the provider refused the number
    record(no_marketing, :withdrawn, purposes: ['promotional'], source: 'merchant')
  end

  describe '.purpose_for' do
    # THE CLASSIFICATION IS THE PROVIDER'S, AND IT IS READ FROM THE CHANNEL'S SYNCED LIST.
    # Meta approves a UTILITY template for messages about something the customer is already
    # part of, which is the transactional class, and requires opt-in for MARKETING, which is
    # the promotional one. The fixture is therefore a channel that actually holds the
    # templates, named by the campaign the way the dashboard names them.
    let(:templates) do
      [{ 'name' => 'order_shipped', 'language' => 'en_US', 'status' => 'approved', 'category' => 'UTILITY' },
       { 'name' => 'autumn_sale', 'language' => 'en_US', 'status' => 'approved', 'category' => 'MARKETING' },
       { 'name' => 'login_code', 'language' => 'en_US', 'status' => 'approved', 'category' => 'AUTHENTICATION' }]
    end
    let(:whatsapp_inbox) do
      create(:inbox, account: account,
                     channel: create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                        sync_templates: false, validate_provider_config: false,
                                                        message_templates: templates))
    end

    # Four call sites with one field differing each time, which is the case the guideline
    # against setup helpers makes an exception for.
    def campaign_claiming(params)
      build(:campaign, account: account, inbox: whatsapp_inbox, template_params: params)
    end

    { 'order_shipped' => :transactional, 'autumn_sale' => :promotional, 'login_code' => :promotional }
      .each do |name, purpose|
      it "reads #{name} as #{purpose}, from the category the provider gave it" do
        campaign = campaign_claiming('name' => name, 'language' => 'en_US')

        expect(described_class.purpose_for(campaign)).to eq(purpose)
      end
    end

    it 'matches the template language case-insensitively, as the sender does' do
      campaign = campaign_claiming('name' => 'order_shipped', 'language' => 'EN_us')

      expect(described_class.purpose_for(campaign)).to eq(:transactional)
    end

    # THE DEFECT THIS PAIR PINS, and it is a consent bypass rather than a classification nit.
    #
    # `category` is a field of the campaign's own JSON body -- the dashboard's WhatsApp form
    # sends `category: currentTemplate?.category || 'UTILITY'` -- and this used to read it.
    # A campaign created with a MARKETING template and `"category": "UTILITY"` was therefore
    # transactional on the creator's say-so, required no promotional grant, and went to every
    # contact in the audience who had never agreed to marketing.
    it 'ignores a UTILITY claim in the request when the provider calls the template MARKETING' do
      campaign = campaign_claiming('name' => 'autumn_sale', 'language' => 'en_US', 'category' => 'UTILITY')

      expect(described_class.purpose_for(campaign)).to eq(:promotional)
    end

    it 'ignores a UTILITY claim for a template the channel has never heard of' do
      campaign = campaign_claiming('name' => 'not_a_real_template', 'language' => 'en_US', 'category' => 'UTILITY')

      expect(described_class.purpose_for(campaign)).to eq(:promotional)
    end

    # An SMS blast carries no provider classification, so there is nothing authoritative to
    # read and the conservative answer is the only safe one. Same for a campaign with no
    # inbox at all, which is how the audience preview may be asked.
    it 'treats a campaign with no template params at all as promotional' do
      expect(described_class.purpose_for(build(:campaign, account: account, template_params: nil)))
        .to eq(:promotional)
    end

    it 'treats a campaign on a channel with no template list as promotional' do
      campaign = build(:campaign, account: account, inbox: create(:inbox, account: account),
                                  template_params: { 'name' => 'order_shipped', 'category' => 'UTILITY' })

      expect(described_class.purpose_for(campaign)).to eq(:promotional)
    end
  end

  describe '.filter' do
    # A real opt-out and a provider suppression stop everything, whatever the class.
    %i[transactional promotional].each do |purpose|
      it "excludes a blocked contact, a STOP and a suppression from a #{purpose} send" do
        expect(described_class.filter(relation, account, purpose)).not_to include(blocked, stopped, suppressed)
      end
    end

    it 'reaches an unrefused contact for a transactional send without needing a grant' do
      expect(described_class.filter(relation, account, :transactional)).to include(clean)
    end

    # THE ASYMMETRY THE TWO-CLASS MODEL EXISTS FOR. Opting out of marketing must not silence a
    # parcel notification. This contact refused promotional only, through the merchant surface.
    it 'still sends a transactional message to someone who refused marketing only' do
      expect(described_class.filter(relation, account, :transactional)).to include(no_marketing)
      expect(described_class.filter(relation, account, :promotional)).not_to include(no_marketing)
    end

    # THE CORRECTION. An earlier version required a grant only where the account ran Commerce,
    # which read the absence of a consent record as permission to market. It is required
    # everywhere now, because absence of a record is not consent.
    it 'refuses a promotional send with no grant, whether or not the account runs Commerce' do
      expect(account.feature_enabled?('lynomia_commerce')).to be(false)
      expect(described_class.filter(relation, account, :promotional)).to be_empty

      account.enable_features!('lynomia_commerce')
      expect(described_class.filter(relation, account, :promotional)).to be_empty
    end

    it 'reaches a contact who granted promotional consent' do
      record(clean, :granted, purposes: ['promotional'], source: 'merchant')

      expect(described_class.filter(relation, account, :promotional)).to contain_exactly(clean)
    end

    # A transactional grant is consent to hear about an order they placed. It is not consent to
    # be marketed at, and treating it as one is the mistake the two-class model exists to stop.
    it 'does not accept a transactional grant as permission to market' do
      record(clean, :granted, purposes: ['transactional'], source: 'merchant')

      expect(described_class.filter(relation, account, :promotional)).to be_empty
    end

    # Suppression is the provider saying the number cannot receive. A later grant is a decision
    # nobody gets to make on the provider's behalf.
    it 'keeps refusing a suppressed contact who later granted consent' do
      record(suppressed, :granted, purposes: ['promotional'], source: 'merchant')

      expect(described_class.filter(relation, account, :transactional)).not_to include(suppressed)
    end
  end

  # THE CROSS-CHECK THAT MAKES TWO READINGS ONE RULE.
  #
  # The filter is SQL because its callers do `.each`, `.count` and `.seed` and a marketing
  # audience is not a page. Commerce::MessagingEligibility keeps the per-contact decision. Two
  # expressions of one rule are a drift hazard, so this asserts they agree contact for contact
  # rather than trusting that they do -- and it has already earned its place: it caught a draft
  # whose SQL blocked on a refusal of any class while the policy looks one up per class.
  describe 'agreement with Commerce::MessagingEligibility' do
    %i[transactional promotional].each do |purpose|
      it "matches the per-contact decision exactly for a #{purpose} send" do
        record(clean, :granted, purposes: ['promotional'], source: 'merchant')

        reachable = described_class.filter(relation, account, purpose).to_a
        allowed = everyone.select { |contact| Commerce::MessagingEligibility.allows?(contact, purpose) }

        expect(reachable).to match_array(allowed)
      end
    end
  end

  # The filter has to hold at the entry point every sender, the preview and the snapshot share,
  # not only when called directly -- that is the whole reason it was put there.
  describe 'through Campaign#audience_contacts' do
    # A REAL CHANNEL WITH REAL TEMPLATES, because the campaign's class is now read from the
    # list Meta's sync writes rather than from the campaign's own body. A fixture that only
    # claimed `category` would have described a campaign the provider would classify as
    # marketing, which is the shape the claim used to be able to hide.
    let(:inbox) do
      create(:inbox, account: account,
                     channel: create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                        sync_templates: false, validate_provider_config: false,
                                                        message_templates: [
                                                          { 'name' => 'order_shipped', 'language' => 'en_US',
                                                            'status' => 'approved', 'category' => 'UTILITY' },
                                                          { 'name' => 'autumn_sale', 'language' => 'en_US',
                                                            'status' => 'approved', 'category' => 'MARKETING' }
                                                        ]))
    end
    let(:campaign) do
      create(:campaign, account: account, inbox: inbox, campaign_type: :one_off,
                        template_params: { 'name' => 'order_shipped', 'language' => 'en_US' },
                        audience: [{ 'type' => 'Label', 'id' => label.id }])
    end

    before { everyone.each { |contact| contact.update!(label_list: ['vip']) } }

    it 'returns only the contacts a UTILITY campaign may actually message' do
      expect(campaign.audience_contacts).to contain_exactly(clean, no_marketing)
    end

    it 'returns nobody for a MARKETING campaign where no one has granted consent' do
      campaign.update!(template_params: { 'name' => 'autumn_sale', 'language' => 'en_US' })

      expect(campaign.audience_contacts).to be_empty
    end

    # The same campaign, with the request claiming the transactional class: the audience is
    # the MARKETING one, so the bypass does not survive the entry point either.
    it 'returns nobody for a MARKETING campaign whose request claims UTILITY' do
      campaign.update!(template_params: { 'name' => 'autumn_sale', 'language' => 'en_US', 'category' => 'UTILITY' })

      expect(campaign.audience_contacts).to be_empty
    end

    it 'still reports everyone the audience selected, so the shortfall is explainable' do
      expect(campaign.selected_contacts { campaign.account.contacts.where(id: everyone.map(&:id)) })
        .to match_array(everyone)
    end
  end
end
