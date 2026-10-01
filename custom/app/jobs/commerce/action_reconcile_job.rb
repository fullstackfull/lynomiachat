# Settles an order action whose answer was lost, or that the store completes asynchronously, by reading the store only
# (Commerce::ActionExecutor#reconcile). `stall_check` runs once after each send, to catch a worker that died mid-action.
class Commerce::ActionReconcileJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(run_id, stall_check = false) # rubocop:disable Style/OptionalBooleanParameter
    run = Commerce::ActionRun.find_by(id: run_id)
    return if run.nil?

    stall_check ? Commerce::ActionExecutor.new(run).check_stall : Commerce::ActionExecutor.new(run).reconcile
  end
end
