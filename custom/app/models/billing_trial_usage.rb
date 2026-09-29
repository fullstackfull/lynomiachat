# frozen_string_literal: true

class BillingTrialUsage < ApplicationRecord
  before_validation { self.email = email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true
end