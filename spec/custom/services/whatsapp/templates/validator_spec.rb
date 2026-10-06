require 'rails_helper'

# The structural rules Meta publishes, checked before a template is submitted so a mistake costs a keystroke
# rather than a review cycle. The template manager's controller spec already drives the common paths; these are
# the branches it does not reach, and each one is a rule whose absence would be silent -- a template that Meta
# will reject gets submitted, or one Meta would accept gets blocked.
#
# The validator never writes, so these records are deliberately unsaved: the rules are about the payload.
describe Whatsapp::Templates::Validator do
  let(:account) { create(:account) }

  def template(components, **overrides)
    Whatsapp::MessageTemplate.new({
      account: account, business_account_id: 'waba', name: 'order_update', language: 'en',
      category: 'UTILITY', parameter_format: 'POSITIONAL', components: components
    }.merge(overrides))
  end

  def body(text = 'Your order is on its way.', example: nil)
    { 'type' => 'BODY', 'text' => text, 'example' => example }.compact
  end

  def codes(record) = described_class.new(record).problems.pluck(:code)

  describe 'identity' do
    it 'accepts a template that breaks no rule' do
      validator = described_class.new(template([body]))

      expect(validator.problems).to be_empty
      expect(validator).to be_valid
    end

    it 'rejects a parameter format Meta does not offer' do
      expect(codes(template([body], parameter_format: 'MUSTACHE'))).to include('parameter_format_unsupported')
    end

    it 'accepts NAMED, which is the other format Meta does offer' do
      expect(codes(template([body], parameter_format: 'named'))).not_to include('parameter_format_unsupported')
    end
  end

  describe 'the header' do
    it 'rejects a format outside the four Meta supports, and checks nothing else about it' do
      expect(codes(template([body, { 'type' => 'HEADER', 'format' => 'CAROUSEL' }])))
        .to eq(['header_format_unsupported'])
    end

    it 'accepts a plain text header' do
      expect(codes(template([body, { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Order update' }]))).to be_empty
    end

    it 'rejects header text over sixty characters' do
      header = { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'a' * 61 }
      problems = described_class.new(template([body, header])).problems

      expect(problems).to include(a_hash_including(field: 'header', code: 'header_too_long', limit: 60))
    end

    # Meta allows exactly one variable in a header, so two is a rule of its own rather than a count check.
    it 'rejects more than one variable in a header' do
      header = { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Order {{1}} for {{2}}',
                 'example' => { 'header_text' => %w[A B] } }

      expect(codes(template([body, header]))).to include('header_too_many_variables')
    end

    it 'requires a sample value for a header variable' do
      header = { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Order {{1}}' }

      expect(codes(template([body, header]))).to include('variable_example_missing')
    end

    it 'accepts a header variable that carries its sample value' do
      header = { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Order {{1}} update',
                 'example' => { 'header_text' => ['A1234'] } }

      expect(codes(template([body, header]))).to be_empty
    end

    # A media header carries no text; what Meta needs instead is the uploaded handle.
    it 'requires an uploaded handle on a media header' do
      expect(codes(template([body, { 'type' => 'HEADER', 'format' => 'IMAGE' }]))).to eq(['header_example_missing'])
    end

    it 'accepts a media header that has one' do
      header = { 'type' => 'HEADER', 'format' => 'DOCUMENT', 'example' => { 'header_handle' => ['4::aGk='] } }

      expect(codes(template([body, header]))).to be_empty
    end
  end

  describe 'buttons' do
    def buttons(list) = { 'type' => 'BUTTONS', 'buttons' => list }

    it 'rejects a phone number over twenty characters' do
      button = { 'type' => 'PHONE_NUMBER', 'text' => 'Call us', 'phone_number' => "+#{'9' * 20}" }
      problems = described_class.new(template([body, buttons([button])])).problems

      expect(problems).to include(a_hash_including(field: 'buttons.0', code: 'button_phone_too_long', limit: 20))
    end

    it 'accepts a phone number within it' do
      button = { 'type' => 'PHONE_NUMBER', 'text' => 'Call us', 'phone_number' => '+96512345678' }

      expect(codes(template([body, buttons([button])]))).to be_empty
    end

    it 'requires a coupon code on a copy-code button' do
      button = { 'type' => 'COPY_CODE', 'text' => 'Copy code' }

      expect(codes(template([body, buttons([button])]))).to eq(['button_example_missing'])
    end

    # Held at 15 rather than Meta's 20 on purpose: the send path still refuses anything longer, so a template
    # authored up to 20 would be created at Meta and fail to send.
    it 'rejects a coupon code longer than the send path accepts' do
      button = { 'type' => 'COPY_CODE', 'text' => 'Copy code', 'example' => 'A' * 16 }
      problems = described_class.new(template([body, buttons([button])])).problems

      expect(problems).to include(a_hash_including(field: 'buttons.0', code: 'button_copy_code_too_long', limit: 15))
    end

    it 'accepts a coupon code at that limit' do
      button = { 'type' => 'COPY_CODE', 'text' => 'Copy code', 'example' => 'A' * 15 }

      expect(codes(template([body, buttons([button])]))).to be_empty
    end
  end

  describe 'named variables' do
    let(:named) { { parameter_format: 'NAMED' } }

    it 'rejects a name that is not lowercase letters, digits and underscores' do
      example = { 'body_text_named_params' => [{ 'param_name' => 'Customer', 'example' => 'Sara' }] }

      expect(codes(template([body('Hello {{Customer}}', example: example)], **named))).to include('variable_name_invalid')
    end

    it 'rejects the same name used twice' do
      text = 'Hello {{name}}, your order {{name}} is ready'
      example = { 'body_text_named_params' => [{ 'param_name' => 'name', 'example' => 'Sara' }] }

      expect(codes(template([body(text, example: example)], **named))).to include('variable_duplicated')
    end

    it 'accepts a well-formed named variable with its sample value' do
      text = 'Hello {{customer_name}}, your order is ready'
      example = { 'body_text_named_params' => [{ 'param_name' => 'customer_name', 'example' => 'Sara' }] }

      expect(codes(template([body(text, example: example)], **named))).to be_empty
    end
  end

  # Found while writing these: a variable at the very start or end of the text is refused in its own right, which
  # is why every example above keeps its variables inside a sentence.
  describe 'a variable at the edge of the text' do
    it 'is refused at the end' do
      expect(codes(template([body('Your order is {{1}}', example: { 'body_text' => [['ready']] })])))
        .to include('variable_at_edge')
    end

    it 'is refused at the start' do
      expect(codes(template([body('{{1}} is on its way', example: { 'body_text' => [['Your order']] })])))
        .to include('variable_at_edge')
    end

    it 'is accepted inside a sentence' do
      expect(codes(template([body('Your order {{1}} is on its way', example: { 'body_text' => [['A1']] })]))).to be_empty
    end
  end

  # Meta nests body samples one level deeper than header samples, and reading the wrong shape would report a
  # missing example for a template that has one.
  describe 'positional sample values' do
    it 'reads a body sample out of its nested array' do
      record = template([body('Hello {{1}}, your order is ready', example: { 'body_text' => [['Sara']] })])

      expect(codes(record)).to be_empty
    end

    it 'still reads a flat body sample' do
      record = template([body('Hello {{1}}, your order is ready', example: { 'body_text' => ['Sara'] })])

      expect(codes(record)).to be_empty
    end

    it 'reports the sample as missing when fewer are given than the text needs' do
      record = template([body('Hello {{1}}, order {{2}} is ready', example: { 'body_text' => [['Sara']] })])

      expect(codes(record)).to include('variable_example_missing')
    end
  end
end
