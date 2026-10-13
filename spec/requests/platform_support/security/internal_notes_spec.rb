require 'rails_helper'

# INTERNAL-NOTE SECRECY, END TO END.
#
# Secrecy here is structural, not a predicate: notes are a SEPARATE TABLE, so there is no `visibility` flag
# anybody could forget, no tenant route whose controller could render one, and no association reachable from a
# tenant-visible object. The existence of a note is hidden too -- `internal_note_added` is excluded from the
# 7-of-18 customer-visible event allow-list -- and so is its attachment, because its parent class is not the
# one the tenant attachment relation resolves.
#
# Every assertion below reads the RAW response body, so it holds however the payload is composed.
RSpec.describe 'Platform Support internal note secrecy', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:ticket) { create(:platform_support_ticket, account: account, reporter: reporter) }

  # The secret only ever lives in the note.
  let(:secret) { 'SUB-ETHA-SENS-O-MATIC' }
  # A real agent row, because `agent_id` carries a foreign key; the model snapshots the name from it.
  let(:operator) { create(:platform_support_agent) }
  let!(:note) { PlatformSupport::InternalNote.create!(ticket: ticket, agent: operator, body: secret) }

  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  def as(user, verb, path)
    public_send(verb, path, headers: user.create_new_auth_token, as: :json)
  end

  it 'leaks nothing on any tenant route, for either role' do
    paths = ["#{base}/tickets", "#{base}/tickets/#{ticket.id}", "#{base}/tickets/#{ticket.id}/messages",
             "#{base}/tickets/#{ticket.id}/events"]

    [administrator, reporter].each do |user|
      paths.each do |path|
        as(user, :get, path)
        expect(response.body).not_to include(secret), "#{path} leaked the note body to #{user.id}"
        expect(response.body).not_to include('internal_note')
      end
    end
  end

  # No tenant route exists whose controller could render one -- not a filtered one, not a 403 one, none.
  # The TENANT tree only. `/super_admin/platform_support/tickets/:id/note` is the staff surface's own writer,
  # behind `authenticate_super_admin!` and an active agent row, and it is where notes are supposed to live.
  it 'declares no tenant route that names a note' do
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
                 .grep(%r{\A/api/v1/accounts/:account_id/platform_support/})

    expect(paths.grep(/note/)).to be_empty
  end

  # Comment lines are stripped first: a serializer header listing `internal_notes` among the keys it
  # deliberately omits is the documentation of this rule, not a breach of it.
  it 'exposes no tenant serializer key for one' do
    views = Dir.glob(Rails.root.join('app/views/api/v1/accounts/platform_support/**/*'))
               .select { |path| File.file?(path) }
    offenders = views.select do |path|
      File.readlines(path).reject { |line| line.strip.start_with?('#') }.join.match?(/internal_note|InternalNote/)
    end

    expect(offenders).to be_empty
  end

  # Its EXISTENCE is hidden as well: the event type is absent from the positive allow-list.
  it 'produces no customer-visible event' do
    PlatformSupport::Event.create!(platform_support_ticket_id: ticket.id, event_type: 'internal_note_added',
                                   actor_type: 'PlatformSupport::Agent', actor_id: 1, actor_name: 'An operator')

    as(reporter, :get, "#{base}/tickets/#{ticket.id}/events")

    expect(response.parsed_body['payload']).to be_empty
    expect(PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES).not_to include('internal_note_added')
  end

  it 'produces no notification of any kind' do
    expect(Notification.where(primary_actor: ticket)).to be_empty
    expect(Notification::NOTIFICATION_TYPES.keys.map(&:to_s).grep(/note/)).to be_empty
  end

  # The attachment half, which the parent lookup refuses rather than a flag.
  it '404s a note attachment for every tenant request' do
    note.platform_support_note_files.attach(io: StringIO.new(secret), filename: 'escalation.txt',
                                            content_type: 'text/plain')
    attachment = note.platform_support_note_files.attachments.last

    [administrator, reporter].each do |user|
      as(user, :get, "#{base}/attachments/#{attachment.id}")
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(secret)
    end
  end

  # A separate table, so secrecy is not a predicate that can be forgotten.
  it 'keeps notes in their own table with no visibility flag to forget' do
    expect(PlatformSupport::InternalNote.column_names).not_to include('visibility', 'private', 'public')
    expect(PlatformSupport::Message.column_names).not_to include('visibility', 'private')
  end
end
