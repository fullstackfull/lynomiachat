# The record of what a one-off WhatsApp campaign did to one contact
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §4.1, §4.4).
#
# Written as the campaign runs, because a campaign's audience cannot be reconstructed afterwards: a campaign
# keeps references to labels and shared audiences, never the conditions, and membership is resolved at send
# time. A contact labelled after the send would appear in a recomputed audience and was never addressed; one
# unlabelled since would vanish although it received the message.
#
# `upsert`, not `create`: the unique index on `(campaign_id, contact_id)` is the backstop, and a re-run -- a
# retried job, an operator sending again -- has to be an update of the contact's existing row rather than an
# error that aborts the run (§4.4). So the same call serves the first run and every later one, and a contact in
# two of the campaign's labels gets one row rather than a duplicate-key error.
#
# A re-run writes the whole outcome, including the delivery timestamps as nil. That is deliberate: a re-run
# sends a NEW message with a new provider identifier, so the previous message's delivery and read times are no
# longer about anything, and leaving them would make P8 count a delivery that has not happened yet. `created_at`
# is the one column a re-run never touches, so the row stays inside the window the analytics counted it in.
#
# The skip reasons are a small closed set of fixed strings and must stay that way: P8 groups the skip breakdown
# on `error_message` directly (custom/app/services/analytics/campaigns/metrics.rb:151-155), so a reason that
# interpolated a phone number would both explode that breakdown's cardinality and put a recipient's own data
# into an analytics response.
class Campaigns::RecipientSnapshot
  NO_DESTINATION = 'No WhatsApp destination'.freeze
  AMBIGUOUS_DESTINATION = 'Multiple WhatsApp identities'.freeze
  NO_TEMPLATE_PARAMS = 'Campaign has no template parameters'.freeze
  BLANK_TEMPLATE_VARIABLES = 'Template variables resolved to blank'.freeze
  AUTHENTICATION_TEMPLATE_BLOCKED = 'Authentication template not allowed for this recipient'.freeze
  TEMPLATE_NOT_AVAILABLE = 'No approved template for this name and language'.freeze

  SKIP_REASONS = [
    NO_DESTINATION, AMBIGUOUS_DESTINATION, NO_TEMPLATE_PARAMS,
    BLANK_TEMPLATE_VARIABLES, AUTHENTICATION_TEMPLATE_BLOCKED, TEMPLATE_NOT_AVAILABLE
  ].freeze

  # Everything one send's outcome consists of. Writing all of it every time is what makes a re-run replace the
  # previous outcome rather than blend with it.
  OUTCOME_COLUMNS = %i[
    source_id status error_code error_title error_message message_content
    sent_at delivered_at read_at failed_at
  ].freeze

  # One statement per thousand contacts when the audience snapshot is seeded.
  SEED_BATCH = 1_000

  def initialize(campaign)
    @campaign = campaign
  end

  # Lynomia refused to send before any provider call. There is no timestamp to record: nothing was attempted,
  # so there is no provider event to time, and the state is the whole record of it.
  def skipped(contact, reason, message_content: nil)
    write(contact, status: :skipped, error_message: reason, message_content: message_content)
  end

  # Meta accepted the send and returned the message id that every later delivery report is matched on.
  def sent(contact, source_id:, message_content: nil)
    write(contact, status: :sent, source_id: source_id, sent_at: Time.current, message_content: message_content)
  end

  # Meta refused the send, or the call never reached it. Whatever diagnosis exists is kept in three parts,
  # because the recipient list reads the reason and the code as two separate things.
  def failed(contact, error_code: nil, error_title: nil, error_message: nil, message_content: nil)
    write(
      contact, status: :failed, failed_at: Time.current, message_content: message_content,
               error_code: error_code, error_title: error_title, error_message: error_message
    )
  end

  # The audience as it stood when the run began, written before the first provider call.
  #
  # Every rate the analytics page computes is over `audience`, which is the size of this snapshot, and the page
  # polls while a run is in progress (specification D §2). Writing a row only as each contact's turn came made
  # that denominator grow with the loop, so each poll divided by a different number -- and `queued`, which is
  # how the page words its "still processing" banner, could never be positive at all, because the only row ever
  # written already carried its outcome.
  #
  # `on_duplicate: :skip`, which `unique_by` selects: re-running a campaign that already has rows must not reset
  # an outcome already recorded. The per-contact writers above advance these rows from `queued`.
  #
  # Batched because a marketing audience is not a page: one statement per thousand contacts rather than one
  # statement of any size.
  #
  # `in_batches` and `pluck(:id)` rather than iterating the relation: a row needs nothing but the contact's id,
  # and the audience is not a cheap relation -- it resolves labels and shared audiences into a union of
  # contact queries (`Custom::CampaignAudience#audience_contacts`), which upstream's send loop then resolves
  # and iterates again on its own. Loading every Contact object here to read one integer off each would double
  # the memory a large campaign needs for nothing.
  def seed(contacts)
    contacts.in_batches(of: SEED_BATCH) do |batch|
      rows = batch.pluck(:id).map { |contact_id| queued_row(contact_id) }
      next if rows.empty?

      CampaignRecipient.insert_all(rows, unique_by: %i[campaign_id contact_id]) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def queued_row(contact_id)
    {
      account_id: @campaign.account_id, campaign_id: @campaign.id,
      contact_id: contact_id, inbox_id: @campaign.inbox_id,
      status: CampaignRecipient.statuses[:queued]
    }
  end

  # The timestamps are left to `record_timestamps`, which stamps both on an insert and only `updated_at` on a
  # conflict -- which is exactly the rule this needs, and naming `updated_at` here as well would assign the
  # column twice in one statement.
  # The validation this skips is `status` presence, and every caller above sets one; what cannot be skipped is
  # the unique index, which is the whole point of writing it this way.
  def write(contact, outcome)
    CampaignRecipient.upsert( # rubocop:disable Rails/SkipsModelValidations
      OUTCOME_COLUMNS.index_with { |column| outcome[column] }.merge(
        account_id: @campaign.account_id, campaign_id: @campaign.id,
        contact_id: contact.id, inbox_id: @campaign.inbox_id
      ),
      unique_by: %i[campaign_id contact_id],
      update_only: OUTCOME_COLUMNS + %i[inbox_id]
    )
  end
end
