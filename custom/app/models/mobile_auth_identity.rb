# frozen_string_literal: true

class MobileAuthIdentity < ApplicationRecord
  PROVIDERS = %w[google apple].freeze

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }
end