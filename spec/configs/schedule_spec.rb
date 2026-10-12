## we had instances where after copy pasting the schedule block,
## the dev forgets to changes the schedule key,
## this would break some of the scheduled jobs with out explicit errors
require 'rails_helper'

RSpec.context 'with valid schedule.yml' do
  it 'does not have duplicates' do
    file = Rails.root.join('config/schedule.yml')
    schedule_keys = []
    invalid_line_starts = [' ', '#', "\n"]
    # couldn't figure out a proper solution with yaml.parse
    # so the rudementary solution is to read the file and parse it
    # check for duplicates in the array
    File.open(file).each do |f|
      f.each_line do |line|
        next if invalid_line_starts.include?(line[0])

        schedule_keys << line.split(':')[0]
      end
    end
    # ensure that no duplicates exist
    expect(schedule_keys.count).to eq(schedule_keys.uniq.count)
  end

  # The same class of silent failure as the duplicate key above, from the other direction. Nothing
  # constantizes `class:`, and the sidekiq-cron loader only runs under `Sidekiq.server?`
  # (config/initializers/sidekiq.rb:75) -- so a typo produces no error in web, console or CI, just a scheduled
  # job that never runs. A retention sweep or an SLA sweep that silently never runs is indistinguishable from
  # one that found nothing to do, which is why this is worth a gate.
  it 'names a job class and a queue that both exist' do
    schedule = YAML.safe_load(Rails.root.join('config/schedule.yml').read, aliases: true)
    sidekiq = ERB.new(Rails.root.join('config/sidekiq.yml').read).result
    queues = YAML.safe_load(sidekiq, aliases: true, permitted_classes: [Symbol])[:queues]

    schedule.each_value do |entry|
      expect { entry['class'].constantize }.not_to raise_error, "#{entry['class']} does not resolve"
      next if entry['queue'].blank?

      expect(queues).to include(entry['queue']), "#{entry['class']} is scheduled on the unserved queue #{entry['queue']}"
    end
  end
end
