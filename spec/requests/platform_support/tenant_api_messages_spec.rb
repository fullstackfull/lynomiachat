require 'rails_helper'

RSpec.describe 'Platform Support tenant messages and events API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_row) { PlatformSupport::Agent.create!(user: create(:super_admin), display_name: 'Operator One') }
  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  let(:ticket) do
    PlatformSupport::TicketCreation.new(
      account: account, reporter: administrator,
      attributes: { category: 'whatsapp', subject: 'Template stuck', description: 'Pending since Sunday' }
    ).perform
  end

  let(:log_file) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('a log excerpt'), filename: 'log.txt',
                                           content_type: 'text/plain')
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'GET /tickets/:id/messages' do
    it 'returns the thread oldest first' do
      PlatformSupport::MessageCreation.new(ticket: ticket, author: agent_row, body: 'Looking into it').perform

      get "#{base}/tickets/#{ticket.id}/messages", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(payload.map { |message| message['body'] }).to eq(['Pending since Sunday', 'Looking into it'])
    end

    it 'names the customer on their own message and "Lynomia Support" on every operator message' do
      PlatformSupport::MessageCreation.new(ticket: ticket, author: agent_row, body: 'Looking into it').perform

      get "#{base}/tickets/#{ticket.id}/messages", headers: administrator.create_new_auth_token

      expect(payload.map { |message| [message['author_role'], message['author_name']] }).to eq(
        [['customer', administrator.available_name], ['lynomia', 'Lynomia Support']]
      )
      expect(response.body).not_to include('Operator One')
    end

    it 'carries exactly the message keys the contract lists' do
      get "#{base}/tickets/#{ticket.id}/messages", headers: administrator.create_new_auth_token

      expect(payload.first.keys).to match_array(%w[id author_role author_name body attachments created_at])
    end

    it 'describes an attachment without any URL, because a blob URL here never expires' do
      ticket.messages.first.platform_support_message_files.attach(log_file)

      get "#{base}/tickets/#{ticket.id}/messages", headers: administrator.create_new_auth_token

      attachment = payload.first['attachments'].first
      expect(attachment.keys).to match_array(%w[id filename byte_size content_type])
      expect(attachment).to include('filename' => 'log.txt', 'content_type' => 'text/plain')
      expect(response.body).not_to match(%r{http|signed_id|rails/active_storage})
    end

    it 'never renders an internal note in the thread' do
      PlatformSupport::NoteCreation.new(ticket: ticket, agent: agent_row, body: 'Meta ticket 4471').perform

      get "#{base}/tickets/#{ticket.id}/messages", headers: administrator.create_new_auth_token

      expect(response.body).not_to include('Meta ticket 4471')
      expect(payload.length).to eq(1)
    end

    it 'answers 404 for a ticket in another account' do
      other = create(:account)
      other_admin = create(:user, account: other, role: :administrator)

      get "#{base}/tickets/#{ticket.id}/messages", headers: other_admin.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /tickets/:id/messages' do
    it 'adds the reply and returns 201 with it' do
      post "#{base}/tickets/#{ticket.id}/messages", params: { message: { body: 'Any news?' } },
                                                    headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(payload).to include('author_role' => 'customer', 'body' => 'Any news?')
      expect(ticket.reload.last_customer_message_at).to be_present
    end

    it 'answers 422 for an empty body' do
      post "#{base}/tickets/#{ticket.id}/messages", params: { message: { body: '' } },
                                                    headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'reopens a resolved ticket rather than swallowing the customer saying it is not fixed' do
      ticket.update!(status: :resolved, resolved_at: Time.current)

      post "#{base}/tickets/#{ticket.id}/messages", params: { message: { body: 'It is not fixed' } },
                                                    headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(ticket.reload.status).to eq('open')
      expect(ticket.events.pluck(:event_type)).to include('reopened')
    end

    it 'answers 422 on a closed ticket, telling the customer to open a new one' do
      ticket.update!(status: :closed, closed_at: Time.current)

      post "#{base}/tickets/#{ticket.id}/messages", params: { message: { body: 'Hello again' } },
                                                    headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('This ticket is closed. Open a new one.')
    end

    describe 'attachments' do
      it 'attaches a blob the caller uploaded through the account-scoped endpoint' do
        post "#{base}/tickets/#{ticket.id}/messages",
             params: { message: { body: 'Here is the log', attachment_ids: [log_file.signed_id] } },
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:created)
        expect(payload['attachments'].map { |file| file['filename'] }).to eq(['log.txt'])
      end

      it 'answers 422 naming the accepted types for a type outside the allow-list' do
        archive = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('PK'), filename: 'logs.zip',
                                                         content_type: 'application/zip')

        post "#{base}/tickets/#{ticket.id}/messages",
             params: { message: { body: 'Here it is', attachment_ids: [archive.signed_id] } },
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include('application/zip', 'image/png')
      end

      it 'answers 422 for a forged or unparseable signed id rather than dropping it' do
        post "#{base}/tickets/#{ticket.id}/messages",
             params: { message: { body: 'Here it is', attachment_ids: ['not-a-signed-id'] } },
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(PlatformSupport::Message.count).to eq(1)
      end

      it 'answers 422 naming the count limit for more than five files' do
        blobs = Array.new(6) do
          ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'note.txt',
                                                 content_type: 'text/plain').signed_id
        end

        post "#{base}/tickets/#{ticket.id}/messages",
             params: { message: { body: 'Lots of files', attachment_ids: blobs } },
             headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include('5')
      end
    end
  end

  describe 'GET /tickets/:id/events' do
    it 'returns only the customer-visible types, in order' do
      PlatformSupport::MessageCreation.new(ticket: ticket, author: agent_row, body: 'Looking').perform
      PlatformSupport::TicketAssignment.new(ticket: ticket, actor: agent_row, assignee: agent_row).perform
      PlatformSupport::TicketTransition.new(ticket: ticket, actor: agent_row,
                                            attributes: { priority: 'urgent', status: 'resolved' }).perform

      get "#{base}/tickets/#{ticket.id}/events", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(payload.map { |event| event['event_type'] }).to eq(%w[created operator_replied resolved])
    end

    it 'carries exactly the event keys the contract lists, with no metadata' do
      get "#{base}/tickets/#{ticket.id}/events", headers: administrator.create_new_auth_token

      expect(payload.first.keys).to match_array(%w[id event_type actor_name created_at])
    end

    it 'names the customer on their own action and nobody on an operator action' do
      PlatformSupport::MessageCreation.new(ticket: ticket, author: agent_row, body: 'Looking').perform

      get "#{base}/tickets/#{ticket.id}/events", headers: administrator.create_new_auth_token

      actors = payload.to_h { |event| [event['event_type'], event['actor_name']] }
      expect(actors).to eq('created' => administrator.available_name, 'operator_replied' => nil)
      expect(response.body).not_to include('Operator One')
    end

    it 'never reveals that an internal note was written' do
      PlatformSupport::NoteCreation.new(ticket: ticket, agent: agent_row, body: 'Internal').perform

      get "#{base}/tickets/#{ticket.id}/events", headers: administrator.create_new_auth_token

      expect(payload.map { |event| event['event_type'] }).to eq(['created'])
    end
  end
end
