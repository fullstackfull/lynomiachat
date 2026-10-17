require 'rails_helper'

# The Stripe webhook's contribution to the accounting export (custom/app/services/billing/webhook_handler.rb).
#
# THE BRIEF'S HARD RULE: "Do not make synchronous Odoo API calls inside Stripe webhook handlers." Stripe
# expects an answer in milliseconds and retries anything that is not a 2xx, so an endpoint that waited on the
# owner's Odoo would turn one slow accounting server into a storm of redeliveries.
RSpec.describe Billing::WebhookHandler do
  include_context 'with commerce encryption'

  let!(:profile) { create(:odoo_destination_profile, :enabled, environment: 'test') }
  let(:account) { create(:account) }

  before do
    # The destination the handler finds is the enabled one for this Rails environment.
    allow(Odoo::DestinationProfile).to receive(:active).and_return(profile)
    account.create_billing_subscription!(stripe_customer_id: 'cus_test1', status: 'active', source: 'manual')
  end

  def stripe_event(type, object)
    Stripe::Event.construct_from(id: "evt_#{SecureRandom.hex(4)}", type: type, created: Time.current.to_i,
                                 data: { object: object })
  end

  # Nothing in the request may reach Odoo. Proven by making every Odoo transport blow up if touched.
  def refusing_odoo
    allow(Odoo::Transport::Json2).to receive(:new).and_raise('a webhook must not talk to Odoo')
    allow(Odoo::Transport::JsonRpc).to receive(:new).and_raise('a webhook must not talk to Odoo')
    allow(Odoo::Http).to receive(:new).and_raise('a webhook must not open a connection')
  end

  describe 'invoice events' do
    it 'records the work and talks to nothing' do
      refusing_odoo
      event = stripe_event('invoice.paid', stripe_invoice)

      expect { described_class.new(event).perform }.to change(Odoo::SyncEvent, :count).by(1)

      row = Odoo::SyncEvent.last
      expect(row.provider_object_id).to eq('in_test1')
      expect(row.origin).to eq('webhook')
      expect(row).to be_state_pending
      expect(row.account_id).to eq(account.id)
    end

    it 'enqueues the worker rather than running it inline' do
      refusing_odoo
      event = stripe_event('invoice.paid', stripe_invoice)

      expect { described_class.new(event).perform }
        .to have_enqueued_job(Odoo::SyncJob).on_queue('low')
    end

    it 'records the receipt as processed, not ignored' do
      refusing_odoo
      described_class.new(stripe_event('invoice.paid', stripe_invoice)).perform

      expect(BillingWebhookEvent.last).to be_status_processed
    end

    # Stripe documents that it may deliver an event more than once of its own accord.
    it 'makes no second row for a redelivery of the same object' do
      refusing_odoo
      described_class.new(stripe_event('invoice.paid', stripe_invoice)).perform

      expect { described_class.new(stripe_event('invoice.finalized', stripe_invoice)).perform }
        .not_to change(Odoo::SyncEvent, :count)
    end

    it 'handles every invoice event type it declares' do
      refusing_odoo

      Odoo::EventRecorder::INVOICE_EVENTS.each_with_index do |type, index|
        invoice = stripe_invoice(id: "in_type#{index}")
        expect { described_class.new(stripe_event(type, invoice)).perform }
          .to change(Odoo::SyncEvent, :count).by(1)
      end
    end
  end

  describe 'refunds' do
    # ONE ROW PER REFUND: a charge.refunded notification carries every refund the charge has ever had, so a
    # customer refunded twice produces two rows -- and the second notification's first refund lands on the
    # dedup key the first notification already used.
    it 'records one row per refund on the charge' do
      refusing_odoo
      charge = stripe_charge(refunds: [stripe_refund(id: 'rf_1', amount: 5000).to_hash,
                                       stripe_refund(id: 'rf_2', amount: 2000).to_hash])

      expect { described_class.new(stripe_event('charge.refunded', charge)).perform }
        .to change(Odoo::SyncEvent, :count).by(2)

      expect(Odoo::SyncEvent.pluck(:provider_object_id)).to contain_exactly('rf_1', 'rf_2')
      expect(Odoo::SyncEvent.pluck(:provider_object_type)).to all(eq('refund'))
    end

    # THE SECOND REFUND USED TO BE RECORDED AND NEVER EXPORTED. The handler enqueued only `events.first`, so
    # row two sat `pending` with nothing scheduled to pick it up -- a customer refunded twice got one credit
    # note. Recording the work is not doing it; one job per row is.
    it 'enqueues a worker for EVERY refund, not just the first' do
      refusing_odoo
      charge = stripe_charge(refunds: [stripe_refund(id: 'rf_1', amount: 5000).to_hash,
                                       stripe_refund(id: 'rf_2', amount: 2000).to_hash])

      expect { described_class.new(stripe_event('charge.refunded', charge)).perform }
        .to have_enqueued_job(Odoo::SyncJob).twice

      queued = Odoo::SyncEvent.pluck(:id)
      queued.each { |id| expect(Odoo::SyncJob).to have_been_enqueued.with(id) }
    end
  end

  describe 'a dispute' do
    it 'records it for review and writes nothing to Odoo' do
      refusing_odoo
      dispute = Stripe::Dispute.construct_from(id: 'dp_1', object: 'dispute', charge: 'ch_test1',
                                               customer: 'cus_test1')

      described_class.new(stripe_event('charge.dispute.created', dispute)).perform

      expect(Odoo::SyncEvent.last.provider_object_type).to eq('dispute')
    end
  end

  describe 'what it leaves alone' do
    it 'does not touch the subscription path' do
      refusing_odoo
      subscription = Stripe::Subscription.construct_from(
        id: 'sub_1', object: 'subscription', status: 'active', customer: 'cus_test1',
        metadata: { account_id: account.id.to_s }, items: { object: 'list', data: [] },
        current_period_end: 30.days.from_now.to_i, cancel_at_period_end: false
      )

      expect { described_class.new(stripe_event('customer.subscription.updated', subscription)).perform }
        .not_to change(Odoo::SyncEvent, :count)
      expect(account.billing_subscription.reload.stripe_subscription_id).to eq('sub_1')
    end

    it 'still ignores an event type nobody handles' do
      refusing_odoo
      coupon = Stripe::Coupon.construct_from(id: 'co_1', object: 'coupon')

      described_class.new(stripe_event('coupon.created', coupon)).perform

      expect(BillingWebhookEvent.last).to be_status_ignored
      expect(Odoo::SyncEvent.count).to eq(0)
    end
  end

  describe 'with no Odoo destination configured' do
    # An installation that has not set Odoo up must keep taking Stripe webhooks exactly as it did before this
    # feature existed.
    it 'accepts the event, records nothing, and does not fail' do
      allow(Odoo::DestinationProfile).to receive(:active).and_return(nil)
      refusing_odoo

      expect { described_class.new(stripe_event('invoice.paid', stripe_invoice)).perform }
        .not_to change(Odoo::SyncEvent, :count)
      expect(BillingWebhookEvent.last).to be_status_ignored
    end
  end
end
