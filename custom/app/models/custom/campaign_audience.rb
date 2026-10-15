# Lynomia Campaigns (docs/campaigns/02-recipients.md): a one-off campaign's audience may list the account's shared contact
# audiences, `{ "type": "Audience", "id": <custom filter id> }`, beside its labels. The campaign keeps the reference, never
# the conditions. They are resolved with the labels, when the campaign is sent, through each audience's own saved filter:
# the recipients are the account's contacts in any label or any audience, each once.
module Custom::CampaignAudience
  AUDIENCE_TYPE = 'Audience'.freeze

  def self.prepended(base)
    base.validate :audiences_shared_in_account
  end

  # EVERY PATH THAT RESOLVES RECIPIENTS COMES THROUGH HERE -- all four senders, the pre-send
  # `audience_preview` count and Campaigns::RecipientSnapshot#seed -- which is why the consent
  # filter is applied at this one point and nowhere else. Before it, a contact who had replied
  # STOP, a contact an agent had blocked, and a contact the provider had reported as unable to
  # receive were each addressed exactly like anyone else.
  #
  # Filtering here also makes the preview necessarily agree with the send, because they become
  # the same query. A check added to the four senders instead would be four copies of one rule,
  # and the first one somebody forgot to update would be the one that messaged a person who had
  # opted out. See Campaigns::Eligibility for what is excluded and why the refusal half of the
  # rule is unconditional while the grant half is not.
  def audience_contacts
    Campaigns::Eligibility.filter(selected_contacts { super }, account)
  end

  # Who the audience NAMES, before eligibility is applied. Public and separate so the preview
  # can report why the reachable number is smaller than the selected one, counting both off the
  # same population rather than off two queries that could disagree.
  #
  # Upstream's label resolution arrives as a block because `super` is only meaningful inside the
  # method that overrides it; a zsuper in a block still targets the enclosing method's super, so
  # the label rule stays upstream's and is not restated here.
  def selected_contacts
    audiences = shared_audiences.find(audience_ids)
    return yield if audiences.empty?

    sources = audiences.map(&:members)
    sources << yield if audience.any? { |entry| entry['type'] == 'Label' }
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
