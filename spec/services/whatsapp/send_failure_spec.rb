require 'rails_helper'

# The send side of package E (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md §4.4,
# plan scenario E-8). A campaign send carries no `Message`, so upstream's refusal handling returns before it
# records anything and Meta's diagnosis reaches the log and nowhere else -- while the recipient list's reason
# column is the only view an operator has of it. Two things have to hold for that column to be fillable: the
# refusal has to be readable in its parts, and it has to still be reachable once the send call has returned.
RSpec.describe Whatsapp::SendFailure do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:messages_url) { "https://graph.facebook.com/#{Whatsapp::FacebookApiClient::DEFAULT_API_VERSION}/123456789/messages" }
  let(:response_headers) { { 'Content-Type' => 'application/json' } }
  let(:template_info) { { name: 'test_no_params_template', namespace: 'test_namespace', lang_code: 'en', parameters: [] } }

  # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response -- the shape
  # Meta answers a rejected send with. `error_data.details` is the sentence about this call; `message` is the
  # generic one the error type carries.
  let(:meta_refusal) do
    { error: { message: '(#131030) Recipient phone number not in allowed list',
               type: 'OAuthException',
               code: 131_030,
               error_data: { messaging_product: 'whatsapp',
                             details: 'Recipient phone number not in allowed list: Add recipient phone number to the list.' },
               error_subcode: 2_655_007,
               fbtrace_id: 'Az8or2' } }
  end

  # A real HTTParty::Response, because `parsed_response` on a hand-built double proves nothing about what the
  # provider is actually handed.
  def meta_response(body)
    stub_request(:post, messages_url).to_return(status: 400, body: body.to_json, headers: response_headers)
    HTTParty.post(messages_url)
  end

  describe '.from_response' do
    # Package D stores the code and the reason in two columns, so the joined "<code>: <title>" string upstream
    # composes for a Message is not enough here: the parts have to arrive as parts.
    it 'yields the code separately from the human reason' do
      failure = described_class.from_response(meta_response(meta_refusal))

      expect(failure).to have_attributes(
        code: '131030',
        title: 'Recipient phone number not in allowed list: Add recipient phone number to the list.',
        message: '(#131030) Recipient phone number not in allowed list',
        present?: true
      )
    end

    it 'falls back to the generic message when Meta sends no per-call detail' do
      failure = described_class.from_response(meta_response(error: { message: 'Message undeliverable', code: 131_026 }))

      expect(failure).to have_attributes(code: '131026', title: 'Message undeliverable', message: 'Message undeliverable')
    end

    it 'reads no refusal out of a body that carries none' do
      expect(described_class.from_response(meta_response(messages: [{ id: 'wamid.ACCEPTED' }]))).to be_nil
    end

    # A proxy or a gateway answers HTML, and a refusal that cannot be read is not a refusal that may be invented.
    it 'reads no refusal out of a body that is not a Meta error object' do
      stub_request(:post, messages_url).to_return(status: 502, body: '<html>Bad Gateway</html>')

      expect(described_class.from_response(HTTParty.post(messages_url))).to be_nil
    end
  end

  describe '.from_exception' do
    # A send that never reached Meta has no code and no title, and package D's reason chain
    # (error_message -> error_title -> error_code) tolerates having only the message.
    it 'still yields a usable reason when there is no response at all' do
      failure = described_class.from_exception(Errno::ECONNRESET.new('Connection reset by peer'))

      expect(failure).to have_attributes(code: nil, title: nil, present?: true)
      expect(failure.message).to include('Connection reset by peer')
    end
  end

  it 'is not present when the provider gave nothing usable' do
    expect(described_class.new).not_to be_present
    # Whitespace is nothing. `present?` is what the send path asks before it records a refusal at all, and a
    # reason column holding a blank would read to the operator as a failure nobody could explain.
    expect(described_class.new(code: '', title: nil, message: '  ')).not_to be_present
  end

  # The obstacle §4.4 names: upstream delegates the template send straight to a freshly built provider
  # instance, so the instance -- and the refusal it just saw -- is unreachable the moment the call returns.
  describe 'a template send with no message to carry the refusal' do
    it 'leaves Meta code and reason on the channel and answers the caller nothing' do
      stub_request(:post, messages_url).to_return(status: 400, body: meta_refusal.to_json, headers: response_headers)

      expect(channel.send_template('+96512345678', template_info, nil)).to be_nil

      expect(channel.last_send_failure).to have_attributes(
        code: '131030', title: 'Recipient phone number not in allowed list: Add recipient phone number to the list.'
      )
      # Upstream's early return stays: there is no Message on this path and none may be invented for one.
      expect(Message.count).to eq(0)
    end

    it 'holds no refusal after a send Meta accepted' do
      stub_request(:post, messages_url)
        .to_return(status: 200, body: { messages: [{ id: 'wamid.ACCEPTED' }] }.to_json, headers: response_headers)

      expect(channel.send_template('+96512345678', template_info, nil)).to eq('wamid.ACCEPTED')
      expect(channel.last_send_failure).to be_nil
    end

    # One campaign run sends to every contact through the same channel object, so a refusal left over from the
    # previous contact would be recorded against the next one -- a contact marked failed for a send that worked.
    it 'does not carry one contact refusal over to the next send' do
      stub_request(:post, messages_url).to_return(
        { status: 400, body: meta_refusal.to_json, headers: response_headers },
        { status: 200, body: { messages: [{ id: 'wamid.ACCEPTED' }] }.to_json, headers: response_headers }
      )

      channel.send_template('+96512345678', template_info, nil)
      expect(channel.last_send_failure).to be_present

      expect(channel.send_template('+96587654321', template_info, nil)).to eq('wamid.ACCEPTED')
      expect(channel.last_send_failure).to be_nil
    end

    # A send that never reached Meta is a failure too, and the reason is recorded before the exception is
    # re-raised, so every existing caller still sees exactly the exception it saw before.
    it 'records a transport failure and still re-raises it' do
      stub_request(:post, messages_url).to_raise(Errno::ECONNRESET)

      expect { channel.send_template('+96512345678', template_info, nil) }.to raise_error(Errno::ECONNRESET)

      expect(channel.last_send_failure).to be_present
      expect(channel.last_send_failure.message).to be_present
    end
  end

  # §4.1: the conversation-message path must stay exactly as it was. The refusal is now also readable on the
  # channel, but what upstream wrote to the Message is unchanged -- its own joined string, from its own read of
  # the response.
  it 'still writes the refusal onto a message when the send has one' do
    message = create(:message, message_type: :outgoing, inbox: channel.inbox,
                               conversation: create(:conversation, inbox: channel.inbox), content: 'hi')
    stub_request(:post, messages_url).to_return(status: 400, body: meta_refusal.to_json, headers: response_headers)

    channel.send_template('+96512345678', template_info, message)

    expect(message.reload).to have_attributes(status: 'failed', external_error: '(#131030) Recipient phone number not in allowed list')
    expect(channel.last_send_failure.code).to eq('131030')
  end
end
