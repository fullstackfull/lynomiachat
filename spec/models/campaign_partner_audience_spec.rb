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

  # A native grant is not a partner grant. This is not a gap: the send boundary refuses the
  # same contact, so including them would promise a merchant somebody their campaign will not
  # message.
  it 'does not reach a shopper with only an account-wide native grant' do
    native_only = shopper('native only')
    native(native_only, :granted)

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
    expect(allowed_by_boundary).to contain_exactly(population[:partner_granted])
  end

  # An installation an operator revoked authorises nothing, and the audience says so before
  # the merchant presses send rather than after.
  it 'is empty when the installation is no longer active' do
    partner_consent(shopper('opted in'), store, :granted)
    store.update!(status: :disabled)

    expect(campaign.reload.audience_contacts).to be_empty
  end
end
