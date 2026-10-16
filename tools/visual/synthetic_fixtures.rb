# SYNTHETIC FIXTURES FOR VISUAL WORK, DEVELOPMENT ONLY.
#
# A screen with no rows cannot be designed: an empty campaigns list says nothing about how a campaign
# reads, how its status chips sit, or what happens when a title is long. `rails db:seed` populates
# conversations and contacts but leaves campaigns and automation rules at zero, so those two screens
# were being skipped for want of a row rather than for want of a design.
#
# Everything here is invented. The names are places and plain nouns, the messages are the product's
# own vocabulary, and nothing is copied from a customer. It refuses to run outside development.
#
#   bundle exec rails runner tools/visual/synthetic_fixtures.rb
#
# It is idempotent: re-running updates the same records rather than adding more.
abort "refusing to run in #{Rails.env}" unless Rails.env.development?

account = Account.first or abort 'no account -- run `rails db:seed` first'
user    = account.users.first
inboxes = account.inboxes.to_a
abort 'no inboxes -- run `rails db:seed` first' if inboxes.empty?

# Which inbox a campaign sits on is not decoration: `Campaign#ensure_correct_campaign_attributes` derives
# `campaign_type` from it, and each of the three campaign pages filters on BOTH. A one-off campaign parked on
# the website inbox is forced back to `ongoing` and then appears on no page at all, which is what the first
# version of this file did to its two one-off rows.
def inbox_of(inboxes, channel_type)
  inboxes.find { |i| i.channel_type == channel_type } or abort "no #{channel_type} inbox -- run `rails db:seed` first"
end

web_inbox      = inbox_of(inboxes, 'Channel::WebWidget')
sms_inbox      = inbox_of(inboxes, 'Channel::Sms')
whatsapp_inbox = inbox_of(inboxes, 'Channel::Whatsapp')

# An audience is a list of label references, the same shape the campaign form submits. Two labels so the
# recipients line has something to summarise rather than a bare count.
audience = account.labels.order(:id).limit(2).map { |label| { 'type' => 'Label', 'id' => label.id } }

campaigns = [
  { title: 'Welcome to Lynomia',
    description: 'Greets a visitor the first time they open the chat.',
    message: 'Hi! Anything we can help you find today?',
    campaign_type: :ongoing, enabled: true },
  { title: 'Checkout help',
    description: 'Offers a hand to anyone who lingers on the payment step.',
    message: 'Stuck on checkout? We can finish the order with you.',
    campaign_type: :ongoing, enabled: true },
  { title: 'Pricing page follow-up',
    description: 'Paused while the new plans are in review.',
    message: 'Questions about which plan fits? Ask away.',
    campaign_type: :ongoing, enabled: false },
  { title: 'Spring restock announcement — everything back in stock from Sunday',
    description: 'A long title, on purpose: this is what the row does when it has to wrap.',
    message: 'Good news — the pieces you asked about are back in stock from Sunday.',
    inbox: :sms, enabled: true, scheduled_at: 3.days.from_now },
  { title: 'Order status check-in',
    description: 'Sent once, last month.',
    message: 'Your order shipped. Reply here if anything is wrong with it.',
    inbox: :sms, enabled: true, scheduled_at: 4.weeks.ago,
    campaign_status: :completed },
  { title: 'Delivery window reminder',
    description: 'Goes out the evening before the courier arrives.',
    message: 'Your order arrives tomorrow between 9am and noon. Reply if that does not suit.',
    inbox: :whatsapp, enabled: true, scheduled_at: 2.days.from_now },
  { title: 'Ramadan hours',
    description: 'Sent to everyone on the announcements label.',
    message: 'Our hours change from Monday: 10am to 4pm, and 8pm to midnight.',
    inbox: :whatsapp, enabled: true, scheduled_at: 3.weeks.ago,
    campaign_status: :completed },
  # DECISION 6's holding state. A campaign in it reads "Blocked" in `danger` on the card, which is a state no
  # amount of seeded data would otherwise produce on a developer's machine.
  { title: 'Loyalty points expiring',
    description: 'Reached its send time while the WhatsApp campaign capability was unavailable.',
    message: 'You have 400 points expiring at the end of the month.',
    inbox: :whatsapp, enabled: true, scheduled_at: 1.day.ago,
    campaign_status: :blocked, blocked_reason: Campaign::BLOCKED_FEATURE_DISABLED }
]

campaigns.each do |attrs|
  campaign = account.campaigns.find_or_initialize_by(title: attrs[:title])

  # A COMPLETED CAMPAIGN IS FINISHED, and the model says so: re-saving one raises "The campaign is
  # already completed". The first run of this script created it, so the second run must leave it alone
  # rather than try to write the same attributes back over it.
  if campaign.persisted? && campaign.completed?
    puts "campaign: #{campaign.title} (already completed, left as is)"
    next
  end

  inbox = case attrs[:inbox]
          when :sms      then sms_inbox
          when :whatsapp then whatsapp_inbox
          else web_inbox
          end

  campaign.assign_attributes(
    attrs.except(:campaign_status, :blocked_reason, :inbox)
         .merge(inbox: inbox, sender: user, audience: audience)
  )
  # Status and the reason behind it are assigned after the rest, because `campaign_status` is validated against
  # the record's own previous value and `blocked_reason` only means anything alongside `blocked`.
  campaign.campaign_status = attrs[:campaign_status] if attrs[:campaign_status]
  campaign.blocked_reason = attrs[:blocked_reason] if attrs.key?(:blocked_reason)
  campaign.save!
  puts "campaign: #{campaign.title}"
end

rules = [
  { name: 'Tag billing questions',
    description: 'Adds the billing label when a message mentions an invoice or a refund.',
    event_name: 'message_created', active: true,
    conditions: [{ attribute_key: 'content', filter_operator: 'contains',
                   values: ['invoice'], query_operator: nil }],
    actions: [{ action_name: 'add_label', action_params: ['billing'] }] },
  { name: 'Greet a first-time contact',
    description: 'Sends one opening message when a brand-new conversation arrives.',
    event_name: 'conversation_created', active: true,
    conditions: [{ attribute_key: 'status', filter_operator: 'equal_to',
                   values: ['open'], query_operator: nil }],
    actions: [{ action_name: 'send_message',
                action_params: ['Thanks for writing in — someone is on it.'] }] },
  { name: 'Escalate an angry message',
    description: 'Turned off while the wording is agreed.',
    event_name: 'message_created', active: false,
    conditions: [{ attribute_key: 'content', filter_operator: 'contains',
                   values: ['refund'], query_operator: nil }],
    actions: [{ action_name: 'assign_team', action_params: [] }] },
  { name: 'Close resolved conversations after three days',
    description: 'Housekeeping, so the open count means something.',
    event_name: 'conversation_updated', active: true,
    conditions: [{ attribute_key: 'status', filter_operator: 'equal_to',
                   values: ['resolved'], query_operator: nil }],
    actions: [{ action_name: 'resolve_conversation', action_params: [] }] }
]

rules.each do |attrs|
  rule = account.automation_rules.find_or_initialize_by(name: attrs[:name])
  rule.assign_attributes(attrs)
  rule.save!
  puts "rule: #{rule.name}"
end

puts "\ncampaigns: #{account.campaigns.count}   automation rules: #{account.automation_rules.count}"
