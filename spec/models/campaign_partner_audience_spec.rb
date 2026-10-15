require 'rails_helper'

# THE AUDIENCE OF A CAMPAIGN THAT BELONGS TO A PARTNER INSTALLATION, and the agreement that
# makes the preview worth showing.
#
# WHAT WAS WRONG. `audience_contacts` applied Campaigns::Eligibility.filter to every campaign,
# which requires a NATIVE promotional grant. The people a Store Syria campaign exists to
# reach agreed at a Store Syria checkout, and that agreement is a PartnerConsent -- Lynomia's
# own consent table has no row for them, because the account has no surface on which they
# could have agreed natively. So the audience of every store-scoped promotional campaign was
# empty and the whole P5E opt-in could not produce one recipient.
#
# THE PROPERTY THESE PIN is not "partner grants count" on its own -- it is that the audience
# and the send boundary decide the same contacts. Two expressions of one rule drift, and the
# direction that matters is the audience being WIDER than the boundary: that is a campaign
# that reports it reached people it refused.
RSpec.describe 'a campaign that belongs to an installation', type: :model do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:app) { create(:platform_app) }
  let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1', status: :active) }
  let(:other_store) { create(:commerce_store, account: account, provider: 'salla', external_store_id: 'sa-2', status: :active) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_sms, account: account)) }
  let(:label) { create(:label, account: account, title: 'autumn') }

  let(:campaign) do
    create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, commerce_store: store,
                      audience: [{ type: 'Label', id: label.id }])
  end

  def shopper(name)
    create(:contact, :with_phone_number, account: account, name: name).tap { |c| c.update_labels([label.title]) }
  end

  def partner_consent(contact, store, state, channel: :any)
    PartnerConsent.create!(platform_app: app, account: account, commerce_store: store, contact: contact,
                           external_subject_id: "ext-#{contact.id}", source: 'checkout_optin',
                           purpose: :promotional, channel: channel, state: state, captured_at: Time.current)
  end

  def native(contact, state)
    Commerce::MessagingConsents.record(
      account: account, contact: contact,
      decision: Commerce::MessagingConsents::Decision.new(state: state, source: 'merchant')
    )
  end

  it 'reaches a shopper who agreed at this store’s checkout and nowhere else' do
    opted_in = shopper('opted in')
    partner_consent(opted_in, store, :granted)

    expect(campaign.audience_contacts).to contain_exactly(opted_in)
  end

  # The grant is the installation's, so another installation's is not a basis for this one.
  it 'does not reach a shopper who agreed at the merchant’s OTHER store' do
    elsewhere = shopper('agreed elsewhere')
    partner_consent(elsewhere, other_store, :granted)

    expect(campaign.audience_contacts).to be_empty
  end

  # EITHER STORE'S GRANT SATISFIES STEP 8, and this example used to assert the opposite.
  #
  # ADR-001 §3.3 step 8 is "promotional with no grant from EITHER source", under the rule it
  # states twice: negatives union, positives do not. Requiring a grant from THIS installation
  # and discounting an account-wide native one enforced half of that step as though it were
  # all of it. It failed closed -- nobody was messaged who should not have been -- but a
  # merchant whose customers had agreed on Lynomia's own channels reached none of them, which
  # is the gap §1 of that ADR exists to close, reappearing from the other side.
  it 'reaches a shopper with an account-wide native grant and no grant at this store' do
    native_only = shopper('native only')
    native(native_only, :granted)

    expect(campaign.audience_contacts).to contain_exactly(native_only)
  end

  # AND THE UNION IS OF POSITIVES ONLY. A native grant is a basis for a send; it is not an
  # answer to this installation's own withdrawal, which is a NEGATIVE and still refuses. This
  # is the direction the step-8 correction above could have broken.
  it 'does not reach a shopper this store withdrew, however they agreed natively' do
    both_ways = shopper('granted natively, withdrawn here')
    native(both_ways, :granted)
    partner_consent(both_ways, store, :withdrawn)

    expect(campaign.audience_contacts).to be_empty
  end

  # NEGATIVES UNION. A native withdrawal is unconditional and stops a partner-authorised send.
  it 'does not reach a shopper who agreed at checkout and later replied STOP' do
    changed_mind = shopper('changed mind')
    partner_consent(changed_mind, store, :granted)
    native(changed_mind, :withdrawn)

    expect(campaign.audience_contacts).to be_empty
  end

  it 'does not reach a shopper this store’s own record withdraws' do
    withdrew = shopper('withdrew here')
    partner_consent(withdrew, store, :withdrawn)

    expect(campaign.audience_contacts).to be_empty
  end

  # A grant taken for WhatsApp does not authorise an SMS blast, and the campaign's channel is
  # the inbox's. Scoped identically in the audience and at the send boundary, which is what
  # the agreement example below measures.
  it 'does not reach a shopper whose grant covers another channel' do
    whatsapp_only = shopper('whatsapp only')
    partner_consent(whatsapp_only, store, :granted, channel: :whatsapp)

    expect(campaign.audience_contacts).to be_empty
  end

  # THE ONE THAT CATCHES DRIFT. Every state above, in one population, decided twice: once by
  # the relation the audience is resolved through and once by the per-recipient guard the
  # sender asks. A contact the audience selects and the boundary refuses is a campaign that
  # reports reaching somebody it did not.
  it 'selects exactly the contacts the send boundary would allow' do
    population = {
      partner_granted: shopper('partner granted').tap { |c| partner_consent(c, store, :granted) },
      other_store: shopper('other store').tap { |c| partner_consent(c, other_store, :granted) },
      native_only: shopper('native only').tap { |c| native(c, :granted) },
      both_then_stop: shopper('both then stop').tap do |c|
        partner_consent(c, store, :granted)
        native(c, :withdrawn)
      end,
      partner_withdrawn: shopper('partner withdrawn').tap { |c| partner_consent(c, store, :withdrawn) },
      partner_suppressed: shopper('partner suppressed').tap { |c| partner_consent(c, store, :suppressed) },
      wrong_channel: shopper('wrong channel').tap { |c| partner_consent(c, store, :granted, channel: :whatsapp) },
      blocked: shopper('blocked').tap do |c|
        partner_consent(c, store, :granted)
        c.update!(blocked: true)
      end,
      nothing: shopper('nothing at all')
    }

    allowed_by_boundary = population.values.select { |c| Campaigns::SendGuard.allows?(c, campaign, :sms) }

    expect(campaign.audience_contacts).to match_array(allowed_by_boundary)
    # Two of the nine: a grant at this installation, and an account-wide native grant. Step 8
    # takes either, and nothing else in the population has one in scope.
    expect(allowed_by_boundary).to contain_exactly(population[:partner_granted], population[:native_only])
  end

  # An installation an operator revoked authorises nothing, and the audience says so before
  # the merchant presses send rather than after.
  it 'is empty when the installation is no longer active' do
    partner_consent(shopper('opted in'), store, :granted)
    store.update!(status: :disabled)

    expect(campaign.reload.audience_contacts).to be_empty
  end

  # AND IT MUST NOT RAISE WHILE DOING IT, which is the difference between a campaign that
  # sends nothing and a campaign that is wedged forever.
  #
  # `Custom::Contacts::FilterService#scoped_store_id` raises InvalidValue for a store that is
  # not among the counted ones -- correct at the request boundary, wrong at send time, where
  # the id was valid when the campaign was saved and the STORE changed underneath it. A
  # rejected token flips a store to `needs_reauth` unattended. The raise escapes
  # `process_audience`, the job dies, and `mark_processing!` refuses to re-enter, so pausing
  # an integration would wedge every store-scoped campaign in it permanently.
  it 'resolves to nobody, without raising, when the installation stops being counted' do
    opted_in = shopper('opted in')
    partner_consent(opted_in, store, :granted)
    audience = create(:custom_filter, account: account, filter_type: :contact, shared: true,
                                      query: { 'payload' => [{ 'attribute_key' => 'commerce_orders_count',
                                                               'filter_operator' => 'is_greater_than',
                                                               'values' => ['0'], 'query_operator' => 'and' }] })
    campaign.update!(audience: [{ type: 'Audience', id: audience.id }])
    store.update!(status: :needs_reauth)

    expect { campaign.reload.audience_contacts.to_a }.not_to raise_error
    expect(campaign.reload.audience_contacts).to be_empty
  end

  # The channel is the campaign's, and a grant taken for another channel is not a basis for
  # this one -- asserted here as well as in the agreement example because the PREVIEW builds
  # a campaign of its own and used to get this wrong.
  it 'reaches a WhatsApp grant from a WhatsApp campaign' do
    whatsapp_inbox = create(:inbox, account: account,
                                    channel: create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                                       sync_templates: false,
                                                                       validate_provider_config: false))
    campaign.update!(inbox: whatsapp_inbox)
    reachable = shopper('whatsapp only')
    partner_consent(reachable, store, :granted, channel: :whatsapp)

    expect(campaign.reload.audience_contacts).to contain_exactly(reachable)
  end
end
