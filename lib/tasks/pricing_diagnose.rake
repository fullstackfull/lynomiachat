# WHAT THE PUBLIC PRICING PAGE WOULD SHOW, read off this server, writing nothing.
#
# WHY THIS EXISTS. `/pricing` renders `BillingPlan.active.ordered.where(listed_on_website: true)`. Three
# different states look identical from a browser -- no plan rows at all, plan rows that are inactive, and
# plan rows that are active but not ticked for the website -- and all three render the same page. This
# prints which one it is, per plan, so the question is answered from the server rather than guessed from the
# page. It is the same shape as `whatsapp:diagnose`: read-only, safe on production, run by an operator.
#
#   bundle exec rails pricing:diagnose
#
# PRICES ARE PRINTED FOR PUBLISHED PLANS ONLY. A plan an operator has ticked for the website is a public
# offering and its price is already on the page. A plan they have NOT ticked may be a negotiated rate, a
# migration tier or an experiment, so this prints its name, its flags and the reason it is not published --
# and never its price. The output of this task ends up in terminal scrollback, a ticket or a screenshot.
#
# IT WRITES NOTHING. No plan is created, activated or listed by running it. Publishing a plan is a decision
# made in Super Admin, by a person, on purpose.
namespace :pricing do
  desc 'Report which billing plans the public pricing page would publish, and why. Read-only.'
  task diagnose: :environment do
    plans = BillingPlan.order(:position, :id).to_a
    published = BillingPlan.active.ordered.where(listed_on_website: true).to_a

    puts "billing plans on this server: #{plans.length}"
    puts "the pricing page would publish: #{published.length}"
    puts

    if plans.empty?
      puts 'There are no BillingPlan rows at all. The pricing page falls back to its quote form, which is'
      puts 'what it is designed to do -- no plan is invented to fill the space. Create plans in Super Admin'
      puts 'under Billing plans, then tick "Listed on website" on the ones that are a public offering.'
      next
    end

    plans.each do |plan|
      reasons = []
      reasons << 'not active' unless plan.active?
      reasons << 'not ticked "Listed on website"' unless plan.listed_on_website?

      state = reasons.empty? ? 'PUBLISHED' : "withheld: #{reasons.join(' and ')}"
      # The price goes with a plan that is already public, and with no other.
      money = reasons.empty? ? "#{plan.currency.to_s.upcase} #{format('%.2f', plan.price)} / #{plan.interval}" : '(not shown)'

      puts format('  #%<id>-4d %<name>-28s %<state>-48s %<money>s',
                  id: plan.id, name: plan.name.to_s.truncate(28), state: state, money: money)
      puts "        pricing: #{plan.pricing_type}   limits: #{plan.limits.presence || 'none'}   " \
           "features: #{plan.features.length}   subscriptions: #{plan.subscriptions.count}"
    end

    puts

    # A PLAIN CONDITIONAL, and `return` would be a bug rather than a style choice. A task's body is a block,
    # not a method, so `return` here raises LocalJumpError -- and it raises it only once a plan is PUBLISHED,
    # which is to say on a healthy server, after the whole report has already been printed. The early exit on
    # the empty case above uses `next`, which is the one form that does work in a block.
    if published.empty?
      puts 'No plan is published, so the pricing page shows its quote form and the sections on the pricing'
      puts 'row. Nothing is wrong with the page: it is reporting the truth about this installation.'
    end
  end
end
