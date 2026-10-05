# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/02-local-record-design.md §5): the one door every
# new surface reads templates through -- the manager's list and detail, and the campaign and flow selectors.
#
# Two questions, each answered by the store that owns it, which is what keeps the two stores coherent instead of
# split-brained:
#
#   management (list, detail, lifecycle) -> Whatsapp::MessageTemplate rows, reconciled from the channel snapshots
#                                           before every read, so no caller can see stale rows;
#   "what can this inbox send"           -> the channel's synced snapshot under the existing product rule
#                                           (Flows::Template.sendable? plus Meta's approved status, which is exactly
#                                           @chatwoot/utils isSendableTemplate, already used by the composer and the
#                                           campaign picker). A send must not depend on a projection having run, so
#                                           the snapshot stays the live gate -- as Whatsapp::TemplateProcessorService
#                                           already has it.
#
# Note the deliberate difference between selection and sending, which is today's behaviour made explicit in one place:
# selection applies the stricter product rule (no authentication template, no CSAT template, no interactive component),
# while a send applies Meta's rule (approved), so an API client sending an authentication template to an ordinary
# number keeps working.
class Whatsapp::Templates::Query
  def initialize(account)
    @account = account
  end

  def templates
    reconcile!
    Whatsapp::MessageTemplate.where(account_id: account.id).order(:name, :language)
  end

  def for_inbox(inbox)
    templates.for_waba(waba_id_of(inbox))
  end

  def find!(id)
    reconcile!
    Whatsapp::MessageTemplate.where(account_id: account.id).find(id)
  end

  # Per WABA: the inboxes that can send its templates, and when its rows were last mirrored -- the value
  # Whatsapp::MessageTemplate#missing_at_meta? compares against. Two queries for a whole page.
  def waba_contexts
    @waba_contexts ||= begin
      mirrored = Whatsapp::MessageTemplate.where(account_id: account.id)
                                          .group(:business_account_id).maximum(:meta_synced_at)
      channels_by_waba.to_h do |waba_id, channels|
        [waba_id,
         { mirrored_at: mirrored[waba_id],
           inboxes: channels.map { |channel| { id: channel.inbox.id, name: channel.inbox.name } } }]
      end
    end
  end

  # The templates this inbox can actually offer, from its own synced snapshot.
  def sendable_for(inbox)
    Array(inbox.channel.try(:message_templates)).select do |template|
      template.is_a?(Hash) && template['status'].to_s.casecmp?('approved') && Flows::Template.sendable?(template)
    end
  end

  private

  attr_reader :account

  # Network-free: it reads the snapshots the sync has already written, and does nothing when the rows are current.
  def reconcile!
    return if @reconciled

    Whatsapp::Templates::Mirror.reconcile_account!(account)
    @reconciled = true
  end

  def channels_by_waba
    @channels_by_waba ||= account.whatsapp_channels.includes(:inbox)
                                 .group_by { |channel| channel.provider_config['business_account_id'] }
                                 .except(nil, '')
  end

  def waba_id_of(inbox)
    inbox.channel.try(:provider_config)&.dig('business_account_id')
  end
end
