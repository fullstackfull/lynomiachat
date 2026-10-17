require 'rails_helper'

# THE CASE THIS FEED EXISTS FOR: a shopper replies STOP on WhatsApp. The decision is made on
# Lynomia's channel, about a person the merchant knows as their own customer, and the merchant
# finds out only if somebody tells them. Without it, Store Syria's consent screen shows a
# cheerful "subscribed" for somebody who opted out days ago.
RSpec.describe Consents::ChangeFeed do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1') }
  let(:other_store) { create(:commerce_store, account: account, provider: 'salla', external_store_id: 'sa-2') }
  let(:shopper) { create(:contact, account: account, name: 'Shopper') }
  let!(:webhook) do
    create(:webhook, account: account, url: 'https://store.example/lynomia/events/7',
                     webhook_type: :account_type, subscriptions: [described_class::EVENT])
  end

  before do
    create(:commerce_customer_link, account: account, store: store, contact: shopper,
                                    external_customer_id: 'cust-77')
  end

  def stop!
    Commerce::MessagingConsents.record(
      account: account, contact: shopper,
      decision: Commerce::MessagingConsents::Decision.new(state: :withdrawn, source: 'shopper_keyword')
    )
  end

  def enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == WebhookJob }

  # ActiveJob stamps `_aj_symbol_keys` into every serialised hash to remember which keys were
  # symbols. It is transport bookkeeping, not part of the payload a receiver sees, so it is
  # stripped here rather than asserted around.
  def clean(value)
    case value
    when Hash  then value.except('_aj_symbol_keys', :_aj_symbol_keys).transform_values { |v| clean(v) }.symbolize_keys
    when Array then value.map { |v| clean(v) }
    else value
    end
  end

  def payloads = enqueued.map { |job| clean(job[:args][1]) }

  # The receiver refuses a correctly signed delivery whose account is not the one that store
  # is linked to, so the account has to travel or nothing is accepted.
  it 'names the workspace, which the receiver checks before it accepts anything' do
    stop!

    expect(payloads).to all(include(account: { id: account.id }))
  end

  it 'tells the store when a shopper opts out on a Lynomia channel' do
    stop!

    expect(payloads).to include(
      hash_including(event: 'consent_changed', origin: 'lynomia_native', state: 'withdrawn',
                     store: { provider: 'storesyria', external_store_id: 'sy-1' },
                     subject: { external_customer_id: 'cust-77' })
    )
  end

  # A partner cannot act on a Lynomia contact id, so the payload names the customer id that
  # store already uses.
  it 'addresses the customer in the partner\'s own terms, never with a Lynomia id' do
    stop!

    body = payloads.first
    expect(body[:subject][:external_customer_id]).to eq('cust-77')
    expect(body.to_s).not_to include(shopper.id.to_s)
    expect(body.keys).not_to include(:contact_id, :email, :phone_number)
  end

  it 'sends one delivery per installation that knows the person, and none that do not' do
    create(:commerce_customer_link, account: account, store: other_store, contact: shopper,
                                    external_customer_id: 'salla-9')
    create(:commerce_store, account: account, provider: 'zid', external_store_id: 'zid-3')

    stop!

    # A keyword STOP changes BOTH classes at once, so each installation is told twice -- once
    # per decision. What is asserted is which stores heard about it, and that the third,
    # which has no link to this person, heard nothing.
    stores = payloads.map { |body| body[:store][:external_store_id] }
    expect(stores.uniq).to contain_exactly('sy-1', 'sa-2')
    expect(payloads.map { |body| body[:purpose] }.uniq).to contain_exactly('transactional', 'promotional')
  end

  # A paused integration may not AUTHORISE a send, but it must still be told somebody opted
  # out -- that is the fact it needs when it resumes.
  it 'still tells a disabled installation, but not a disconnected one' do
    store.update!(status: :disabled)
    stop!
    expect(payloads.map { |body| body[:store][:external_store_id] }.uniq).to eq(['sy-1'])

    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    store.update!(status: :disconnected)
    Commerce::MessagingConsents.record(
      account: account, contact: shopper,
      decision: Commerce::MessagingConsents::Decision.new(state: :suppressed, source: 'operator')
    )
    expect(payloads).to be_empty
  end

  # THE DEPARTURE FROM deliver_account_webhooks, and the reason for it. That method mints a
  # random uuid per enqueue, which is harmless for a conversation event and not harmless for
  # a consent change: a reconciliation sweep or a republish would arrive as a NEW delivery and
  # be processed again. A derived id makes every repeat a no-op at the receiver.
  describe 'delivery identity' do
    it 'derives the delivery id from the decision, so a republish is a no-op downstream' do
      stop!
      first = enqueued.map { |job| job[:args].last[:delivery_id] || job[:args].last['delivery_id'] }

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      described_class.publish_native(Commerce::MessagingConsent.find_by(contact_id: shopper.id,
                                                                        purpose: :promotional))
      repeat = enqueued.map { |job| job[:args].last[:delivery_id] || job[:args].last['delivery_id'] }

      expect(repeat).to eq(first & repeat)
      expect(repeat).to all(match(/\Aconsent-native-\d+-\d+-\d+\z/))
    end

    it 'gives a later decision a different id, so a real change is not swallowed' do
      stop!
      withdrawn = enqueued.map { |job| job[:args].last.symbolize_keys[:delivery_id] }
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      travel_to(1.hour.from_now) do
        Commerce::MessagingConsents.record(
          account: account, contact: shopper,
          decision: Commerce::MessagingConsents::Decision.new(state: :suppressed, source: 'operator')
        )
      end

      expect(enqueued.map { |job| job[:args].last.symbolize_keys[:delivery_id] }).not_to eq(withdrawn)
    end
  end

  # A DIFFERENT DELIVERY ID IS NOT ENOUGH, and the two examples above could not tell the
  # difference. The receiver accepts the delivery and THEN compares revisions, keeping the
  # highest it has seen and dropping anything at or below it -- which is what stops a delayed
  # delivery reinstating a decision a later one replaced. So a revision that does not rise
  # makes every decision after the first a no-op at the far end, with the delivery arriving
  # and being discarded.
  #
  # It did not rise. The feed published the consent row's id, and the native row is updated
  # in place -- one row per (contact, purpose) for the life of the scope -- so the id was the
  # one number in it that never changes.
  describe 'revision' do
    it 'rises with every decision, so a receiver keeping the highest does not drop the later ones' do
      stop!
      first = payloads.map { |body| body[:revision] }.uniq
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      Commerce::MessagingConsents.record(
        account: account, contact: shopper,
        decision: Commerce::MessagingConsents::Decision.new(state: :granted, source: 'merchant')
      )
      second = payloads.map { |body| body[:revision] }.uniq

      expect(first).to all(be_positive)
      expect(second.min).to be > first.max
    end

    # Reconciliation has to report the SAME number the feed publishes, or a sweep could not
    # repair a scope the feed had got stuck -- it would feed the stale value back through the
    # same comparison.
    #
    # PER ROW, because one STOP writes both purposes and they no longer share a number. The
    # revision is drawn from the table's own sequence rather than counted on the row, so
    # that `clear_suppression` destroying a row cannot restart it at 1; two rows written in
    # the same breath therefore take two consecutive numbers. Collapsing the payloads with
    # `uniq` and comparing against one row passed only while the two happened to agree.
    it 'is the number the reconciliation endpoint reports for the same row' do
      stop!
      rows = Commerce::MessagingConsent.where(contact_id: shopper.id)

      published = payloads.to_h { |body| [body[:purpose], body[:revision]] }

      expect(published).to eq(rows.to_h { |row| [row.purpose, row.revision] })
    end
  end

  describe 'partner decisions' do
    it 'echoes back what Lynomia actually applied, in that installation\'s scope' do
      PartnerConsent.create!(platform_app: create(:platform_app), account: account, commerce_store: store,
                             contact: shopper, external_subject_id: 'cust-77', purpose: :promotional,
                             channel: :whatsapp, state: :granted, source: 'checkout_optin',
                             captured_at: Time.current, revision: 42).then { |row| described_class.publish_partner(row) }

      expect(payloads).to include(
        hash_including(origin: 'partner', state: 'granted', channel: 'whatsapp',
                       store: { provider: 'storesyria', external_store_id: 'sy-1' })
      )
    end
  end

  it 'sends nothing to a webhook that did not subscribe' do
    webhook.update!(subscriptions: ['message_created'])

    stop!

    expect(enqueued).to be_empty
  end
end
