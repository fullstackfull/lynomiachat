require 'rails_helper'

# THE GUARD THAT INVERTED (blocker B10).
#
# Three seeders asked `ENV.fetch('ENABLE_ACCOUNT_SEEDING', !Rails.env.production?)`. `ENV.fetch`
# returns a STRING when the variable is set and every non-empty String is truthy in Ruby, so
# `ENABLE_ACCOUNT_SEEDING=false` -- set by an operator trying to DISABLE seeding -- enabled it.
# Seeders::AccountSeeder then calls destroy_all on the account's teams, conversations, labels,
# inboxes, contacts and custom roles.
#
# The default path was always correct, which is why nobody hit it: the only way to reach the
# bug was to try to be careful.
RSpec.describe Custom::SeedingPermission do
  # ONE LIST, because every one of these must produce the same answer and the reasons only
  # differ in how they got there.
  #
  #   false / 0 / f / off    what an operator writes to switch seeding OFF. `ENV.fetch`
  #                          returned these as Strings and every non-empty String is truthy in
  #                          Ruby, so the old guard read them as ON.
  #   flase / yes please     Rails' own `ActiveModel::Type::Boolean` casts anything outside a
  #                          fixed false-set to TRUE, so a typo would have enabled seeding by
  #                          a different route. In front of destroy_all, a value nobody can
  #                          interpret is a refusal.
  #   '' / '  '              set, and saying nothing.
  describe 'values that must refuse' do
    ['false', '0', 'f', 'off', 'flase', 'yes please', '', '  '].each do |value|
      it "refuses on #{value.inspect}" do
        with_modified_env ENABLE_ACCOUNT_SEEDING: value do
          expect(described_class.allowed?).to be(false)
        end
      end
    end
  end

  describe 'values that must allow' do
    %w[true 1 t on yes y TRUE True].each do |value|
      it "allows on #{value.inspect}" do
        with_modified_env ENABLE_ACCOUNT_SEEDING: value do
          expect(described_class.allowed?).to be(true)
        end
      end
    end
  end

  describe 'unset, which is the path that was always right' do
    it 'allows outside production' do
      with_modified_env ENABLE_ACCOUNT_SEEDING: nil do
        expect(described_class.allowed?).to be(true)
      end
    end

    it 'refuses in production' do
      with_modified_env ENABLE_ACCOUNT_SEEDING: nil do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        expect(described_class.allowed?).to be(false)
      end
    end
  end

  # The refusal an operator reads has to name both inputs, because the failure this replaces
  # was somebody being sure they had switched it off.
  it 'says what it saw when it refuses' do
    with_modified_env ENABLE_ACCOUNT_SEEDING: 'false' do
      expect(described_class.refusal).to include('ENABLE_ACCOUNT_SEEDING', '"false"')
    end
  end

  describe 'the seeder that destroys things' do
    it 'refuses to construct when the variable is the string false' do
      with_modified_env ENABLE_ACCOUNT_SEEDING: 'false' do
        expect { Seeders::AccountSeeder.new(account: create(:account)) }
          .to raise_error(RuntimeError, /not allowed/)
      end
    end
  end
end
