# What this contact said when asked. `csat_survey_responses` carries an indexed `contact_id`, so this is one of
# the few sources that needs no join to reach the contact -- but it is still filtered to the conversations the
# caller may see, so a restricted agent cannot read a rating left in an inbox they have no access to.
class Contacts::ActivityTimeline::CsatAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'conversations'.freeze

  def fetch(limit)
    rows(limit).map do |response|
      Contacts::ActivityTimeline::Entry.new(
        source: source, record_id: response.id, category: CATEGORY, kind: 'csat_response',
        occurred_at: response.created_at, conversation_id: response.conversation_id,
        summary: response.feedback_message,
        meta: { rating: response.rating, agent_id: response.assigned_agent_id }
      )
    end
  end

  private

  def rows(limit)
    scope = CsatSurveyResponse.where(account_id: @account.id, contact_id: @contact.id,
                                     conversation_id: conversation_ids)
                              .reorder(created_at: :desc, id: :desc)
                              .limit(limit)
    cursor_scope(scope, :created_at)
  end
end
