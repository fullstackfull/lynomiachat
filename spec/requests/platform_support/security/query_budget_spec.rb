require 'rails_helper'
require_relative 'platform_support_contract_stub'

# THE TENANT LIST AND THE STAFF QUEUE MUST BE FLAT IN QUERY COUNT AS TICKETS GROW.
#
# The repository's existing `count_queries` idiom (spec/services/operations/overview_query_budget_spec.rb,
# commerce_operations_spec.rb, channel_matrix_spec.rb): measure a small set, measure a larger one, and assert
# the second did not pay per row. A support list is exactly where an N+1 hides, because every row wants its
# account, its plan and its message count.
#
# Nothing in a ticket row may reach a provider or an external API either -- asserted by running the whole
# measurement with HTTP disabled, which WebMock already does for the suite, plus the absence of any such call
# in the code these paths run.
RSpec.describe 'Platform Support query budget', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  def seed(count)
    count.times do
      ticket = PlatformSupportContractStub.ticket!(account: account, reporter: reporter)
      ticket.messages.create!(author_type: 'User', author_name: 'A reporter', body: 'Hello')
    end
  end

  def tenant_list
    get "#{base}/tickets", headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'does not grow the tenant list query count as tickets grow' do
    administrator
    seed(3)
    baseline = count_queries { tenant_list }

    seed(12)
    grown = count_queries { tenant_list }

    expect(grown).to be <= baseline + 2
  end

  # The staff queue's own controller lives on the staff surface, so what is measured here is the RELATION the
  # contract fixes for it: the default order `(status, priority, last_activity_at DESC)` with Kaminari
  # pagination over the partial-index-backed scope. A page must cost the page, not the table.
  it 'does not grow the staff queue query count as tickets grow' do
    seed(3)
    baseline = count_queries { staff_queue_page }

    seed(12)
    grown = count_queries { staff_queue_page }

    expect(grown).to eq(baseline)
  end

  it 'paginates the staff queue for real rather than loading every row' do
    seed(9)

    page = PlatformSupport::Ticket.order(:status, :priority, last_activity_at: :desc).page(1).per(5)

    expect(page.length).to eq(5)
    expect(page.total_pages).to eq(2)
  end

  it 'makes no external request while listing' do
    seed(4)

    expect { tenant_list }.not_to raise_error
    expect(response).to have_http_status(:success)
  end

  def staff_queue_page
    PlatformSupport::Ticket.order(:status, :priority, last_activity_at: :desc)
                           .page(1).per(5)
                           .map { |ticket| [ticket.id, ticket.status, ticket.priority] }
  end

  def count_queries(only: nil)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])

      count += 1 if only.nil? || payload[:sql].include?(only)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
