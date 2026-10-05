# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md): projects a channel's
# already-synced message_templates snapshot into Whatsapp::MessageTemplate rows. It never calls Meta -- it reads the
# jsonb the sync has written -- so it is safe to run at the end of a sync, from a read, and on a deploy with no
# backfill migration and no network request.
#
# Remote truth flows one way: Meta -> the channel's snapshot -> rows. Only a template present in the snapshot is ever
# matched, so a local draft Meta has never seen is outside the write set by construction, not by a conditional: a sync
# can neither delete nor overwrite one. Every template a pass sees is stamped with the same meta_synced_at, which is
# how a template that has disappeared from Meta is observed (Whatsapp::MessageTemplate#missing_at_meta?) instead of
# being given a status we invented.
#
# A pass is a machine sync, not a user action, so it writes no audit rows.
class Whatsapp::Templates::Mirror
  # The fields a template must have for the manager to be able to render, submit or edit it. Everything else Meta sent
  # is kept verbatim in meta_payload.
  REQUIRED = %w[name language category status].freeze
  # The fields promoted to columns; the rest of Meta's object stays in meta_payload (rejected_reason, quality_score,
  # sub_category, previous_category, namespace, health_status, last_updated_time, ...).
  PROMOTED = %w[id name language category status components parameter_format].freeze

  # Brings every WABA of the account up to date from the snapshots already on disk. Cheap enough to call on a read:
  # one aggregate per WABA, and nothing at all when the rows are already current.
  def self.reconcile_account!(account)
    account.whatsapp_channels.group_by { |channel| channel.provider_config['business_account_id'] }
           .each { |waba_id, channels| reconcile_waba!(account, waba_id, channels) }
  end

  def self.reconcile_waba!(account, waba_id, channels)
    return if waba_id.blank?

    channel = channels.select { |c| c.message_templates_last_updated.present? }
                      .max_by(&:message_templates_last_updated)
    return if channel.nil?

    mirrored_at = Whatsapp::MessageTemplate.where(account_id: account.id, business_account_id: waba_id)
                                           .maximum(:meta_synced_at)
    return if mirrored_at.present? && mirrored_at >= channel.message_templates_last_updated

    new(channel).perform
  end
  private_class_method :reconcile_waba!

  def initialize(channel)
    @channel = channel
  end

  def perform
    return if waba_id.blank? || snapshot.blank?

    seen_at = Time.current
    rows = existing_rows

    # Not a user action: auditing covers what a person does to a template, not what Meta reports about it.
    Whatsapp::MessageTemplate.without_auditing do
      snapshot.each { |remote| mirror_one(remote, rows, seen_at) }
    end
  end

  private

  attr_reader :channel

  def waba_id
    @waba_id ||= channel.provider_config['business_account_id']
  end

  def snapshot
    @snapshot ||= Array(channel.message_templates)
                  .select { |template| template.is_a?(Hash) && REQUIRED.all? { |key| template[key].present? } }
  end

  def existing_rows
    rows = Whatsapp::MessageTemplate.where(account_id: channel.account_id, business_account_id: waba_id).to_a
    {
      by_meta_id: rows.filter_map { |row| [row.meta_template_id, row] if row.meta_template_id.present? }.to_h,
      by_identity: rows.index_by { |row| identity(row.name, row.language) }
    }
  end

  # Meta's id first, so a template renamed at Meta updates its own row instead of creating a second one; then the
  # identity a row without an id is found by.
  def mirror_one(remote, rows, seen_at)
    meta_id = remote['id'].presence&.to_s
    row = rows[:by_meta_id][meta_id] if meta_id.present?
    row ||= rows[:by_identity][identity(remote['name'], remote['language'])]
    row ||= Whatsapp::MessageTemplate.new(account_id: channel.account_id, business_account_id: waba_id)

    row.assign_attributes(attributes_for(remote).merge(meta_synced_at: seen_at))
    row.save!
  end

  def attributes_for(remote)
    {
      name: remote['name'],
      language: remote['language'],
      category: remote['category'],
      parameter_format: remote['parameter_format'].presence || 'POSITIONAL',
      components: Array(remote['components']),
      meta_template_id: remote['id'].presence&.to_s,
      meta_status: remote['status'],
      meta_payload: remote.except(*PROMOTED)
    }
  end

  def identity(name, language)
    [name, language.to_s.downcase]
  end
end
