require 'rails_helper'

# WHAT A SUPPRESSED CUSTOMER LINK MEANS, asserted in every place that asks.
#
# `Commerce::CustomerLink`'s own class note has always said it: a suppressed row is a link an
# AGENT REMOVED, so the contact counts as not linked in that store. Exactly one reader
# honoured it -- the audience condition, by spelling the condition out inline -- and three
# others did not:
#
#   the partner-consent WRITE    a store could record a decision about somebody an agent had
#                                said was not its customer
#   the partner-consent READ     and was told that person's account-wide consent state
#   the consent change feed      and was sent their opt-outs as they happened
#
# None of those is a cross-TENANT leak -- the contact is in the same account -- but all three
# hand one shopper's consent data to a merchant who has been told the match was wrong, which
# is the thing an agent suppresses a link in order to stop.
#
# So the rule is one scope now, and this file is what keeps the four readers agreeing.
RSpec.describe 'a suppressed customer link', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:app) { create(:platform_app) }
  let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'merchant.example:7', status: :active) }
  let(:shopper) { create(:contact, account: account, name: 'Not actually theirs') }
  let!(:link) do
    create(:commerce_customer_link, account: account, store: store, contact: shopper,
                                    external_customer_id: 'cust-77', match_source: :suppressed)
  end

  it 'is not one of the links that mean "this store\'s customer"' do
    expect(Commerce::CustomerLink.linked).not_to include(link)
    expect(Commerce::CustomerLink.all).to include(link)
  end

  it 'is not counted by the audience conditions' do
    expect(Audience::CommerceCondition.counted_links(account)).not_to include(link)
  end

  # The feed enqueues one delivery per installation that knows the person. A suppressed link
  # is an installation that has been told it does not.
  it 'is not told about a native consent decision' do
    create(:webhook, account: account, webhook_type: :account_type, subscriptions: ['consent_changed'])
    account.enable_features!('ip_lookup') # any feature; api_and_webhooks_enabled? is what matters

    expect do
      Commerce::MessagingConsents.record(
        account: account, contact: shopper,
        decision: Commerce::MessagingConsents::Decision.new(state: :withdrawn, source: 'shopper_keyword')
      )
    end.not_to(change { ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == WebhookJob } })
  end
end
