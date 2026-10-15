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
    # The provider's own classification, not the account's configuration. Meta approves a
    # UTILITY template for messages about something the customer is already part of, which is
    # the transactional class; it requires opt-in for MARKETING, which is the promotional one.
    {
      'UTILITY' => :transactional, 'utility' => :transactional,
      'MARKETING' => :promotional, 'AUTHENTICATION' => :promotional, '' => :promotional
    }.each do |category, purpose|
      it "reads #{category.presence || 'a missing category'} as #{purpose}" do
        campaign = build(:campaign, account: account, template_params: { 'category' => category })

        expect(described_class.purpose_for(campaign)).to eq(purpose)
      end
    end

    # An SMS blast carries no provider classification, so there is nothing authoritative to
    # read and the conservative answer is the only safe one.
    it 'treats a campaign with no template params at all as promotional' do
      expect(described_class.purpose_for(build(:campaign, account: account, template_params: nil)))
        .to eq(:promotional)
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

  describe '.excluded_counts' do
    it "says why the audience shrank, in the policy's own reason codes" do
      expect(described_class.excluded_counts(relation, account, :transactional))
        .to eq(contact_unavailable: 1, consent_withdrawn: 1, messaging_suppressed: 1)
    end

    it 'counts the marketing-only refusal and the missing grants on a promotional send' do
      expect(described_class.excluded_counts(relation, account, :promotional))
        .to eq(contact_unavailable: 1, consent_withdrawn: 2, messaging_suppressed: 1,
               promotional_consent_missing: 1)
    end
  end

  # The filter has to hold at the entry point every sender, the preview and the snapshot share,
  # not only when called directly -- that is the whole reason it was put there.
  describe 'through Campaign#audience_contacts' do
    let(:inbox) { create(:inbox, account: account) }
    let(:campaign) do
      create(:campaign, account: account, inbox: inbox, campaign_type: :one_off,
                        template_params: { 'category' => 'UTILITY' },
                        audience: [{ 'type' => 'Label', 'id' => label.id }])
    end

    before { everyone.each { |contact| contact.update!(label_list: ['vip']) } }

    it 'returns only the contacts a UTILITY campaign may actually message' do
      expect(campaign.audience_contacts).to contain_exactly(clean, no_marketing)
    end

    it 'returns nobody for a MARKETING campaign where no one has granted consent' do
      campaign.update!(template_params: { 'category' => 'MARKETING' })

      expect(campaign.audience_contacts).to be_empty
    end

    it 'still reports everyone the audience selected, so the shortfall is explainable' do
      expect(campaign.selected_contacts { campaign.account.contacts.where(id: everyone.map(&:id)) })
        .to match_array(everyone)
    end
  end
end
