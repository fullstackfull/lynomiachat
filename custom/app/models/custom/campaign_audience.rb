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
    purpose = Campaigns::Eligibility.purpose_for(self)
    selected = selected_contacts { super }
    return Campaigns::Eligibility.filter(selected, account, purpose) unless commerce_store

    # A CAMPAIGN THAT BELONGS TO AN INSTALLATION ASKS BOTH CONSENT STORES, in the same
    # composition Campaigns::SendGuard makes per recipient: the native refusals are
    # unconditional, and the positive comes from the installation the campaign belongs to.
    #
    # It cannot be `filter` here. That requires a NATIVE promotional grant, and the people a
    # Store Syria campaign exists to reach agreed at a Store Syria checkout -- recorded as a
    # partner consent, because this account has no surface on which they could have agreed
    # natively. Asking for a native grant made the audience of every store-scoped
    # promotional campaign empty, so the whole opt-in produced nobody to send to.
    Partners::Eligibility.filter(Campaigns::Eligibility.refusals(selected, account, purpose),
                                 commerce_store, purpose, consent_channel)
  end

  # A saved audience's members, scoped to this campaign's installation.
  #
  # A saved audience whose store no longer counts can match nobody AT THAT STORE, so it
  # contributes nothing rather than being resolved account-wide -- which would over-count,
  # the very thing the store scope exists to stop -- or raising; see `installation_counted?`.
  def members_of(saved)
    return account.contacts.none if commerce_store_id && !installation_counted?

    saved.members(commerce_store_id: commerce_store_id)
  end

  # WHETHER THIS CAMPAIGN'S INSTALLATION STILL COUNTS FOR COMMERCE CONDITIONS.
  #
  # `Custom::Contacts::FilterService#scoped_store_id` RAISES InvalidValue for a store that is
  # not among `Audience::CommerceCondition.counted_stores`. That is right at the REQUEST
  # boundary -- somebody typed an id that is not theirs, and 422 beats silently answering
  # zero -- and wrong at SEND time, where the id was valid when the campaign was saved and
  # what changed is the STORE. A store leaves that set unattended: a rejected token flips it
  # to `needs_reauth`, an operator disables it, or a Super Admin turns the provider off for
  # the whole installation. The raise would then escape `process_audience`, the job would
  # die, and `mark_processing!` refuses to re-enter -- so pausing an integration would wedge
  # every store-scoped campaign in it, permanently.
  #
  # GUARDED HERE AND NOT HIGHER UP, because the two layers draw different lines and both are
  # right. `counted_stores` excludes a store whose PROVIDER is switched off installation-wide;
  # `Partners::Eligibility` and `Campaigns::SendGuard` only require the store to be ACTIVE.
  # Short-circuiting the whole audience on `counted_stores` would exclude contacts the send
  # boundary goes on to allow, which is the audience being NARROWER than the send -- a
  # merchant silently not reaching customers who agreed. So only the commerce conditions,
  # which are the only thing that can raise, are made to contribute nothing; labels resolve
  # as they always did, and a store that is not active is still turned into an empty audience
  # by `Partners::Eligibility.filter` a few lines above.
  def installation_counted?
    return @installation_counted if defined?(@installation_counted)

    @installation_counted = Audience::CommerceCondition.counted_stores(account).exists?(id: commerce_store_id)
  end

  # THE CHANNEL A PARTNER GRANT HAS TO COVER, and it is the sender's answer rather than a
  # second opinion: a grant taken for WhatsApp does not authorise an SMS blast. Each sender
  # passes this same value to Campaigns::SendGuard -- :whatsapp from the WhatsApp service,
  # :sms from both the SMS and the Twilio one -- so the audience and the send boundary scope
  # a partner consent identically. Derived rather than stored because the inbox already
  # decides it and a column would be a second thing to keep in step.
  def consent_channel = inbox&.channel_type == 'Channel::Whatsapp' ? :whatsapp : :sms

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

    # A STORE-SCOPED CAMPAIGN ASKS ABOUT ITS OWN STORE'S CUSTOMERS. Unscoped, "more than three
    # orders" selected a contact with four orders at the merchant's OTHER store and none at
    # this one. Nothing wrong was ever sent -- the send boundary refuses a contact who is not
    # this installation's customer -- but the preview counted them, so the merchant was told
    # their campaign would reach people it could not. A campaign with no store keeps the
    # account-wide meaning, which is every campaign that existed before this.
    sources = audiences.map { |saved| members_of(saved) }
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
