# The two orders the campaign analytics page reads its recipients in.
#
# WHY THIS IS NEEDED
#   The recipient list is `WHERE account_id = ? AND campaign_id = ? [AND status = ?] ORDER BY created_at ASC,
#   id ASC LIMIT 25 OFFSET ?`, and none of the table's existing indexes contains `created_at`. So no index can
#   produce the required order: Postgres reads every recipient of the campaign and top-N sorts it, for every
#   page -- and the page polls every five seconds while a campaign is processing, with the per-tab counts
#   forcing an unbounded count over the same filtered set. A campaign addressing tens of thousands of contacts
#   therefore sorts tens of thousands of rows per poll to show 25 of them.
#
#   Two indexes because the page has two shapes: the "All" tab filters on the campaign alone, and each state
#   tab adds `status`. A single (campaign_id, status, created_at, id) index cannot serve the unfiltered tab's
#   order, because `status` sits between the equality column and the sort columns.
#
#   `account_id` is left out of both. It is redundant with `campaign_id` -- a campaign belongs to exactly one
#   account, and the controller resolves the campaign inside `Current.account.campaigns` before it reads
#   recipients -- so including it would widen both indexes to no purpose.
#
# HOW
#   CONCURRENTLY. `campaign_recipients` is written once per recipient during a send, so an exclusive lock here
#   would stall a campaign mid-run.
#
# ROLLBACK
#   Reversible: both indexes dropped concurrently, no data involved.
class AddCampaignRecipientReadIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  PAGE_INDEX = 'index_campaign_recipients_on_campaign_and_created_at'.freeze
  STATE_PAGE_INDEX = 'index_campaign_recipients_on_campaign_status_created_at'.freeze

  def up
    unlimit_statement_timeout

    add_index :campaign_recipients, [:campaign_id, :created_at, :id],
              name: PAGE_INDEX, algorithm: :concurrently, if_not_exists: true
    add_index :campaign_recipients, [:campaign_id, :status, :created_at, :id],
              name: STATE_PAGE_INDEX, algorithm: :concurrently, if_not_exists: true
  end

  def down
    unlimit_statement_timeout

    remove_index :campaign_recipients, name: PAGE_INDEX, algorithm: :concurrently, if_exists: true
    remove_index :campaign_recipients, name: STATE_PAGE_INDEX, algorithm: :concurrently, if_exists: true
  end

  private

  def unlimit_statement_timeout
    execute("SET statement_timeout = '0'")
  end
end
