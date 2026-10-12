require 'rails_helper'

# Package A -- the audit trail's read surface (docs/p-final/clean-room/specs/A-audit-trail-read.md, acceptance
# plan section A).
#
# Everything below is asserted through GET /api/v1/accounts/:account_id/audit_logs, because that request is the
# whole of the product surface: the shipped settings page is its only caller and the browser reads the response
# by key name (app/javascript/dashboard/store/modules/auditlogs.js, helper/auditlogHelper.js).
#
# Rows are planted with Custom::AuditLog.create! rather than driven through package B's writers. This file is
# about what the page returns for a row that is already in the store -- including rows no current writer would
# produce: a machine actor, a subject that has since been deleted, a credential written before the scrubber.
RSpec.describe 'Audit trail', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # Creating a membership records its own entry (package B), so the trail is emptied once the fixture exists.
  # Without this, every `total_entries` below would also be counting this spec's own setup.
  before do
    account.enable_features!('audit_logs')
    admin
    Custom::AuditLog.delete_all
  end

  # There is no factory for an audit entry and there must not be one: the columns that matter differ per
  # scenario, and a default-filled row would hide which column each example is actually about.
  def plant(owner, auditable_type: 'Account', auditable_id: owner.id, **columns)
    Custom::AuditLog.create!({ associated_type: 'Account', associated_id: owner.id, action: 'update',
                               auditable_type: auditable_type, auditable_id: auditable_id }.merge(columns))
  end

  def read_trail(params = {}, as: admin, account_id: account.id)
    get "/api/v1/accounts/#{account_id}/audit_logs", params: params, headers: as.create_new_auth_token, as: :json
  end

  def rows
    response.parsed_body['audit_logs']
  end

  def row_for(entry)
    rows.find { |row| row['id'] == entry.id }
  end

  describe 'ordering, totals and paging' do
    # More entries than one page holds, so "the total is the total, not the page size" is a claim this fixture
    # can actually falsify.
    let!(:entries) { Array.new(30) { |index| plant(account, created_at: (index + 1).minutes.ago) } }

    # A-1
    it 'returns the newest entries first, with the real total, page size and page number', :aggregate_failures do
      read_trail

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('total_entries' => 30, 'per_page' => 25, 'current_page' => 1)
      expect(rows.length).to eq(25)
      expect(rows.first['id']).to eq(entries.first.id)
      expect(rows.pluck('created_at')).to eq(rows.pluck('created_at').sort.reverse)
    end

    # A-2
    it 'returns the oldest entries first when asked to sort ascending', :aggregate_failures do
      read_trail({ sort: 'asc' })

      expect(rows.first['id']).to eq(entries.last.id)
      expect(rows.pluck('created_at')).to eq(rows.pluck('created_at').sort)
      # The total describes the filter, not the ordering, so reversing the sort must not move it.
      expect(response.parsed_body['total_entries']).to eq(30)
    end

    # A-6
    it 'answers a page past the end with an empty list and the real total' do
      read_trail({ page: 50 })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('audit_logs' => [], 'total_entries' => 30, 'per_page' => 25,
                                         'current_page' => 50)
    end
  end

  describe 'filters' do
    # A-3
    it 'restricts both the rows and the total to the time window', :aggregate_failures do
      inside = plant(account, created_at: 3.hours.ago)
      plant(account, created_at: 3.days.ago)
      plant(account, created_at: 1.minute.ago)

      read_trail({ since: 6.hours.ago.to_i, until: 1.hour.ago.to_i })

      expect(rows.pluck('id')).to eq([inside.id])
      expect(response.parsed_body['total_entries']).to eq(1)
    end

    # A-4
    it 'restricts to one event type under either spelling the surface accepts', :aggregate_failures do
      inbox_entry = plant(account, auditable_type: 'Inbox', auditable_id: 7, action: 'create')
      membership_entry = plant(account, auditable_type: 'AccountUser', auditable_id: 9)

      # `type` is the documented parameter; `types[]` is what the shipped filter panel sends. Neither is going
      # to be changed on the other's account, so both have to mean the same thing.
      read_trail({ type: 'Inbox' })
      expect(rows.pluck('id')).to eq([inbox_entry.id])
      expect(response.parsed_body['total_entries']).to eq(1)

      read_trail({ types: ['Inbox'] })
      expect(rows.pluck('id')).to eq([inbox_entry.id])
      expect(response.parsed_body['total_entries']).to eq(1)

      # The page's "all" option is a sentinel for no restriction, not a type that nothing matches.
      read_trail({ type: 'all' })
      expect(rows.pluck('id')).to contain_exactly(inbox_entry.id, membership_entry.id)
    end

    # A-5
    it 'restricts to one actor', :aggregate_failures do
      colleague = create(:user, account: account, role: :agent)
      mine = plant(account, user: admin)
      plant(account, user: colleague)

      read_trail({ user_id: admin.id })

      expect(rows.pluck('id')).to eq([mine.id])
      expect(response.parsed_body['total_entries']).to eq(1)
    end

    # A-7
    it 'answers a non-numeric page, an unparseable bound and an unknown sort in one request', :aggregate_failures do
      entry = plant(account)

      read_trail({ page: 'first', since: 'yesterday', until: 'tomorrow', sort: 'sideways' })

      # A stale or hand-edited URL is an administrator's mistake, not an exception report: the values that
      # cannot be understood are dropped and the default page comes back.
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('per_page' => 25, 'current_page' => 1)
      expect(rows.pluck('id')).to eq([entry.id])
    end
  end

  describe 'entries the page has to survive' do
    # A-8
    it 'still returns and still attributes an entry whose actor was deleted', :aggregate_failures do
      departed = create(:user, account: account, role: :agent, display_name: 'Departed Agent',
                               email: 'departed@example.com')
      entry = plant(account, user: departed)

      departed.destroy!

      read_trail

      expect(User).not_to exist(departed.id)
      # `username` was captured when the row was written, and with the actor's own record gone it is the only
      # thing left that can say who did it.
      expect(row_for(entry)).to include('username' => 'Departed Agent', 'user_id' => departed.id,
                                        'user_type' => 'User')
    end

    # A-9
    it 'returns an entry written by a machine credential without claiming a person did it', :aggregate_failures do
      credential = create(:platform_app, name: 'Provisioning credential')
      entry = plant(account, user: credential)

      read_trail

      expect(response).to have_http_status(:success)
      # `user_type` is what says this was not a person. A reader that resolved `user_id` against `users` alone
      # would name whichever member of the account happens to hold that id.
      expect(row_for(entry)).to include('user_type' => 'PlatformApp', 'user_id' => credential.id,
                                        'username' => 'Provisioning credential')
    end

    # A-10
    it 'returns the entries of an audited record that no longer exists', :aggregate_failures do
      inbox = create(:inbox, account: account, name: 'Closed inbox')
      inbox.destroy!

      read_trail

      inbox_rows = rows.select { |row| row['auditable_type'] == 'Inbox' }
      expect(inbox_rows.pluck('action')).to contain_exactly('create', 'destroy')
      expect(inbox_rows.pluck('auditable_id')).to all(eq(inbox.id))
      # The browser tests this with `=== null`, so a vanished record has to be an explicit null rather than a
      # missing key or an empty object.
      expect(inbox_rows).to all(include('auditable' => nil))
    end
  end

  describe 'authorization' do
    # A-11
    it 'serves an administrator of the account' do
      entry = plant(account)

      read_trail

      expect(response).to have_http_status(:success)
      expect(rows.pluck('id')).to eq([entry.id])
    end

    it 'refuses an agent, and refuses an agent holding any named permission set', :aggregate_failures do
      agent = create(:user, account: account, role: :agent)
      membership = agent.account_users.find_by(account: account)

      read_trail({}, as: agent)
      expect(response).to have_http_status(:unauthorized)

      # The trail records what administrators did, and an agent who can read it sees every configuration change
      # in the account. So no package C permission may open it -- each one on its own, and all of them at once.
      # `zip` with no argument is each permission on its own; the whole vocabulary at once goes on the end.
      (CustomRole::PERMISSIONS.zip + [CustomRole::PERMISSIONS]).each do |permissions|
        membership.update!(custom_role: create(:custom_role, account: account, permissions: permissions))

        read_trail({}, as: agent)

        expect(response).to have_http_status(:unauthorized), "#{permissions.inspect} opened the trail"
      end
    end

    it 'refuses a caller with no session' do
      get "/api/v1/accounts/#{account.id}/audit_logs", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'tenant scope' do
    let(:other_account) { create(:account) }
    let(:other_admin) { create(:user, account: other_account, role: :administrator) }

    # A-12
    it '[isolation] never returns another account\'s entry under any identifier, filter, sort or page', :aggregate_failures do
      other_account.enable_features!('audit_logs')
      plant(other_account, user: other_admin, created_at: 1.minute.ago)
      mine = plant(account, user: admin, created_at: 1.minute.ago)

      # B's own trail, read as B's administrator, is the list of ids that must never appear in an answer to A.
      read_trail({}, as: other_admin, account_id: other_account.id)
      foreign_ids = rows.pluck('id')
      expect(foreign_ids).not_to be_empty

      [{}, { user_id: other_admin.id }, { since: 10.years.ago.to_i, until: 10.years.from_now.to_i },
       { sort: 'asc' }, { sort: 'desc' }, { page: 1 }, { page: 2 }, { page: 50 },
       { type: 'Account' }, { types: %w[Account AccountUser] }].each do |params|
        read_trail(params)

        expect(response).to have_http_status(:success), "#{params.inspect} answered #{response.status}"
        expect(rows.pluck('id') & foreign_ids).to be_empty, "#{params.inspect} leaked #{rows.pluck('id').inspect}"
      end

      # The scope comes from the session, so A's administrator supplying B's identifier is refused rather than
      # answered with B's trail.
      read_trail({}, account_id: other_account.id)
      expect(response).to have_http_status(:unauthorized)

      # ...and the unfiltered read is not vacuous: A's own entry really is there to be leaked.
      read_trail
      expect(rows.pluck('id')).to include(mine.id)
    end
  end

  describe 'the audit capability' do
    # A-13
    it 'answers an empty page, not an error, when the account does not have it', :aggregate_failures do
      plant(account)
      account.disable_features!('audit_logs')

      read_trail

      # The settings page renders its own "nothing to show" state from this. A refusal would instead tell an
      # administrator the product is broken.
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('audit_logs' => [], 'total_entries' => 0, 'per_page' => 25,
                                         'current_page' => 1)
    end
  end

  describe 'the originating address' do
    let(:ipv4) { '198.51.100.77' }
    let(:ipv6) { '2001:db8:aaaa:bbbb:cccc:dddd:eeee:ffff' }
    let!(:from_ipv4) { plant(account, remote_address: ipv4, created_at: 4.minutes.ago) }
    let!(:from_ipv6) { plant(account, remote_address: ipv6, created_at: 3.minutes.ago) }
    let!(:from_blank) { plant(account, remote_address: '', created_at: 2.minutes.ago) }
    let!(:from_garbage) { plant(account, remote_address: 'unknown, 10.0.0.1', created_at: 1.minute.ago) }

    # A-14, with the capability off
    it 'reduces the address to a network while the account may not see it', :aggregate_failures do
      read_trail

      expect(row_for(from_ipv4)['remote_address']).to eq('198.51.100.0/24')
      # The host octet is what identifies one machine -- and for a small team, one person -- so the stored value
      # must be nowhere in the payload, not merely absent from this field.
      expect(response.body).not_to include(ipv4)
      expect(row_for(from_ipv6)['remote_address']).to eq('2001:db8:aaaa:bbbb::/64')
      # The low 64 bits are the interface identifier, so a /64 is the smallest block that is still anonymous.
      expect(response.body).not_to include(ipv6)
      # Neither a blank nor an unparseable stored address raises; both are simply nothing to show.
      expect(row_for(from_blank)['remote_address']).to be_nil
      expect(row_for(from_garbage)['remote_address']).to be_nil
    end

    # A-14, with the capability on
    it 'returns the full address once the account has audit_log_ip_address', :aggregate_failures do
      account.enable_features!('audit_log_ip_address')

      read_trail

      expect(response).to have_http_status(:success)
      expect(row_for(from_ipv4)['remote_address']).to eq(ipv4)
      expect(row_for(from_ipv6)['remote_address']).to eq(ipv6)
      # Neither a blank nor an unparseable stored address is shown in either configuration: package A §5 makes
      # that unconditional, so the field is an address or it is null -- never whatever a proxy happened to put
      # in the header.
      expect(row_for(from_blank)['remote_address']).to be_nil
      expect(row_for(from_garbage)['remote_address']).to be_nil
    end
  end

  describe 'what an entry may disclose' do
    # A-15
    it 'renders no credential-shaped value, even from a row written before the scrubber', :aggregate_failures do
      entry = plant(account, auditable_type: 'Channel::Whatsapp', auditable_id: 4)
      # Written straight to the column: Custom::AuditLog drops these on write, so a row that predates that rule
      # is the only way to exercise the read surface's own scrubbing, which is the half this package owns.
      # rubocop:disable Rails/SkipsModelValidations
      entry.update_columns(audited_changes: { 'api_key' => %w[old-key-1a2b new-key-9f8e],
                                              'password' => 'hunter2-never-rendered',
                                              'provider_config' => { 'app_secret' => 'app-secret-7c7c',
                                                                     'phone_number_id' => '15550001111' } })
      # rubocop:enable Rails/SkipsModelValidations

      read_trail

      # Asserted against the whole body: a value that leaks through a key this spec did not think to look at is
      # still a value on an administrator's screen.
      %w[old-key-1a2b new-key-9f8e hunter2-never-rendered app-secret-7c7c].each do |planted|
        expect(response.body).not_to include(planted)
      end
      # ...and the entry is still rendered, so the assertions above are not passing on an empty page.
      expect(response.body).to include('15550001111')
      expect(row_for(entry)['audited_changes']).to eq('provider_config' => { 'phone_number_id' => '15550001111' })
    end

    # A-16
    it 'states no location for an entry', :aggregate_failures do
      account.enable_features!('audit_log_ip_address')
      entry = plant(account, remote_address: '198.51.100.77')

      read_trail

      # Lynomia resolves no locations: `city`, `country` and `country_code` exist only because the table is
      # shared with upstream, and a field here would be the first step back towards a lookup service.
      expect(row_for(entry).keys & %w[city country country_code]).to be_empty
      expect(response.body).not_to match(/city|country/i)
    end
  end

  describe 'the response shape the browser reads' do
    it 'carries every per-entry key, with the types the browser reads them as', :aggregate_failures do
      membership = admin.account_users.find_by(account: account)
      entry = plant(account, auditable_type: 'AccountUser', auditable_id: membership.id, user: admin,
                             comment: 'role changed', remote_address: '198.51.100.77',
                             audited_changes: { 'role' => [0, 1] })

      read_trail

      expect(rows.length).to eq(1)
      expect(rows.first.keys).to match_array(%w[id action auditable_type auditable_id user_id user_type username
                                                comment audited_changes created_at remote_address auditable])
      expect(rows.first).to include('id' => entry.id, 'action' => 'update', 'auditable_type' => 'AccountUser',
                                    'auditable_id' => membership.id, 'user_id' => admin.id,
                                    'user_type' => 'User', 'username' => admin.available_name,
                                    'comment' => 'role changed', 'audited_changes' => { 'role' => [0, 1] })
      # Handed to fromUnixTime in the browser, so seconds since the epoch and not an ISO-8601 string.
      expect(rows.first['created_at']).to be_an(Integer).and eq(entry.created_at.to_i)
      # The one thing disclosed about the audited record: the membership's own user, which is how the browser
      # tells a self-edit from an edit of somebody else.
      expect(rows.first['auditable']).to eq('user_id' => admin.id)
    end

    it 'keeps the meta keys and an explicit empty list on an empty page', :aggregate_failures do
      read_trail

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to match_array(%w[audit_logs total_entries per_page current_page])
      expect(response.parsed_body).to eq('audit_logs' => [], 'total_entries' => 0, 'per_page' => 25,
                                         'current_page' => 1)
    end
  end

  describe 'the cost of a page' do
    # A-17
    it 'issues a query count that does not grow with the number of entries on the page', :aggregate_failures do
      # Every entry gets its own actor and its own audited record, which is the shape that makes a per-row
      # lookup visible: resolving either one row at a time would cost one query per entry rendered.
      base = 10.hours.ago
      actors = Array.new(50) { create(:user, account: account, role: :agent) }
      Custom::AuditLog.delete_all
      actors.each_with_index do |actor, index|
        plant(account, auditable_type: 'AccountUser', auditable_id: actor.account_users.first.id,
                       user: actor, created_at: base - index.minutes)
      end
      headers = admin.create_new_auth_token

      measure = lambda do |params|
        queries = 0
        subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
          payload = args.last
          queries += 1 unless payload[:cached] || payload[:name] == 'SCHEMA'
        end
        get "/api/v1/accounts/#{account.id}/audit_logs", params: params, headers: headers, as: :json
        ActiveSupport::Notifications.unsubscribe(subscription)
        [queries, response.parsed_body['audit_logs'].length]
      end

      # The first request through a controller loads more than the page, so the comparison starts warm.
      measure.call({})
      twenty = measure.call({ since: (base - 19.minutes).to_i, until: (base + 1.minute).to_i })
      five = measure.call({ since: (base - 4.minutes).to_i, until: (base + 1.minute).to_i })

      # Both pages really were the sizes claimed, otherwise the comparison below proves nothing. Neither fills
      # a page, so neither pays for the pager's own total-count query and the only difference left is the rows.
      expect([twenty.last, five.last]).to eq([20, 5])
      expect(twenty.first).to eq(five.first)
    end
  end
end
