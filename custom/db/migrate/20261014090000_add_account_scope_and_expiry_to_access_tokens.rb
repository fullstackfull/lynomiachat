# An access token may now be confined to ONE account, and may expire.
#
# WHY. Measured before this change: a User's personal access token reached every account that
# user belongs to. The Phase 1 account scope did not apply to it, and could not -- the scope is
# read from `users.tokens[client]`, which devise_token_auth populates, and the api_access_token
# path never sets @token, so `sso_account_scope` resolved to nil and nil means unscoped. An
# integration holding a user's token therefore held every workspace that person was in.
#
# That was safe for the Store Syria integration only BY CONSTRUCTION -- it creates one identity
# per person per workspace, so its identities are single-account. A property that holds because
# of how a caller happens to behave is not a property. This makes it hold by enforcement.
#
# BOTH COLUMNS ARE NULLABLE AND NULL MEANS "AS BEFORE". Every token that exists today keeps
# account_id NULL and expires_at NULL, so it stays unscoped and immortal and every existing
# consumer -- the profile page's personal token, agent bots, platform apps -- is untouched. The
# columns only bind tokens that are minted with them set.
class AddAccountScopeAndExpiryToAccessTokens < ActiveRecord::Migration[7.2]
  def change
    add_column :access_tokens, :account_id, :bigint, null: true
    add_column :access_tokens, :expires_at, :datetime, null: true

    # Partial, because the overwhelming majority of rows are unscoped personal tokens and an
    # index over them would be a long list of NULLs nothing ever queries.
    add_index :access_tokens, [:owner_type, :owner_id, :account_id],
              where: 'account_id IS NOT NULL',
              name: 'index_access_tokens_on_owner_and_account'
  end
end
