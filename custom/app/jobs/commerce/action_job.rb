# Sends one requested order action (Commerce::ActionExecutor). Never retried: a write is sent at most once, and a lost
# answer is reconciled by reading the store, not by sending again.
class Commerce::ActionJob < ApplicationJob
  queue_as :high
  sidekiq_options retry: false

  def perform(run_id)
    run = Commerce::ActionRun.find_by(id: run_id)
    Commerce::ActionExecutor.new(run).call if run
  end
end
