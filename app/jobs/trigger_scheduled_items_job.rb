class TriggerScheduledItemsJob < ApplicationJob
  queue_as :scheduled_jobs

  # How far back a scheduled campaign is still picked up. Upstream's bound, unchanged -- named here only so
  # Campaign#unblock! can respect the same window instead of repeating the number (DECISION 6). A campaign
  # scheduled longer ago than this is not selected at all, which is why re-activating one that was blocked for
  # days has to move its scheduled time forward to mean anything.
  SELECTION_WINDOW = 3.days

  def perform
    # trigger the scheduled campaign jobs
    #
    # `campaign_status: :active` is also what keeps a `blocked` campaign out of here: it is not retried, which
    # is the point of the state. It returns only when an operator re-activates it.
    Campaign.where(campaign_type: :one_off,
                   campaign_status: :active).where(scheduled_at: SELECTION_WINDOW.ago..Time.current).all.find_each(batch_size: 100) do |campaign|
      Campaigns::TriggerOneoffCampaignJob.perform_later(campaign)
    end

    # Job to reopen snoozed conversations
    Conversations::ReopenSnoozedConversationsJob.perform_later

    # Job to reopen snoozed notifications
    Notification::ReopenSnoozedNotificationsJob.perform_later

    # Job to auto-resolve conversations
    Account::ConversationsResolutionSchedulerJob.perform_later

    # Job to sync whatsapp templates
    Channels::Whatsapp::TemplatesSyncSchedulerJob.perform_later

    # Job to trigger pending executions
    AutomationRules::TriggerPendingExecutionsJob.perform_later
  end
end

TriggerScheduledItemsJob.prepend_mod_with('TriggerScheduledItemsJob')
