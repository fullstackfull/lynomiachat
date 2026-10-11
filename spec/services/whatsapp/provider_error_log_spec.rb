require 'rails_helper'

# DECISION 3. `handle_error` used to write the whole provider response body to the log. These examples are the
# proof that it no longer can -- not by asserting what the line says, which a future payload could satisfy
# while still leaking, but by handing the parser bodies that CONTAIN the forbidden values and asserting they
# are not in the output.
#
# The payload shapes here are Meta's own, taken from the same reference the provider code cites:
# https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
RSpec.describe Whatsapp::ProviderErrorLog do
  let(:url) { 'https://graph.facebook.com/v23.0/123456789/messages' }

  # A real HTTParty::Response, for the reason the sibling spec gives: `parsed_response` on a hand-built double
  # proves nothing about what the provider is actually handed.
  def meta_response(body, status: 400)
    stub_request(:post, url).to_return(status: status, body: body.is_a?(String) ? body : body.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
    HTTParty.post(url)
  end

  # `error` is the error OBJECT, so the examples below read as the payload shape rather than as Ruby plumbing.
  # Deliberately keyword-free, so a bare hash at the call site arrives as the positional argument it looks like.
  def line_for(error)
    line_with_status(error, 400)
  end

  def line_with_status(error, status)
    described_class.from_response(meta_response({ error: error }, status: status))
  end

  describe 'what it keeps' do
    let(:refusal) do
      { message: '(#131030) Recipient phone number not in allowed list',
        type: 'OAuthException',
        code: 131_030,
        error_subcode: 2_655_007,
        fbtrace_id: 'Az8or2',
        error_data: { messaging_product: 'whatsapp',
                      details: 'Recipient phone number not in allowed list: Add recipient phone number to the list.' } }
    end

    it 'keeps the five named values an operator escalates with' do
      line = line_for(refusal)

      expect(line).to start_with('WHATSAPP_PROVIDER_ERROR ')
      expect(line).to include('status=400', 'class=provider_refused', 'code=131030',
                              'error_subcode=2655007', 'type=OAuthException', 'fbtrace_id=Az8or2')
    end

    it 'keeps the provider sentence, so a code is not the only thing an operator has' do
      expect(line_for(refusal)).to include('Recipient phone number not in allowed list')
    end
  end

  describe 'what it refuses to log' do
    it 'drops error_data, which is where Meta puts the sentence about this specific call' do
      line = line_for(message: 'Generic', code: 131_030,
                      error_data: { details: 'Recipient 96555512345 is not registered' })

      expect(line).not_to include('96555512345')
      expect(line).not_to include('error_data')
      expect(line).not_to include('details')
    end

    # error_user_msg and error_user_title are written for the end user and routinely name them.
    it 'drops the customer-facing message fields' do
      line = line_for(message: 'Generic', code: 131_026,
                      error_user_title: 'Message not delivered to Amal',
                      error_user_msg: 'We could not reach +965 5551 2345')

      expect(line).not_to include('Amal')
      expect(line).not_to include('5551')
      expect(line).not_to include('error_user')
    end

    it 'drops a key nobody listed, even one that looks harmless' do
      line = line_for(message: 'Generic', code: 100, trace_context: 'abc', recipient_id: '96555512345')

      expect(line).not_to include('trace_context')
      expect(line).not_to include('recipient_id')
      expect(line).not_to include('96555512345')
    end

    it 'never logs the raw body of a response it cannot parse' do
      line = described_class.from_response(meta_response('<html><body>Bearer sk-live-SECRET</body></html>', status: 502))

      expect(line).to eq('WHATSAPP_PROVIDER_ERROR status=502 class=unparseable_body')
      expect(line).not_to include('SECRET')
    end

    it 'says a body carried no error object without describing the body' do
      response = meta_response({ messages: [{ id: 'wamid.ACCEPTED' }] }, status: 200)

      expect(described_class.from_response(response)).to eq('WHATSAPP_PROVIDER_ERROR status=200 class=unparseable_body')
    end
  end

  describe 'sanitizing the one free-form value it keeps' do
    it 'removes an E.164-shaped recipient number from the provider sentence' do
      line = line_for(code: 131_030, message: 'Recipient +96555512345 is not a valid WhatsApp user')

      expect(line).not_to include('96555512345')
      expect(line).to include('[redacted]')
      expect(line).to include('is not a valid WhatsApp user')
    end

    it 'removes a spaced number too' do
      expect(line_for(code: 131_030, message: 'to 965 5551 2345 failed')).not_to include('5551')
    end

    it 'removes a dashed number too' do
      expect(line_for(code: 131_030, message: 'to 965-5551-2345 failed')).not_to include('5551')
    end

    it 'removes an email address' do
      expect(line_for(code: 100, message: 'owner amal@example.com must accept the terms')).not_to include('amal@example.com')
    end

    it 'removes a credential a provider quoted back at us' do
      line = line_for(code: 190, message: 'Invalid access_token=EAAG0ZASUPERSECRET supplied')

      expect(line).not_to include('EAAG0ZASUPERSECRET')
      expect(line).to include('access_token=[redacted]')
    end

    it 'removes a credential embedded in a URL the provider echoed' do
      expect(line_for(code: 190, message: 'request to https://user:hunter2@graph.facebook.com failed')).not_to include('hunter2')
    end

    # The boundary that makes the number pattern safe rather than a guess: Meta's own codes are three to six
    # digits and must survive, because they are what the error reference is indexed by.
    it 'leaves Meta error codes in the sentence alone' do
      line = line_for(code: 131_030, message: 'Error 131030 subcode 2655007 on this send')

      expect(line).to include('131030')
      expect(line).to include('2655007')
    end

    it 'collapses a multi-line provider error to one line' do
      expect(line_for(code: 100, message: "first line\n\tsecond line")).to include('first line second line')
    end

    it 'bounds a provider sentence so prose cannot fill the log' do
      line = line_for(code: 100, message: 'x' * 2_000)

      expect(line.length).to be < 500
      expect(line).to include('...')
    end
  end

  describe 'values that are not identifier-shaped' do
    # A code or a trace id arriving as prose is a payload shape nobody here has seen. It is dropped rather than
    # printed, because the allow-list is about the VALUE as much as the key.
    it 'drops a named field whose value is not identifier-shaped' do
      line = line_for(code: 'failed because +96555512345 was blocked', message: 'Generic')

      expect(line).not_to include('96555512345')
      expect(line).not_to include('code=')
    end

    it 'drops a named field that is a nested structure' do
      line = line_for(fbtrace_id: { nested: 'value' }, message: 'Generic')

      expect(line).not_to include('nested')
      expect(line).not_to include('fbtrace_id')
    end
  end

  describe 'classification' do
    it 'calls a 5xx a provider error rather than a refusal' do
      expect(line_with_status({ code: 1, message: 'Unknown' }, 500)).to include('class=provider_error')
    end

    it 'names the case where a 2xx body still carried a refusal' do
      expect(line_with_status({ code: 131_047, message: 'Re-engagement message' }, 200)).to include('class=provider_rejected')
    end
  end

  # The line is what reaches the log, so the integration is asserted at the point the decision is about.
  describe 'the provider base service' do
    let(:channel) do
      create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    end

    it 'logs the sanitized line and never the body' do
      body = { error: { code: 131_030, message: 'Recipient +96555512345 not in allowed list',
                        error_data: { details: 'Add +96555512345 to the list' } } }
      response = meta_response(body)
      logged = []
      allow(Rails.logger).to receive(:error) { |line| logged << line.to_s }

      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel).handle_error(response, nil)

      expect(logged).to be_present
      expect(logged.join("\n")).to include('WHATSAPP_PROVIDER_ERROR')
      expect(logged.join("\n")).to include('code=131030')
      expect(logged.join("\n")).not_to include('96555512345')
      expect(logged.join("\n")).not_to include('error_data')
    end
  end
end
