# Lynomia Campaigns (docs/campaigns/02-recipients.md): a one-off campaign's audience may list the account's shared contact
# audiences, `{ "type": "Audience", "id": <custom filter id> }`, beside its labels. The campaign keeps the reference, never
# the conditions. They are resolved with the labels, when the campaign is sent, through each audience's own saved filter:
# the recipients are the account's contacts in any label or any audience, each once.
module Custom::CampaignAudience
  AUDIENCE_TYPE = 'Audience'.freeze

  def self.prepended(base)
    base.validate :audiences_shared_in_account
  end

  def audience_contacts
    audiences = shared_audiences.find(audience_ids)
    return super if audiences.empty?

    sources = audiences.map(&:members)
    sources << super if audience.any? { |entry| entry['type'] == 'Label' }
    sources.map { |source| account.contacts.where(id: source.unscope(:select, :order).select(:id)) }.reduce(:or)
  end

  def audience_ids = Array(audience).select { |entry| entry['type'] == AUDIENCE_TYPE }.pluck('id')

  # Audience entries are allowed on one-off campaigns only, and name shared contact audiences of the campaign's account.
  def audiences_shared_in_account?
    ids = audience_ids
    ids.empty? || (one_off? && ids.all?(Integer) && shared_audiences.where(id: ids).count == ids.uniq.size)
  end

  private

  def shared_audiences = account.custom_filters.contact.where(shared: true)

  def audiences_shared_in_account
    errors.add(:base, I18n.t('errors.campaigns.audience_not_shared')) unless audiences_shared_in_account?
  end
end
