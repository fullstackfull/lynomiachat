require 'rails_helper'
require_relative 'platform_support_contract_stub'

# THE WRITE THROTTLES, and the one property that matters beyond the limit itself: A 429 MUST NOT TELL THE
# CALLER WHETHER A RESOURCE EXISTS.
#
# Two structural reasons, both asserted. The counter key is built from the path pattern and the caller's
# identity and never contains the ticket id, so the message route counts and refuses identically for a real
# ticket, another account's ticket and an id that never existed. And the refusal happens in middleware, before
# any controller or model has looked anything up -- so no row is read, and no row is written either.
#
# `Rack::Attack.enabled` is false outside production, so it is switched on around these examples, against an
# in-memory store that cannot be polluted by -- or pollute -- anything else running against the same Redis.
RSpec.describe 'Platform Support abuse protection', type: :request do
  let(:account) { create(:account) }
  # A routable client address, because `Rack::Attack::Request#allowed_ip?` safelists 127.0.0.1 and ::1 and a
  # request spec is otherwise loopback -- which would short-circuit every rule before it is reached.
  let(:client_ip) { '203.0.113.9' }
  let(:other_account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:other_reporter) { create(:user, account: account, role: :agent) }
  let(:ticket) { PlatformSupportContractStub.ticket!(account: account, reporter: reporter) }
  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  around do |example|
    previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    example.run
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.cache.store = previous_store
  end

  def post_message(to_ticket_id, as: reporter)
    post "#{base}/tickets/#{to_ticket_id}/messages", headers: as.create_new_auth_token,
                                                     params: { message: { body: 'A reply' } },
                                                     env: { 'REMOTE_ADDR' => client_ip }, as: :json
  end

  def message_limit
    ENV.fetch('RATE_LIMIT_PLATFORM_SUPPORT_MESSAGE_CREATE', '30').to_i
  end

  it 'refuses message creation past the per-user limit with 429' do
    ticket
    message_limit.times { post_message(ticket.id) }

    post_message(ticket.id)

    expect(response).to have_http_status(:too_many_requests)
  end

  it 'writes nothing once it is refusing' do
    ticket
    message_limit.times { post_message(ticket.id) }

    expect { post_message(ticket.id) }.not_to change(PlatformSupport::Message, :count)
  end

  # THE NON-LEAK PROPERTY. Once the caller is throttled, a real ticket, another account's ticket and an id
  # that never existed all answer identically -- so a 429 reveals nothing a 404 would have hidden.
  it 'answers identically for a real ticket, a foreign ticket and a nonexistent id once throttled' do
    foreign = PlatformSupportContractStub.ticket!(account: other_account)
    ticket
    message_limit.times { post_message(ticket.id) }

    answers = [ticket.id, foreign.id, 0].map do |id|
      post_message(id)
      [response.status, response.body]
    end

    expect(answers.uniq.length).to eq(1)
    expect(answers.first.first).to eq(429)
  end

  it 'names nothing about the request in the refusal body' do
    ticket
    message_limit.times { post_message(ticket.id) }
    post_message(ticket.id)

    expect(response.body).not_to include(ticket.reference, ticket.subject, account.id.to_s)
  end

  # Keyed per user WITHIN the account, so one member's loop cannot throttle their colleagues.
  it 'does not spend another member budget' do
    ticket
    mine = PlatformSupportContractStub.ticket!(account: account, reporter: other_reporter)
    message_limit.times { post_message(ticket.id) }

    post_message(mine.id, as: other_reporter)

    expect(response).to have_http_status(:created)
  end

  describe 'the throttle definitions' do
    it 'uses its own names and its own path regexes, distinct from the tenant desk' do
      names = Rack::Attack.throttles.keys.grep(/platform_support/)

      expect(names).to include(
        '/api/v1/accounts/:account_id/platform_support/* per user',
        '/api/v1/accounts/:account_id/platform_support/tickets create per user',
        '/api/v1/accounts/:account_id/platform_support/tickets create per account',
        '/api/v1/accounts/:account_id/platform_support/tickets/:id/messages create per user',
        '/api/v1/accounts/:account_id/platform_support/tickets/:id/messages create per account'
      )
      expect(names).not_to include('/api/v1/accounts/:account_id/support/* per user')
    end

    it 'matches only the platform_support path and never the tenant support path' do
      expect(Rack::Attack::PLATFORM_SUPPORT_PATHS).to match('/api/v1/accounts/7/platform_support/tickets')
      expect(Rack::Attack::PLATFORM_SUPPORT_PATHS).not_to match('/api/v1/accounts/7/support/tickets')
      expect(Rack::Attack::SUPPORT_TICKETS_PATHS).not_to match('/api/v1/accounts/7/platform_support/tickets')
    end

    it 'reads every limit from ENV with the repository convention' do
      source = File.read(Rails.root.join('config/initializers/rack_attack.rb'))
      platform_block = source[/PLATFORM_SUPPORT_PATHS.*\z/m]

      expect(platform_block.scan(/ENV\.fetch\('RATE_LIMIT_PLATFORM_SUPPORT[A-Z_]*', '\d+'\)/).length).to eq(5)
    end

    # The write limits are the new part: every pre-existing rule in this family is GET-only, so there was no
    # write limit anywhere in it.
    it 'limits writes, unlike the GET-only tenant desk rule' do
      expect(Rack::Attack.throttles['/api/v1/accounts/:account_id/platform_support/tickets create per user'].limit)
        .to be_positive
    end
  end
end
