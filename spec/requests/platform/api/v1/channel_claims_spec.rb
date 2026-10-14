require 'rails_helper'

# ONE CHANNEL IDENTITY, ONE HOLDER.
#
# The rule belongs to an integration that connects merchants: "this WhatsApp number belongs to one
# of my stores and no other", including across two stores owned by the same person. Lynomia itself
# has never had that rule and must not acquire it globally -- an independent customer connecting
# their own number conflicts with nobody -- so every example here also has to show that an account
# no integration holds is untouched.
RSpec.describe 'Channel identity claims', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }

  let(:store_a) { create(:account) }
  let(:store_b) { create(:account) }

  before do
    create(:platform_app_permissible, platform_app: platform_app, permissible: store_a)
    create(:platform_app_permissible, platform_app: platform_app, permissible: store_b)
  end

  def claim(account, identity, provider: 'whatsapp', owner: nil, app_headers: headers)
    post '/platform/api/v1/channel_claims',
         params: { account_id: account.id, provider: provider, identity: identity, external_owner_ref: owner },
         headers: app_headers, as: :json
  end

  describe 'claiming' do
    it 'records a claim for an account the app holds' do
      claim(store_a, '+44 20 7946 0958', owner: 'store-7')

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('provider' => 'whatsapp', 'account_id' => store_a.id,
                                              'external_owner_ref' => 'store-7', 'state' => 'active')
    end

    # WITHOUT NORMALIZATION THE RULE IS A FORMATTING RULE. These are three spellings of one number,
    # and a registry that treated them as three identities would let three stores hold it.
    it 'treats every spelling of one phone number as the same identity' do
      claim(store_a, '+44 20 7946 0958')
      expect(response).to have_http_status(:created)

      ['442079460958', '00442079460958', '+44-20-7946-0958', '+44 (20) 7946 0958'].each do |spelling|
        claim(store_b, spelling)
        expect(response).to have_http_status(:conflict), "#{spelling} was treated as a different number"
      end
    end

    it 'treats an email mailbox case-insensitively' do
      claim(store_a, 'Sales@Example.COM', provider: 'email')
      claim(store_b, 'sales@example.com', provider: 'email')

      expect(response).to have_http_status(:conflict)
    end

    # Provider-issued ids are opaque. Lowercasing a case-sensitive token would merge two channels
    # that are genuinely different.
    it 'compares a provider-issued id exactly' do
      claim(store_a, 'PageABC', provider: 'facebook')
      claim(store_b, 'pageabc', provider: 'facebook')

      expect(response).to have_http_status(:created)
    end

    it 'refuses a second store, and names who holds it' do
      claim(store_a, '+15551234567', owner: 'store-7')
      claim(store_b, '+15551234567', owner: 'store-9')

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include('error_code' => 'channel_claimed_elsewhere', 'held_by' => 'store-7')
    end

    # THE RULE APPLIES WITHIN ONE MERCHANT TOO. Two stores owned by the same person are two stores.
    it 'refuses a second store even when both belong to one owner' do
      claim(store_a, '+15551234567', owner: 'merchant-1/store-a')
      claim(store_b, '+15551234567', owner: 'merchant-1/store-b')

      expect(response).to have_http_status(:conflict)
    end

    it 'is idempotent for the holder, so a retry after a lost answer succeeds' do
      claim(store_a, '+15551234567')
      first = response.parsed_body['id']

      claim(store_a, '+15551234567')

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['id']).to eq(first)
      expect(ChannelIdentityClaim.active.count).to eq(1)
    end

    it 'refuses an account the app does not hold' do
      stranger = create(:account)

      claim(stranger, '+15551234567')

      expect(response).to have_http_status(:unauthorized)
      expect(ChannelIdentityClaim.count).to be_zero
    end

    it 'refuses an unknown provider and a blank identity' do
      claim(store_a, '+15551234567', provider: 'carrier-pigeon')
      expect(response).to have_http_status(:unprocessable_entity)

      claim(store_a, '')
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an unauthenticated caller' do
      post '/platform/api/v1/channel_claims',
           params: { account_id: store_a.id, provider: 'whatsapp', identity: '+15551234567' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(ChannelIdentityClaim.count).to be_zero
    end

    # TWO INTEGRATIONS DO NOT BLOCK EACH OTHER. The rule is each integration's own.
    it 'does not let one integration block another' do
      other_app = create(:platform_app)
      other_account = create(:account)
      create(:platform_app_permissible, platform_app: other_app, permissible: other_account)

      claim(store_a, '+15551234567')
      post '/platform/api/v1/channel_claims',
           params: { account_id: other_account.id, provider: 'whatsapp', identity: '+15551234567' },
           headers: { api_access_token: other_app.access_token.token }, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe 'releasing' do
    it 'frees the identity for the next holder and keeps the history' do
      claim(store_a, '+15551234567')

      delete '/platform/api/v1/channel_claims',
             params: { provider: 'whatsapp', identity: '+1 555 123 4567' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['released']).to be(true)
      expect(ChannelIdentityClaim.active.count).to be_zero
      # Kept, so "who held this number in March" has an answer.
      expect(ChannelIdentityClaim.count).to eq(1)

      claim(store_b, '+15551234567')
      expect(response).to have_http_status(:created)
    end

    it 'is a no-op for something nobody holds' do
      delete '/platform/api/v1/channel_claims',
             params: { provider: 'whatsapp', identity: '+15550000000' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['released']).to be(false)
    end

    it 'cannot release another integration\'s claim' do
      other_app = create(:platform_app)
      claim(store_a, '+15551234567')

      delete '/platform/api/v1/channel_claims',
             params: { provider: 'whatsapp', identity: '+15551234567' },
             headers: { api_access_token: other_app.access_token.token }, as: :json

      expect(response.parsed_body['released']).to be(false)
      expect(ChannelIdentityClaim.active.count).to eq(1)
    end
  end

  describe 'listing' do
    it 'shows only this integration\'s claims, narrowable by holder' do
      claim(store_a, '+15551111111', owner: 'store-7')
      claim(store_b, '+15552222222', owner: 'store-9')

      get '/platform/api/v1/channel_claims', headers: headers, as: :json
      expect(response.parsed_body['claims'].length).to eq(2)

      get '/platform/api/v1/channel_claims', params: { external_owner_ref: 'store-7' }, headers: headers, as: :json
      expect(response.parsed_body['claims'].map { |c| c['identity'] }).to eq(['+15551111111'])
    end
  end

  # ================================================================ enforcement at the chokepoint

  describe 'what a claim actually prevents' do
    # Inbox creation has nine production call sites in this fork; only Inbox validation is
    # downstream of all of them, which is why the guard lives there and not on a controller.
    # THE CHANNEL ITSELF IS REFUSED, one layer earlier than the inbox. Custom::Channelable rides
    # the prepend_mod_with seam Channelable already has, so this applies to all twelve channel
    # models without editing any of them.
    it 'refuses the channel itself in another store' do
      claim(store_a, 'sales@example.com', provider: 'email')

      expect do
        Channel::Email.create!(account: store_b, email: 'sales@example.com',
                               forward_to_email: 'fwd-b@example.com')
      end.to raise_error(ActiveRecord::RecordInvalid, /already connected to another store/i)
    end

    # AND THE INBOX GUARD CATCHES IT INDEPENDENTLY, which is what covers the six inbox-creation
    # paths that never go near the inboxes controller. Here the channel predates the claim, so
    # the channel-side validation had nothing to refuse when it was written.
    it 'refuses an inbox whose channel was created before the claim existed' do
      channel = Channel::Email.create!(account: store_b, email: 'sales@example.com',
                                       forward_to_email: 'fwd-b@example.com')
      claim(store_a, 'sales@example.com', provider: 'email')

      inbox = store_b.inboxes.new(name: 'Sales', channel: channel)

      expect(inbox).not_to be_valid
      expect(inbox.errors.full_messages.join).to match(/already connected to another store/i)
    end

    # THE TWO-STEP EVASION. Connect an identity nobody claimed, then edit it to the one you
    # wanted. A create-only rule lets this through; EDITABLE_ATTRS makes it reachable through the
    # ordinary inboxes controller for WhatsApp, SMS and Email.
    it 'refuses an identity change onto a claimed one' do
      claim(store_a, 'sales@example.com', provider: 'email')
      channel = Channel::Email.create!(account: store_b, email: 'other@example.com',
                                       forward_to_email: 'fwd-b@example.com')

      channel.email = 'sales@example.com'

      expect(channel).not_to be_valid
      expect(channel.errors.full_messages.join).to match(/already connected to another store/i)
    end

    # An edit that does NOT touch the identity must not be refused because somebody else holds a
    # number this channel is not trying to take.
    it 'allows an unrelated edit while another store holds a different identity' do
      claim(store_a, 'sales@example.com', provider: 'email')
      channel = Channel::Email.create!(account: store_b, email: 'other@example.com',
                                       forward_to_email: 'fwd-b@example.com')

      channel.forward_to_email = 'changed@example.com'

      expect(channel).to be_valid
    end

    it 'allows the holder to create its own inbox for it' do
      claim(store_a, 'sales@example.com', provider: 'email')

      channel = Channel::Email.create!(account: store_a, email: 'sales@example.com',
                                       forward_to_email: 'fwd-a@example.com')
      inbox = store_a.inboxes.new(name: 'Sales', channel: channel)

      expect(inbox).to be_valid
    end

    # THE ACCOUNT NOBODY LINKED IS UNTOUCHED, which is every account that did not come from an
    # integration. Breaking this would be a regression for independent Lynomia customers.
    it 'does not constrain an account no integration holds' do
      claim(store_a, 'sales@example.com', provider: 'email')
      independent = create(:account)

      channel = Channel::Email.create!(account: independent, email: 'sales@example.com',
                                       forward_to_email: 'fwd-i@example.com')
      inbox = independent.inboxes.new(name: 'Sales', channel: channel)

      expect(inbox).to be_valid
    end

    it 'stops constraining once the claim is released' do
      claim(store_a, 'sales@example.com', provider: 'email')
      ChannelIdentityClaim.active.sole.release!

      channel = Channel::Email.create!(account: store_b, email: 'sales@example.com',
                                       forward_to_email: 'fwd-b@example.com')

      expect(store_b.inboxes.new(name: 'Sales', channel: channel)).to be_valid
    end
  end

  # ================================================================ concurrency, for real

  describe 'two claims racing' do
    # THE INDEX IS THE ARBITER, NOT THE CHECK. Both callers read "unclaimed" and both proceed; a
    # check-then-write loses this every time it is run often enough. Driven through real threads
    # against real Postgres rather than simulated, because a partial unique index either holds
    # under concurrency or it does not and nothing else can tell you which.
    it 'lets exactly one win' do
      identity = '+15559998888'
      results = []
      mutex = Mutex.new

      threads = [store_a, store_b].map do |account|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            outcome = begin
              Channels::Exclusivity.claim!(platform_app: platform_app, account: account,
                                           provider: 'whatsapp', identity: identity)
              :won
            rescue Channels::Exclusivity::Conflict
              :lost
            end
            mutex.synchronize { results << outcome }
          end
        end
      end
      threads.each(&:join)

      expect(results.count(:won)).to eq(1)
      expect(ChannelIdentityClaim.active.where(identity: identity).count).to eq(1)
    end

    it 'is enforced by the database even when the service is bypassed' do
      ChannelIdentityClaim.create!(platform_app: platform_app, account: store_a,
                                   provider: 'whatsapp', identity: '+15551234567')

      expect do
        ChannelIdentityClaim.create!(platform_app: platform_app, account: store_b,
                                     provider: 'whatsapp', identity: '+15551234567')
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
