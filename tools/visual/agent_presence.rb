# KEEPING AN AGENT ONLINE FOR THE LENGTH OF A CAPTURE RUN. DEVELOPMENT ONLY.
#
# The website widget asks the installation which agents are available and shows "We are away at the moment"
# when the answer is none. Availability is PRESENCE, not a column: `OnlineStatusTracker` holds a sorted set
# in Redis that each connected dashboard refreshes, and an entry older than `PRESENCE_DURATION` (20 seconds)
# is not online any more. A capture run has no dashboard open, so every widget screenshot ever taken here
# came out in the away state -- which is a real state, and the wrong one to illustrate "a visitor messages
# you and somebody answers".
#
# So this is the missing dashboard: it refreshes the presence of the inbox's members while a capture runs,
# and stops. It writes to Redis only -- no record is created, updated or deleted -- so there is nothing to
# undo afterwards; the keys expire on their own 20 seconds after it stops.
#
#   bundle exec rails runner tools/visual/agent_presence.rb 240 &
#
# The argument is how many seconds to keep them up for; it exits on its own so a forgotten background job
# cannot leave a development account looking permanently staffed.
abort 'development only' unless Rails.env.development?

account = Account.first or abort 'no account -- run `rails db:seed` first'
seconds = (ARGV.first || 240).to_i

# The members of the website channel, because they are who the widget asks about. Administrators are not
# added automatically: the widget lists `inbox.members`, so an account whose administrator never joined the
# channel shows as away however many people are signed in.
inbox = account.inboxes.find_by(channel_type: 'Channel::WebWidget') or abort 'no web widget inbox'
agents = inbox.members.to_a
abort "#{inbox.name} has no members" if agents.empty?

puts "holding #{agents.size} agent(s) online on #{inbox.name} for #{seconds}s: #{agents.map(&:name).join(', ')}"

finish = Time.zone.now + seconds
while Time.zone.now < finish
  agents.each do |agent|
    OnlineStatusTracker.update_presence(account.id, 'User', agent.id)
    OnlineStatusTracker.set_status(account.id, agent.id, 'online')
  end
  sleep 5
end

puts 'presence released'
