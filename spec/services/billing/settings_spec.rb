require 'rails_helper'

RSpec.describe Billing::Settings do
  # Nothing caches these: a stale commercial setting would charge or lock the wrong account
  # (docs/p11/07-security-performance.md §6).
  it 'sees a change immediately' do
    described_class.update!(trial_days: 21)
    expect(described_class.trial_days).to eq(21)

    described_class.update!(trial_days: 30)
    expect(described_class.trial_days).to eq(30)
  end

  it 'falls back to the declared default when nothing is stored' do
    expect(described_class.get(:trial_days)).to eq(described_class::KEYS[:trial_days][:default])
    expect(described_class.get(:stripe_secret_key)).to be_nil
  end

  it 'keeps a stored secret when the form submits an empty field' do
    described_class.update!(stripe_secret_key: 'sk_test_original')
    described_class.update!(stripe_secret_key: '')

    expect(described_class.stripe_secret_key).to eq('sk_test_original')
  end

  it 'reports a secret as set and masked, never in full' do
    described_class.update!(stripe_secret_key: 'sk_test_51abcdefghijklmnop9876')

    hint = described_class.masked(:stripe_secret_key)
    expect(hint).to eq('sk_test...9876')
    expect(hint).not_to include('abcdefghijklmnop')
  end

  describe 'enforcement' do
    it 'is off with no Stripe keys and no trial plan' do
      expect(described_class.enforced?).to be(false)
    end

    it 'is on once Stripe is configured' do
      described_class.update!(stripe_secret_key: 'sk_test_fake', stripe_webhook_secret: 'whsec_fake')

      expect(described_class.stripe_configured?).to be(true)
      expect(described_class.enforced?).to be(true)
    end

    it 'is on once a trial plan is chosen, with no Stripe keys at all' do
      plan = create(:billing_plan)
      described_class.update!(trial_enabled: true, trial_days: 14, trial_plan_id: plan.id)

      expect(described_class.stripe_configured?).to be(false)
      expect(described_class.enforced?).to be(true)
    end
  end
end
