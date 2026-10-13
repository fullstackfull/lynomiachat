require 'rails_helper'

# THE SIX PROOFS §3 REQUIRES of the first authorized ActiveStorage download in this repository.
#
# Every other blob in this installation is served by ActiveStorage's own signed-id redirect, with no policy
# check, and blob URLs here never expire -- so a leaked signed id is a permanent, account-less bearer token.
# These examples assert the opposite for this route: authorization is a PARENT LOOKUP through the ticket
# policy scope, and every miss is the same 404.
RSpec.describe 'Platform Support attachments', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:bystander) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }

  let(:ticket) { create(:platform_support_ticket, account: account, reporter: reporter) }
  let(:message) do
    ticket.messages.create!(author_type: 'User', author_id: reporter.id, author_name: 'A reporter',
                            body: 'Here is the invoice')
  end
  # A real agent row, because `agent_id` carries a foreign key; the model snapshots the name from it.
  let(:operator) { create(:platform_support_agent) }
  let(:note) do
    PlatformSupport::InternalNote.create!(ticket: ticket, agent: operator, body: 'ESCALATE-TO-INFRA')
  end

  def attach_to(record, association, filename: 'invoice.png', content_type: 'image/png')
    record.public_send(association).attach(
      io: StringIO.new('PLATFORM-SUPPORT-BLOB-BODY'), filename: filename, content_type: content_type
    )
    record.public_send(association).attachments.last
  end

  def message_attachment
    @message_attachment ||= attach_to(message, :platform_support_message_files)
  end

  def note_attachment
    @note_attachment ||= attach_to(note, :platform_support_note_files)
  end

  def download(id, as:, from: account)
    get "/api/v1/accounts/#{from.id}/platform_support/attachments/#{id}",
        headers: as.create_new_auth_token
  end

  # ---- PROOF 1: a same-account permitted user may download ----------------------------------------------
  it 'streams the file to the reporter of the ticket' do
    download(message_attachment.id, as: reporter)

    expect(response).to have_http_status(:success)
    expect(response.body).to eq('PLATFORM-SUPPORT-BLOB-BODY')
  end

  it 'streams the file to an administrator of the subject account' do
    download(message_attachment.id, as: administrator)

    expect(response).to have_http_status(:success)
  end

  # The filename and the content type come from the blob and never from a request parameter, and the
  # disposition is whatever the installation already allows inline.
  it 'names the file from the blob' do
    download(message_attachment.id, as: reporter)

    expect(response.headers['Content-Type']).to start_with('image/png')
    expect(response.headers['Content-Disposition']).to include('invoice.png')
  end

  it 'forces a download for a type the installation does not allow inline' do
    html = attach_to(message, :platform_support_message_files, filename: 'log.html', content_type: 'text/html')

    download(html.id, as: reporter)

    expect(response.headers['Content-Disposition']).to start_with('attachment')
  end

  # ---- PROOF 2: another account may not ------------------------------------------------------------------
  it '404s for an administrator of another account asking through their own account' do
    download(message_attachment.id, as: other_administrator, from: other_account)

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('PLATFORM-SUPPORT-BLOB-BODY')
  end

  # Asking through the OWNING account's path does not help: the request is refused by the account guard
  # before the attachment is looked up at all.
  it 'refuses an outsider asking through the owning account path' do
    download(message_attachment.id, as: other_administrator, from: account)

    expect(response).to have_http_status(:unauthorized)
  end

  # ---- PROOF 3: an agent who did not create the ticket may not -----------------------------------------
  it '404s for a same-account agent who did not report the ticket' do
    download(message_attachment.id, as: bystander)

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('PLATFORM-SUPPORT-BLOB-BODY')
  end

  it 'treats a custom-role holder exactly as an agent' do
    account.enable_features!('custom_roles')
    account.account_users.find_by(user: bystander)
           .update!(custom_role: create(:custom_role, account: account, permissions: ['conversation_manage']),
                    role: :agent)

    download(message_attachment.id, as: bystander.reload)

    expect(response).to have_http_status(:not_found)
  end

  # ---- PROOF 4: staff with an agent row may ------------------------------------------------------------
  #
  # The staff HTTP route is /super_admin/platform_support/attachments/:id and belongs to the staff surface,
  # so the proof available here is the half this controller is responsible for: a note's attachment is a real,
  # reachable record with a resolvable parent -- it is not orphaned, not deleted and not made unreadable --
  # and what refuses the TENANT is the parent lookup, not the blob.
  it 'keeps a note attachment intact and resolvable for the staff surface' do
    expect(note_attachment.blob.download).to eq('PLATFORM-SUPPORT-BLOB-BODY')
    expect(note_attachment.record).to eq(note)
    expect(note.ticket).to eq(ticket)
  end

  it 'leaves the staff download on its own surface, with no tenant route reaching a note' do
    expect(Api::V1::Accounts::PlatformSupport::AttachmentsController::PUBLIC_RECORD_TYPE)
      .to eq('PlatformSupport::Message')
    expect(Api::V1::Accounts::PlatformSupport::AttachmentsController.constants)
      .not_to include(:NOTE_ATTACHMENT_NAME)
  end

  # ---- PROOF 5: guessing a blob id or a signed id does not bypass ---------------------------------------
  describe 'guessing' do
    it '404s on the blob id, which is not an attachment id' do
      download(message_attachment.blob.id + 10_000, as: reporter)

      expect(response).to have_http_status(:not_found)
    end

    it '404s on a signed id' do
      download(message_attachment.blob.signed_id, as: reporter)

      expect(response).to have_http_status(:not_found)
    end

    it '404s on an attachment id that belongs to a conversation, not to this module' do
      inbox = create(:inbox, account: account)
      chat_message = create(:message, account: account, inbox: inbox,
                                      conversation: create(:conversation, account: account, inbox: inbox))
      chat_message.attachments.create!(account_id: account.id, file_type: :image)
      foreign = ActiveStorage::Attachment.where.not(name: 'platform_support_message_files').last

      download(foreign&.id || 0, as: reporter)

      expect(response).to have_http_status(:not_found)
    end

    # The response must be byte-identical whether the id is wrong, somebody else's, real-but-unauthorized,
    # or a note's -- otherwise the status itself tells the caller the row exists.
    it 'answers identically for a nonexistent id, a note and a row of another account' do
      foreign = create(:platform_support_ticket, account: other_account)
      foreign_message = foreign.messages.create!(author_type: 'User', author_id: other_administrator.id,
                                                 author_name: 'Somebody', body: 'Hi')
      foreign_attachment = attach_to(foreign_message, :platform_support_message_files)

      bodies = [0, note_attachment.id, foreign_attachment.id].map do |id|
        download(id, as: reporter)
        [response.status, response.body]
      end

      expect(bodies.uniq.length).to eq(1)
      expect(bodies.first.first).to eq(404)
    end
  end

  # ---- PROOF 6: internal-note attachments never become tenant-visible ----------------------------------
  describe 'an internal note attachment' do
    it '404s for the reporter of the very ticket it is attached to' do
      download(note_attachment.id, as: reporter)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('PLATFORM-SUPPORT-BLOB-BODY')
    end

    it '404s for an administrator of the subject account' do
      download(note_attachment.id, as: administrator)

      expect(response).to have_http_status(:not_found)
    end

    # AS A CONSEQUENCE OF THE PARENT LOOKUP, not as a special case. The tenant relation is "the files of the
    # public messages of the tickets you may see"; a note is simply not that parent type, so there is no
    # `unless note?` for a later reader to delete.
    it 'is excluded because its parent is not a PlatformSupport::Message' do
      expect(note_attachment.record_type).to eq('PlatformSupport::InternalNote')
      expect(note_attachment.name).to eq('platform_support_note_files')
      expect(PlatformSupport::Message.exists?(note_attachment.record_id)).to be(false)
    end
  end

  # ---- No serializer emits a blob URL ------------------------------------------------------------------
  # Comments are stripped first: a header stating that this partial never renders a signed id is the
  # documentation of the rule, not a violation of it. What the rule is about is what a view can EMIT.
  it 'emits no blob url from any Platform Support view' do
    views = Dir.glob(Rails.root.join('app/views/api/v1/accounts/platform_support/**/*')) +
            Dir.glob(Rails.root.join('app/views/super_admin/platform_support/**/*')) +
            Dir.glob(Rails.root.join('app/views/platform_support_mailer/**/*'))
    emitted = views.select { |path| File.file?(path) }
                   .select { |path| rendered_code(File.read(path)).match?(/rails_blob|rails_storage_proxy|signed_id|service_url/) }

    expect(emitted).to be_empty
  end

  # TWO ROUTES, one per surface, and that is the architecture rather than a leak: each authorizes the blob's
  # PARENT through its own boundary -- the tenant one through the policy scope, which has no path to an
  # internal note, and the staff one through the acting-agent guard. Neither hands out a blob URL.
  it 'reaches a blob through exactly two routes, one per authorized surface' do
    routes = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
                  .grep(%r{/platform_support/attachments})

    expect(routes).to contain_exactly('/api/v1/accounts/:account_id/platform_support/attachments/:id(.:format)',
                                      '/super_admin/platform_support/attachments/:id(.:format)')
  end

  # ERB and HTML comments, and the comment lines of a jbuilder, are not code this view can emit.
  def rendered_code(body)
    body.gsub(/<%#.*?%>/m, '').gsub(/<!--.*?-->/m, '')
        .lines.reject { |line| line.strip.start_with?('#') }.join
  end
end
