# == Schema Information
#
# Table name: campaigns
#
#  id                                 :bigint           not null, primary key
#  audience                           :jsonb
#  campaign_status                    :integer          default("active"), not null
#  campaign_type                      :integer          default("ongoing"), not null
#  description                        :text
#  enabled                            :boolean          default(TRUE)
#  message                            :text             not null
#  scheduled_at                       :datetime
#  started_at                         :datetime
#  completed_at                       :datetime
#  template_params                    :jsonb
#  title                              :string           not null
#  trigger_only_during_business_hours :boolean          default(FALSE)
#  trigger_rules                      :jsonb
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  account_id                         :bigint           not null
#  display_id                         :integer          not null
#  inbox_id                           :bigint           not null
#  sender_id                          :integer
#
# Indexes
#
#  index_campaigns_on_account_id       (account_id)
#  index_campaigns_on_campaign_status  (campaign_status)
#  index_campaigns_on_campaign_type    (campaign_type)
#  index_campaigns_on_inbox_id         (inbox_id)
#  index_campaigns_on_scheduled_at     (scheduled_at)
#
class Campaign < ApplicationRecord
  include UrlHelper
  validates :account_id, presence: true
  validates :inbox_id, presence: true
  validates :title, presence: true
  validates :message, presence: true
  validate :validate_campaign_inbox
  validate :validate_url
  validate :prevent_completed_campaign_from_update, on: :update
  validate :sender_must_belong_to_account
  validate :inbox_must_belong_to_account

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true

  enum campaign_type: { ongoing: 0, one_off: 1 }
  # TODO : enabled attribute is unneccessary . lets move that to the campaign status with additional statuses like draft, disabled etc.
  #
  # `blocked` is Lynomia's (DECISION 6): a scheduled WhatsApp campaign reached its send time while the
  # `whatsapp_campaign` capability was unavailable. It is a HOLDING state, not a terminal one -- the campaign and
  # its audience are untouched and `unblock!` returns it to `active`. It exists because the alternative, which is
  # what this model did before, is a campaign that keeps reading `active`, is retried silently for three days and
  # is then abandoned with nothing recorded anywhere.
  #
  # Only a WhatsApp campaign can hold it: `feature_enabled?` is true for every other inbox type, so no SMS or
  # website campaign can reach the transition.
  enum campaign_status: { active: 0, completed: 1, processing: 2, blocked: 3 }

  # The machine-readable reason a campaign is blocked. One value today; a constant rather than a literal so a
  # reader can match on it and a second reason has somewhere to go.
  BLOCKED_FEATURE_DISABLED = 'FEATURE_DISABLED'.freeze

  has_many :conversations, dependent: :nullify, autosave: true

  before_validation :ensure_correct_campaign_attributes
  before_update :set_completed_at, if: :marking_completed?
  after_commit :set_display_id, unless: :display_id?
  after_destroy_commit :invalidate_filtered_unread_count_filters

  def trigger!
    return unless one_off?
    return block_for_disabled_feature! unless feature_enabled?
    return unless mark_processing!

    execute_campaign
  end

  # Back to `active`, which is the only way out of `blocked` other than the operator deleting the campaign.
  # Scheduled time moves to now when it has fallen outside the window `TriggerScheduledItemsJob` selects on
  # (scheduled_at:3), because otherwise re-activating a campaign that was blocked for more than three days
  # silently does nothing -- the same silence this decision exists to remove. Re-activating a blocked campaign
  # means "send it now", so saying so in the data is honest rather than clever.
  def unblock!
    return false unless blocked?

    attributes = { campaign_status: :active, blocked_reason: nil }
    attributes[:scheduled_at] = Time.current if scheduled_at.nil? || scheduled_at < TriggerScheduledItemsJob::SELECTION_WINDOW.ago

    update!(attributes)
  end

  # The contacts the campaign's audience selects, resolved when it is sent: any of its labels, each contact once.
  def audience_contacts
    label_ids = audience.select { |entry| entry['type'] == 'Label' }.pluck('id')
    account.contacts.tagged_with(account.labels.where(id: label_ids).pluck(:title), any: true)
  end

  private

  def feature_enabled?
    inbox.inbox_type != 'Whatsapp' || account.feature_enabled?(:whatsapp_campaign)
  end

  # The whole of DECISION 6's write side, and it is reached only from a WhatsApp campaign because
  # `feature_enabled?` is true for every other inbox type.
  #
  # Under a lock and idempotent: a job already in flight when the campaign was blocked finds it blocked and
  # changes nothing, and the signal's own dedup means the second observation raises `occurrences` rather than
  # adding a row. Returns nil so `trigger!` reads as a guard clause.
  def block_for_disabled_feature!
    newly_blocked = with_lock do
      next false if completed? || blocked?

      update!(campaign_status: :blocked, blocked_reason: BLOCKED_FEATURE_DISABLED)
      true
    end

    record_blocked_signal if newly_blocked
    nil
  end

  # EXACTLY ONE row per blocked campaign, which the partial unique index on the open identity guarantees:
  # the identity is (account, source, subject, signal), so a second observation of the same campaign updates
  # the row rather than inserting one. `detail` carries the capability name only -- an allow-listed key holding
  # an identifier, never the campaign's message or audience.
  def record_blocked_signal
    recorder = Operations::SignalRecorder.new(source: :campaign, account: account, subject: self)
    recorder.record(
      :feature_disabled,
      severity: :warning,
      reason: 'Scheduled WhatsApp campaign not sent: the whatsapp_campaign capability is not available',
      detail: { capability: 'whatsapp_campaign', inbox_id: inbox_id }
    )
  end

  def mark_processing!
    # Multiple scheduler jobs can pick the same active campaign; lock before flipping status to avoid duplicate sends.
    #
    # `blocked?` is here as well as in `trigger!` because a job enqueued before the campaign was blocked is a
    # real independent path to this method: it would otherwise find the capability restored and send a campaign
    # the operator has not re-activated.
    with_lock do
      next if completed? || processing? || blocked?

      update!(campaign_status: :processing, started_at: Time.current)
    end
  end

  def marking_completed?
    will_save_change_to_campaign_status? && completed?
  end

  def set_completed_at
    self.completed_at ||= Time.current
  end

  def execute_campaign
    case inbox.inbox_type
    when 'Twilio SMS'
      Twilio::OneoffSmsCampaignService.new(campaign: self).perform
    when 'Sms'
      Sms::OneoffSmsCampaignService.new(campaign: self).perform
    when 'Whatsapp'
      Whatsapp::OneoffCampaignService.new(campaign: self).perform
    end
  end

  def invalidate_filtered_unread_count_filters
    filters_changed = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).conversation_changed!
    dispatch_account_cache_invalidated if filters_changed
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end

  def set_display_id
    reload
  end

  def validate_campaign_inbox
    return unless inbox

    errors.add :inbox, 'Unsupported Inbox type' unless ['Website', 'Twilio SMS', 'Sms', 'Whatsapp'].include? inbox.inbox_type
  end

  # TO-DO we clean up with better validations when campaigns evolve into more inboxes
  def ensure_correct_campaign_attributes
    return if inbox.blank?

    if ['Twilio SMS', 'Sms', 'Whatsapp'].include?(inbox.inbox_type)
      self.campaign_type = 'one_off'
      self.scheduled_at ||= Time.now.utc
    else
      self.campaign_type = 'ongoing'
      self.scheduled_at = nil
    end
  end

  def validate_url
    return unless trigger_rules['url']

    use_http_protocol = trigger_rules['url'].starts_with?('http://') || trigger_rules['url'].starts_with?('https://')
    errors.add(:url, 'invalid') if inbox.inbox_type == 'Website' && !use_http_protocol
  end

  def inbox_must_belong_to_account
    return unless inbox

    return if inbox.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account as the campaign')
  end

  def sender_must_belong_to_account
    return unless sender

    return if account.users.exists?(id: sender.id)

    errors.add(:sender_id, 'must belong to the same account as the campaign')
  end

  def prevent_completed_campaign_from_update
    errors.add :status, 'The campaign is already completed' if !campaign_status_changed? && completed?
  end

  # creating db triggers
  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end
end
Campaign.include_mod_with('Campaign')
Campaign.prepend_mod_with('CampaignAudience')
