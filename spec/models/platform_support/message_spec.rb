require 'rails_helper'

RSpec.describe PlatformSupport::Message do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Template stuck')
  end

  it 'allows exactly three authors' do
    expect(described_class::AUTHOR_TYPES).to eq(['User', 'PlatformSupport::Agent', 'System'])
  end

  it 'refuses an author type outside the list' do
    message = ticket.messages.new(author_type: 'Contact', author_id: 1, author_name: 'X', body: 'hello')
    expect(message).not_to be_valid
    expect(message.errors[:author_type]).to be_present
  end

  describe '.author_attributes_for' do
    it 'files a tenant user as the customer, under their own name' do
      expect(described_class.author_attributes_for(reporter)).to eq(
        author_type: 'User', author_id: reporter.id, author_name: reporter.available_name
      )
    end

    it 'files a staff row as the operator, under the snapshot' do
      expect(described_class.author_attributes_for(agent)).to eq(
        author_type: 'PlatformSupport::Agent', author_id: agent.id, author_name: agent.display_name
      )
    end

    it 'files nil as the product speaking for itself, with no author id' do
      expect(described_class.author_attributes_for(nil)).to eq(
        author_type: 'System', author_id: nil, author_name: 'Lynomia Support'
      )
    end

    it 'refuses anything else rather than guessing' do
      expect { described_class.author_attributes_for(create(:contact, account: account)) }
        .to raise_error(ArgumentError, /cannot author/)
    end
  end

  describe 'what a customer is told about the author' do
    it 'names the customer themselves on their own message' do
      message = ticket.messages.create!(described_class.author_attributes_for(reporter).merge(body: 'Still broken'))

      expect([message.author_role, message.display_author_name]).to eq(['customer', reporter.available_name])
    end

    it 'names every operator message "Lynomia Support", never the individual' do
      message = ticket.messages.create!(described_class.author_attributes_for(agent).merge(body: 'Looking into it'))

      expect([message.author_role, message.display_author_name]).to eq(['lynomia', 'Lynomia Support'])
      expect(message.author_name).to eq(agent.display_name)
    end

    it 'names a system message as Lynomia as well, because from the customer side it is Lynomia speaking' do
      message = ticket.messages.create!(described_class.author_attributes_for(nil).merge(body: 'Reopened'))

      expect([message.author_role, message.display_author_name]).to eq(['lynomia', 'Lynomia Support'])
    end
  end

  describe 'the author id and the author type have to agree' do
    it 'requires an author id for a user or an agent' do
      message = ticket.messages.new(author_type: 'User', author_name: 'X', body: 'hello')
      expect(message).not_to be_valid
      expect(message.errors[:author_id]).to be_present
    end

    it 'refuses an author id on a system message' do
      message = ticket.messages.new(author_type: 'System', author_id: 7, author_name: 'X', body: 'hello')
      expect(message).not_to be_valid
      expect(message.errors[:author_id]).to be_present
    end
  end

  it 'requires a body and caps it at 10 000 characters' do
    message = ticket.messages.new(described_class.author_attributes_for(reporter).merge(body: ''))
    expect(message).not_to be_valid

    message.body = 'a' * 10_001
    expect(message).not_to be_valid
    expect(message.errors[:body]).to be_present
  end

  it 'accepts only the attachment types a complaint actually needs, and excludes archives' do
    expect(described_class::ALLOWED_CONTENT_TYPES).to eq(
      %w[image/png image/jpeg image/gif image/webp application/pdf text/plain text/csv]
    )
    expect(described_class::ALLOWED_CONTENT_TYPES.grep(/zip|x-tar|gzip/)).to be_empty
  end
end
