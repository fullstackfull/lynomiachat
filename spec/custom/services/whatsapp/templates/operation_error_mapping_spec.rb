require 'rails_helper'

# What a Graph refusal becomes for the person who caused it. The manager shows a code and, where Meta itself wrote
# something for a person to read, that sentence -- never a token, a header or a raw body, which go to the log
# instead. The mapping is shared by every operation that talks to Meta (Whatsapp::Templates::Operation#mapped);
# these cases reach it through the two that the controller spec does not: an edit and a delete.
describe Whatsapp::Templates::Operation do
  let(:account) { create(:account) }
  # The channel factory fixes the WABA itself, so the template has to agree with it rather than the other way round.
  let(:waba_id) { '123456789' }
  let!(:channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                              provider: 'whatsapp_cloud', message_templates: [])
  end
  let!(:template) do
    channel
    Whatsapp::MessageTemplate.create!(
      account: account, business_account_id: waba_id, name: 'order_update', language: 'en', category: 'UTILITY',
      parameter_format: 'POSITIONAL', meta_template_id: '555', meta_status: 'APPROVED',
      components: [{ 'type' => 'BODY', 'text' => 'Your order {{1}} is ready', 'example' => { 'body_text' => [['A1']] } }]
    )
  end
  let(:edit_url) { 'https://graph.facebook.com/v24.0/555' }

  def edit!
    Whatsapp::Templates::Revision.new(template, { components: template.components }).perform
  end

  def refuse(status, body)
    stub_request(:post, edit_url).to_return(status: status, body: body.to_json,
                                            headers: { 'Content-Type' => 'application/json' })
  end

  def graph_error(**attributes)
    { error: { message: 'Something went wrong', fbtrace_id: 'Atrace' }.merge(attributes) }
  end

  it 'reports a name Meta already holds in that language as NAME_TAKEN' do
    refuse(400, graph_error(code: 100, error_subcode: described_class::DUPLICATE_NAME_SUBCODE))

    expect { edit! }.to(raise_error { |error| expect(error.code).to eq('NAME_TAKEN') })
  end

  it 'reports a token Meta no longer accepts as AUTH_INVALID' do
    refuse(401, graph_error(code: described_class::OAUTH_ERROR_CODE))

    expect { edit! }.to(raise_error { |error| expect(error.code).to eq('AUTH_INVALID') })
  end

  it 'reports a throttled request as RATE_LIMITED, which is a wait rather than a fault' do
    refuse(429, graph_error(code: 4))

    expect { edit! }.to(raise_error { |error| expect(error.code).to eq('RATE_LIMITED') })
  end

  it 'reports Meta being down as META_UNAVAILABLE rather than as the template being wrong' do
    refuse(503, graph_error(code: 1))

    expect { edit! }.to(raise_error { |error| expect(error.code).to eq('META_UNAVAILABLE') })
  end

  # Everything else is Meta refusing this particular request, and the only part worth showing is the sentence Meta
  # wrote for an end user.
  it 'passes through what Meta wrote for a person to read' do
    refuse(400, graph_error(code: 100, error_user_msg: 'The footer may not contain a variable.'))

    expect { edit! }.to(raise_error do |error|
      expect(error.code).to eq('META_REJECTED_REQUEST')
      expect(error.reason).to eq('The footer may not contain a variable.')
    end)
  end

  it 'shows no reason at all when Meta wrote nothing for a person' do
    refuse(400, graph_error(code: 100))

    expect { edit! }.to(raise_error do |error|
      expect(error.code).to eq('META_REJECTED_REQUEST')
      expect(error.reason).to be_nil
    end)
  end

  # The message is what a log line and an API response carry, so it must not grow a token or a raw body.
  it 'keeps the raw Graph body out of the error a caller sees' do
    refuse(400, graph_error(code: 100, error_user_msg: 'Rejected', fbtrace_id: 'AsecretLookingTrace'))

    expect { edit! }.to(raise_error do |error|
      expect(error.message).to eq('META_REJECTED_REQUEST: Rejected')
      expect(error.as_json).to eq({ code: 'META_REJECTED_REQUEST', reason: 'Rejected' })
    end)
  end

  # The edit failed, so the local row must still describe what Meta holds rather than the attempted change.
  it 'leaves the template as it was when Meta refuses the edit' do
    refuse(400, graph_error(code: 100))
    original = template.meta_status

    expect { Whatsapp::Templates::Revision.new(template, { category: 'MARKETING' }).perform }.to raise_error(StandardError)
    expect(template.reload.meta_status).to eq(original)
    expect(template.category).to eq('UTILITY')
  end

  it 'maps a refusal on delete the same way' do
    template.update!(meta_status: 'REJECTED')
    stub_request(:delete, %r{graph\.facebook\.com/v24\.0/#{waba_id}/message_templates})
      .to_return(status: 500, body: graph_error(code: 2).to_json, headers: { 'Content-Type' => 'application/json' })

    expect { Whatsapp::Templates::Removal.new(template).perform }
      .to(raise_error { |error| expect(error.code).to eq('META_UNAVAILABLE') })
    expect(Whatsapp::MessageTemplate.exists?(template.id)).to be(true)
  end
end
