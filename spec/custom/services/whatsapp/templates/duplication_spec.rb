require 'rails_helper'

# Duplicating brings nothing of Meta's along, and it cannot reuse the name: Meta blocks a deleted approved
# template's name for thirty days and refuses a duplicate (name, language) outright.
describe Whatsapp::Templates::Duplication do
  let(:account) { create(:account) }
  let(:components) { [{ 'type' => 'BODY', 'text' => 'Your order {{1}} has shipped', 'example' => { 'body_text' => [['A1']] } }] }

  def remote_template(category)
    Whatsapp::MessageTemplate.create!(
      account: account, business_account_id: 'waba-1', name: 'order_shipped', language: 'en',
      category: category, parameter_format: 'POSITIONAL', components: components,
      meta_template_id: '900', meta_status: 'APPROVED'
    )
  end

  # Meta recategorised its pre-2022 categories, and a synced row can still carry one. A copy has to start in a
  # category a user may actually author, and UTILITY is the conservative choice for a draft about to be edited.
  it 'starts a copy of a recategorised template as UTILITY' do
    copy = described_class.new(remote_template('SHIPPING_UPDATE')).perform

    expect(copy.category).to eq('UTILITY')
    expect(copy).to be_valid
  end

  it 'keeps a category the user may author' do
    expect(described_class.new(remote_template('MARKETING')).perform.category).to eq('MARKETING')
  end

  it 'brings none of Meta\'s state along, and takes a new name' do
    copy = described_class.new(remote_template('UTILITY')).perform

    expect(copy.meta_template_id).to be_nil
    expect(copy.meta_status).to be_nil
    expect(copy).to be_local
    expect(copy.name).not_to eq('order_shipped')
    expect(copy.components).to eq(components)
  end
end
