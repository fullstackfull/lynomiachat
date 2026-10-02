require 'rails_helper'

# Automation actions never reach another account, and one failing action never repeats or stops the others
# (docs/automation/05-runtime-security-and-tenancy.md).
RSpec.describe AutomationRules::ActionService do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:foreign_team) { create(:team, account: other_account) }
  let(:foreign_agent) { create(:user, account: other_account, role: :administrator) }

  def rule_with(actions)
    rule = account.automation_rules.new(name: 'x', event_name: 'conversation_created', conditions: [], actions: actions)
    rule.save!(validate: false)
    rule
  end

  it 'never assigns or emails another account\'s team or agent' do
    rule = rule_with([{ 'action_name' => 'assign_team', 'action_params' => [foreign_team.id] },
                      { 'action_name' => 'assign_agent', 'action_params' => [foreign_agent.id] },
                      { 'action_name' => 'send_email_to_team', 'action_params' => [{ 'team_ids' => [foreign_team.id], 'message' => 'Look' }] }])
    create(:team_member, team: foreign_team, user: foreign_agent)

    expect(TeamNotifications::AutomationNotificationMailer).not_to receive(:conversation_creation)
    described_class.new(rule, account, conversation).perform

    expect(conversation.reload).to have_attributes(team_id: nil, assignee_id: nil)
  end

  it 'runs the next actions when one fails, and never raises' do
    rule = rule_with([{ 'action_name' => 'add_label', 'action_params' => ['vip'] },
                      { 'action_name' => 'change_priority', 'action_params' => ['high'] }])
    allow(conversation).to receive(:add_labels).and_raise(StandardError, 'boom')

    expect { described_class.new(rule, account, conversation).perform }.not_to raise_error
    expect(conversation.reload.priority).to eq('high')
  end

  it 'sends automation webhooks through the existing SSRF guard: private addresses are refused' do
    expect { WebhookJob.perform_now('http://169.254.169.254/latest/meta-data', { event: 'automation_event.commerce_order_paid' }) }
      .not_to raise_error
    expect(a_request(:any, /169\.254\.169\.254/)).not_to have_been_made
  end
end
