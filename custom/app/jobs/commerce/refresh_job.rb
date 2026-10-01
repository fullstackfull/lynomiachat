# One coalesced refresh of a linked customer's orders after a store event (Commerce::Realtime). Store errors are handled
# inside (a store answering again later is read on the next event or panel open), so the job is never retried.
class Commerce::RefreshJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(link_id)
    link = Commerce::CustomerLink.find_by(id: link_id)
    Commerce::Realtime.refresh(link) if link
  end
end
