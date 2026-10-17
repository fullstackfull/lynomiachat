class AllowCampaignCancellation < ActiveRecord::Migration[7.0]
  # CANCELLATION IS A STATUS, NOT A COLUMN OF ITS OWN.
  #
  # `campaign_status` is an integer enum and `cancelled` is simply the next value, so there is
  # no migration here at all beyond this note: the enum lives in the model
  # (app/models/campaign.rb) and the column already holds any integer.
  #
  # WHY THE EMPTY MIGRATION EXISTS ANYWAY. Adding an enum value with no migration leaves no
  # record in the schema history of when the meaning of `campaign_status = 4` was decided, and
  # the next person reading a row with a 4 in it has nowhere to look. `blocked_reason` is
  # reused for the cancellation note rather than a second nullable string beside it: both
  # answer "why is this campaign not sending", and two columns answering one question is how
  # they come to disagree.
  def up
    change_column_comment :campaigns, :campaign_status,
                          '0 active, 1 completed, 2 processing, 3 blocked (capability unavailable), 4 cancelled (operator stopped it)'
  end

  def down
    change_column_comment :campaigns, :campaign_status, nil
  end
end
