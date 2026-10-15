require 'rails_helper'

# THE DEFECT THESE EXAMPLES PIN.
#
# No campaign sender checked anything. `Campaign#audience_contacts` was
# `account.contacts.tagged_with(...)` and nothing else, so a contact who had replied STOP, a
# contact an agent had blocked, and a contact the provider had reported as unable to receive
# were all addressed exactly like anyone else -- while Commerce::MessagingEligibility, sitting
# right there, would have refused all three.
RSpec.describe Campaigns::Eligibility do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:label) { create(:label, account: account, title: 'vip') }
  let(:relation) { account.contacts.where(id: everyone.map(&:id)) }

  let(:clean) { create(:contact, account: account, name: 'Clean') }
  let(:blocked) { create(:contact, account: account, name: 'Blocked', blocked: true) }
  let(:withdrawn) { create(:contact, account: account, name: 'Withdrawn') }
  let(:suppressed) { create(:contact, account: account, name: 'Suppressed') }
  let(:everyone) { [clean, blocked, withdrawn, suppressed] }

  def decide(contact, purpose, state)
    Commerce::MessagingConsent.create!(account: account, contact: contact, purpose: purpose, state: state,
                                       source: 'merchant', decided_at: Time.current)
  end

  before do
    decide(withdrawn, :promotional, :withdrawn)
    decide(suppressed, :promotional, :suppressed)
  end

  describe '.filter' do
    # The refusal half is unconditional: honouring "this person said stop" must never depend on
    # a feature flag, so it runs for every account whether or not it operates Commerce.
    it 'excludes a blocked, a withdrawn and a suppressed contact even without Commerce' do
      expect(account.feature_enabled?('lynomia_commerce')).to be(false)

      expect(described_class.filter(relation, account)).to contain_exactly(clean)
    end

    # The grant half is conditional, and this is why: an account with no Commerce has no
    # consent rows and no way to collect any, so requiring a grant would silently reduce every
    # campaign to zero recipients against data that cannot exist.
    it 'does not require a grant from an account that does not run Commerce' do
      expect(described_class.filter(relation, account)).to include(clean)
    end

    context 'when the account runs Commerce' do
      before { account.enable_features!('lynomia_commerce') }

      it 'refuses a contact with no promotional grant, because a campaign is promotional' do
        expect(described_class.filter(relation, account)).to be_empty
      end

      it 'reaches a contact who granted promotional consent' do
        decide(clean, :promotional, :granted)

        expect(described_class.filter(relation, account)).to contain_exactly(clean)
      end

      # A transactional grant is consent to hear about an order they placed. It is not consent
      # to be marketed at, and treating it as one is the mistake the two-class model exists to
      # prevent.
      it 'does not accept a transactional grant as permission to send a campaign' do
        decide(clean, :transactional, :granted)

        expect(described_class.filter(relation, account)).to be_empty
      end

      # Suppression is the provider saying the number cannot receive. A later grant is a
      # decision nobody gets to make on the provider's behalf.
      it 'keeps refusing a suppressed contact who also granted consent' do
        decide(suppressed, :transactional, :granted)

        expect(described_class.filter(relation, account)).not_to include(suppressed)
      end
    end
  end

  # THE CROSS-CHECK THAT MAKES TWO READINGS ONE RULE.
  #
  # The filter is SQL because its callers do `.each`, `.count` and `.seed` on the result and a
  # marketing audience is not a page. Commerce::MessagingEligibility keeps the per-contact
  # decision. Two expressions of one rule are a drift hazard, so this asserts they agree
  # contact for contact rather than trusting that they do.
  describe 'agreement with Commerce::MessagingEligibility' do
    %w[without with].each do |commerce|
      it "matches the per-contact decision exactly, #{commerce} Commerce" do
        account.enable_features!('lynomia_commerce') if commerce == 'with'
        decide(clean, :promotional, :granted) if commerce == 'with'

        reachable = described_class.filter(relation, account).to_a
        purpose = described_class.grant_required?(account) ? described_class::PURPOSE : nil
        allowed = everyone.select { |contact| Commerce::MessagingEligibility.allows?(contact, purpose) }

        expect(reachable).to match_array(allowed)
      end
    end
  end

  describe '.excluded_counts' do
    it 'says why the audience shrank, in the same reason codes the policy returns' do
      expect(described_class.excluded_counts(relation, account))
        .to eq(contact_unavailable: 1, consent_withdrawn: 1, messaging_suppressed: 1)
    end

    it 'adds the missing-grant count only where a grant is required' do
      account.enable_features!('lynomia_commerce')

      expect(described_class.excluded_counts(relation, account))
        .to eq(contact_unavailable: 1, consent_withdrawn: 1, messaging_suppressed: 1,
               promotional_consent_missing: 1)
    end
  end

  # The filter has to hold at the entry point every sender, the preview and the snapshot share,
  # not only when called directly -- that is the whole reason it was put there.
  describe 'through Campaign#audience_contacts' do
    let(:inbox) { create(:inbox, account: account) }
    let(:campaign) do
      create(:campaign, account: account, inbox: inbox, campaign_type: :one_off,
                        audience: [{ 'type' => 'Label', 'id' => label.id }])
    end

    before { everyone.each { |contact| contact.update!(label_list: ['vip']) } }

    it 'returns only the contacts the campaign may actually message' do
      expect(campaign.audience_contacts).to contain_exactly(clean)
    end

    it 'still reports everyone the audience selected, so the shortfall is explainable' do
      expect(campaign.selected_contacts { campaign.account.contacts.where(id: everyone.map(&:id)) })
        .to match_array(everyone)
    end
  end
end
