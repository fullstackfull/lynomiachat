# == Schema Information
#
# Table name: access_tokens
#
#  id         :bigint           not null, primary key
#  owner_type :string
#  token      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :bigint
#
# Indexes
#
#  index_access_tokens_on_owner_type_and_owner_id  (owner_type,owner_id)
#  index_access_tokens_on_token                    (token) UNIQUE
#

# A bearer credential for its owner, optionally CONFINED to one account and optionally EXPIRING.
#
# BOTH LIMITS ARE OPT-IN, AND NIL MEANS WHAT IT ALWAYS MEANT. A token with account_id nil reaches
# every account its owner is a member of, and a token with expires_at nil never lapses. That is
# the behaviour of every token this installation has ever issued -- the personal token on the
# profile page, agent bot tokens, platform app tokens -- and none of them change.
#
# The limits exist for tokens minted FOR somebody else to hold. An integration that is granted a
# merchant's workspace should be able to act in that workspace and nowhere else, and a credential
# it holds indefinitely should lapse if nobody renews it. Before these columns the only available
# credential was the owner's personal token, which carried the owner's whole membership with it.
class AccessToken < ApplicationRecord
  has_secure_token :token

  belongs_to :owner, polymorphic: true
  # optional, because the overwhelming majority of tokens are unscoped and always will be.
  belongs_to :account, optional: true

  scope :unscoped_tokens, -> { where(account_id: nil) }

  def expired?
    expires_at.present? && expires_at.past?
  end

  # What this token may act on, or nil for "anything its owner may act on".
  def account_scope_id
    account_id
  end
end
