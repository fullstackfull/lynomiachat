module AccessTokenable
  extend ActiveSupport::Concern
  included do
    # THE PERSONAL TOKEN IS THE UNSCOPED ONE, and saying so is what keeps this a has_one.
    #
    # access_tokens has only a non-unique index on (owner_type, owner_id), so the table has
    # always permitted several rows per owner -- the association simply assumed one. Scoped
    # tokens minted for an integration to hold now use that room, and without this condition
    # `user.access_token` would be LIMIT 1 with no ORDER BY over a set of two: it would return
    # either row, non-deterministically, and the profile page would show the merchant somebody
    # else's credential half the time. Every pre-existing row has account_id NULL, so this
    # selects exactly the same row it always did.
    has_one :access_token, -> { where(account_id: nil) }, as: :owner, dependent: :destroy_async, inverse_of: :owner
    # Scoped tokens are destroyed with the owner too; they are not reachable through has_one.
    has_many :scoped_access_tokens, -> { where.not(account_id: nil) },
             as: :owner, class_name: 'AccessToken', dependent: :destroy_async, inverse_of: :owner
    after_create :create_access_token
  end

  def create_access_token
    AccessToken.create!(owner: self)
  end
end
