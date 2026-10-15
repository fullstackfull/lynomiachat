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

web_inbox = inboxes.find { |i| i.channel_type == 'Channel::WebWidget' } || inboxes.first

CAMPAIGNS = [
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
    campaign_type: :one_off, enabled: true, scheduled_at: 3.days.from_now },
  { title: 'Order status check-in',
    description: 'Sent once, last month.',
    message: 'Your order shipped. Reply here if anything is wrong with it.',
    campaign_type: :one_off, enabled: true, scheduled_at: 4.weeks.ago,
    campaign_status: :completed },
]

CAMPAIGNS.each do |attrs|
  campaign = account.campaigns.find_or_initialize_by(title: attrs[:title])
  campaign.assign_attributes(
    attrs.except(:campaign_status).merge(inbox: web_inbox, sender: user)
  )
  campaign.campaign_status = attrs[:campaign_status] if attrs[:campaign_status]
  campaign.save!
  puts "campaign: #{campaign.title}"
end

RULES = [
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
    actions: [{ action_name: 'resolve_conversation', action_params: [] }] },
]

RULES.each do |attrs|
  rule = account.automation_rules.find_or_initialize_by(name: attrs[:name])
  rule.assign_attributes(attrs)
  rule.save!
  puts "rule: #{rule.name}"
end

puts "\ncampaigns: #{account.campaigns.count}   automation rules: #{account.automation_rules.count}"
