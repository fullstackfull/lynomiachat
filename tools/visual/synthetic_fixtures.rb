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

# ---------------------------------------------------------------------------------------------------------
# A WEEK OF TRAFFIC, so the reports screens have something to report on.
#
# `rails db:seed` creates twenty conversations and stamps them all within a minute of each other, which is
# the right thing for a list and the wrong thing for every chart: the Overview's traffic heatmap comes out
# empty except for one cell, the resolution chart is blank because nothing has ever been resolved, and a
# screenshot of it published beside the words "see how the team is actually doing" shows a product with
# nothing in it. Those charts read `conversations.created_at` and the `reporting_events` rows written when a
# conversation is resolved or first answered, so this writes both.
#
# IT IS SHAPED, NOT RANDOM. Weekday mornings and early evenings carry more than nights and weekends, because
# a heatmap of uniform noise looks exactly as fake as a heatmap of one cell. The arithmetic is deterministic
# -- index-based, no `rand` -- so re-running produces the same week and a re-captured screenshot differs only
# where the product changed.
#
# WHY NOT `db:seed:reports_data`. The repository already ships `Seeders::Reports::ReportDataSeeder`, and it
# is the right tool for a different job: it is a PERFORMANCE fixture -- a thousand conversations, a hundred
# Faker contacts, twenty invented agents over three months -- and it CLEARS THE ACCOUNT FIRST. Running it
# here would throw away the seeded contacts, campaigns and rules every other screenshot in this set is a
# picture of, and replace the names in the conversation list with a different set on every run, so no two
# captures would be comparable. This keeps the rows `rails db:seed` made and only moves them in time.
#
# NOTHING HERE IS A CLAIM. These are seeded demo conversations in a development database; the figures they
# produce are illustrative and `docs/screenshots/README.md` says so. No marketing copy quotes a number off
# these charts.

# THE WEEK'S SHAPE, as a count per hour. A heatmap colours each cell against the busiest cell in the grid,
# so a week spread thinly enough that no cell holds more than one conversation renders as 168 cells of the
# palest tint -- which is indistinguishable from empty. These weights put five conversations in the busiest
# hour and none overnight, which gives the scale something to work with and looks like a support desk rather
# than like noise.
HOUR_WEIGHTS = {
  7 => 1, 8 => 2, 9 => 4, 10 => 5, 11 => 5, 12 => 3, 13 => 3, 14 => 4,
  15 => 4, 16 => 3, 17 => 2, 18 => 2, 19 => 3, 20 => 3, 21 => 2, 22 => 1
}.freeze
WEEK_DAYS = 7
# Saturday and Sunday keep every third conversation. Two quiet columns are what makes the other five read as
# working days.
QUIET_DIVISOR = 3

seed_conversations = account.conversations.order(:id).to_a
abort 'no conversations -- run `rails db:seed` first' if seed_conversations.empty?

now = Time.zone.now
slots = []
(0...WEEK_DAYS).each do |back|
  day = (now - back.days).beginning_of_day
  weekend = day.saturday? || day.sunday?
  HOUR_WEIGHTS.each do |hour, weight|
    count = weekend ? weight / QUIET_DIVISOR : weight
    count.times { |n| slots << day.change(hour: hour, min: (n * 11) % 60) }
  end
end

# Reuse the seeded rows first, then clone from them. A clone keeps its contact, inbox and messages pointer,
# which is all these charts read; `display_id` and `uuid` are cleared so the model assigns fresh ones.
while account.conversations.count < slots.length
  source = seed_conversations[account.conversations.count % seed_conversations.length]
  copy = source.dup
  copy.display_id = nil
  copy.uuid = nil
  copy.identifier = nil
  copy.save!
end

# rubocop:disable Rails/SkipsModelValidations -- backdating is the whole point: a callback that stamps
# `updated_at` or fires a notification would undo it, and these rows are development fixtures.
# A DESK THAT ANSWERS ITS MESSAGES. `first_reply_created_at` is what the Overview counts as "unattended",
# and clones of the seed arrive with it unset -- so a week of traffic came out as 81 unattended out of 85
# open, which is a picture of a support desk nobody is running. Nine in ten get a first reply, and the rest
# are the queue. Assignment is spread over the seeded agents for the same reason: every conversation
# unassigned is not a product working.
agents = account.users.order(:id).to_a

conversations = account.conversations.order(:id).to_a
conversations.each_with_index do |conversation, index|
  created = slots[index % slots.length]
  replied = index % 10 == 9 ? nil : created + (4 + ((index * 97) % 28)).minutes
  conversation.update_columns(created_at: created, updated_at: created,
                              first_reply_created_at: replied,
                              assignee_id: index % 7 == 6 ? nil : agents[index % agents.length]&.id)
  conversation.messages.update_all(created_at: created, updated_at: created)
end

# Two thirds resolved, with a first response and a resolution time each. `ReportingEvent` is what the
# response-time and resolution charts average, and nothing writes one retroactively, so they are written
# here rather than by calling `resolved!` -- which would fire notifications and webhooks for a conversation
# that was "resolved" a week ago.
ReportingEvent.where(account_id: account.id).delete_all

conversations.each_with_index do |conversation, index|
  next if index % 3 == 2

  opened = conversation.created_at
  # 4 to 32 minutes to the first reply, 40 minutes to 11 hours to resolution: a spread wide enough that an
  # average means something and no figure is implausibly good.
  first_response = 4.minutes + ((index * 97) % 28).minutes
  resolution = 40.minutes + ((index * 37) % 620).minutes

  ReportingEvent.create!(
    account_id: account.id, inbox_id: conversation.inbox_id, user_id: conversation.assignee_id,
    conversation_id: conversation.id, name: 'first_response', value: first_response.to_i,
    value_in_business_hours: first_response.to_i,
    event_start_time: opened, event_end_time: opened + first_response, created_at: opened + first_response
  )
  ReportingEvent.create!(
    account_id: account.id, inbox_id: conversation.inbox_id, user_id: conversation.assignee_id,
    conversation_id: conversation.id, name: 'conversation_resolved', value: resolution.to_i,
    value_in_business_hours: resolution.to_i,
    event_start_time: opened, event_end_time: opened + resolution, created_at: opened + resolution
  )
  conversation.update_columns(status: Conversation.statuses[:resolved])
end
# rubocop:enable Rails/SkipsModelValidations

puts "\nconversations: #{account.conversations.count} over #{WEEK_DAYS} days   " \
     "reporting events: #{ReportingEvent.where(account_id: account.id).count}"
