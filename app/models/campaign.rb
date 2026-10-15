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
  # `cancelled` is Lynomia's (P5D): an operator stopped this campaign. Unlike `blocked` it is
  # TERMINAL and deliberate -- `blocked` is a holding state the system entered on its own and
  # can leave, while a cancellation is a person's decision and there is no un-cancel. A
  # cancelled campaign is never picked up again by the scheduler, and a run already in flight
  # stops at its next recipient: Campaigns::SendGuard re-reads the status per recipient, so
  # cancelling stops the send that is happening NOW rather than the next one, which is the
  # only moment anybody reaches for it.
  enum campaign_status: { active: 0, completed: 1, processing: 2, blocked: 3, cancelled: 4 }

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
    return if cancelled?
    return block_for_disabled_feature! unless feature_enabled?
    return unless mark_processing!

    execute_campaign
  end

  # An operator stopping a campaign.
  #
  # TERMINAL, AND UNDER THE SAME LOCK AS mark_processing! -- a scheduler job and a cancelling
  # operator can reach the row at the same moment, and without the lock the job's flip to
  # `processing` could land after the cancellation and resurrect it. Taking the lock means one
  # of the two sees the other's write.
  #
  # A COMPLETED CAMPAIGN CANNOT BE CANCELLED, because there is nothing left to stop and saying
  # otherwise would misreport what happened: its messages were sent.
  #
  # The in-flight run is NOT interrupted here and does not need to be. Campaigns::SendGuard
  # re-reads the campaign per recipient, so the loop stops at its next one; reaching into a
  # running job would be a second mechanism for the same effect, and the harder one to prove.
  def cancel!(reason = nil)
    with_lock do
      next false if completed? || cancelled?

      update!(campaign_status: :cancelled, blocked_reason: reason.presence)
      true
    end
  end

  # TERMINAL MEANS TERMINAL, INCLUDING AGAINST THE RUN THAT WAS ALREADY GOING.
  #
  # Every sender ends `perform` with `campaign.completed!` once its loop returns, and the
  # loop returns NORMALLY when a cancellation stopped it -- Campaigns::SendGuard refuses each
  # remaining recipient rather than raising, which is deliberate: a run that has already
  # handed messages to a provider must not abort. So the status an operator watched change to
  # `cancelled` was overwritten by `completed` a moment later, along with a `completed_at`
  # that says the campaign finished sending. The sends really did stop. What was wrong was
  # the only account of it anybody can read afterwards, and a cancellation whose record
  # disappears is indistinguishable from one that never happened.
  #
  # HERE RATHER THAN IN THE SENDERS, because there are four of them and the first one
  # somebody forgot would be the one that reported a stopped campaign as finished. `false`
  # rather than a raise, for the same reason the guard refuses rather than raises.
  #
  # AND UNDER THE LOCK, READING THE ROW RATHER THAN THE ATTRIBUTE. The sender holds the
  # campaign object it was handed when the job started; the operator cancels in another
  # process. `cancelled?` on the held object answers a question about the moment the run
  # began, so a guard written that way lets exactly the case it exists for through -- which
  # is the same staleness Campaigns::SendGuard#live exists to defeat. The lock is the one
  # `cancel!` takes, so the two serialise: whichever arrives second sees the first's write.
  def completed!
    with_lock { cancelled? ? false : super }
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
    # The signal is an OPEN observation, so leaving it open after the campaign has resumed would leave the
    # Operations feed asserting something that is no longer true -- and the feed is the surface this decision
    # relies on for operator visibility. `resolve` is subject-scoped (signal_recorder.rb:90-95), so this closes
    # this campaign's row and nobody else's, and it is a no-op when there is none.
    Operations::SignalRecorder.new(source: :campaign, account: account, subject: self).resolve(:feature_disabled)
    true
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
      next if completed? || processing? || blocked? || cancelled?

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
