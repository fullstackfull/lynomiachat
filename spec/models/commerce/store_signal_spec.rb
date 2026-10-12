require 'rails_helper'

# A store losing its authorization is an operational problem a human has to act on, recorded as one
# (docs/product-refinement/09-commerce-operations.md §incidents).
#
# Recorded from the model rather than from the six services that flip the status, so there is one place every
# transition passes through. These examples exercise the real services, not the callback directly.
RSpec.describe Commerce::Store, type: :model do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, account: account) }

  def reauth_signal
    Operations::Signal.open_signals.find_by(source: 'commerce_store', signal: 'reauthorization_required',
                                            subject_type: 'Commerce::Store', subject_id: store.id)
  end

  it 'opens a critical incident when the merchant authorization is gone' do
    Commerce::StoreConnection.new(account: account, user: nil).credentials_rejected(store)

    expect(reauth_signal).to be_present
    expect(reauth_signal.severity).to eq('critical')
    expect(reauth_signal.account_id).to eq(account.id)
    expect(reauth_signal.detail['provider']).to eq('woocommerce')
  end

  it 'resolves it when the store is working again' do
    Commerce::StoreConnection.new(account: account, user: nil).credentials_rejected(store)
    store.update!(status: :active)

    expect(reauth_signal).to be_nil
  end

  # A merchant who disconnected their store did exactly what the product offers them. There is no incident to
  # leave behind.
  it 'resolves it when the store is disconnected rather than leaving an incident open' do
    Commerce::StoreConnection.new(account: account, user: nil).credentials_rejected(store)
    store.update!(status: :disconnected)

    expect(reauth_signal).to be_nil
  end

  it 'records nothing when a status change does not touch the authorization' do
    expect { Commerce::StoreConnection.new(account: account, user: nil).disable(store) }
      .not_to(change { Operations::Signal.where(source: 'commerce_store').count })
  end

  it 'records nothing when something other than the status changes' do
    expect { store.update!(name: 'Renamed') }.not_to change(Operations::Signal, :count)
  end
end
