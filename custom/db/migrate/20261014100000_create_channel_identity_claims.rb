# One channel identity, one holder -- per integration, and nowhere else.
#
# THE RULE THIS SERVES IS STORE SYRIA'S, NOT LYNOMIA'S. An external platform that connects
# merchants needs "this WhatsApp number belongs to one of my stores and no other", including
# across two stores owned by the same person. Lynomia itself has never had that rule and must not
# acquire it globally: an independent Lynomia customer connecting their own number is not a
# conflict with anybody, and breaking that would be a regression for every account that does not
# come from an integration.
#
# So the registry is keyed on the PLATFORM APP. A row exists only because an integration claimed
# an identity; an account with no claim is untouched by any of this, which is every account that
# exists today.
#
# THE UNIQUE INDEX IS THE RULE, NOT A CHECK. Two merchants connecting the same number at the same
# moment both read "unclaimed" and both proceed; a check-then-write loses that race every time it
# is run often enough. The index is the arbiter and the claiming service reports the conflict.
# It is PARTIAL, over active claims only: a released claim is history and must not block the next
# holder, but it is kept rather than deleted so "who had this number in March" has an answer.
#
# IDENTITY IS NORMALIZED BEFORE IT GETS HERE. +44 20 7946 0958, 442079460958 and 00442079460958
# are one phone number; Sales@Example.COM and sales@example.com are one mailbox. Storing what the
# caller happened to type would make the index a formatting check rather than an identity one.
class CreateChannelIdentityClaims < ActiveRecord::Migration[7.2]
  def change
    create_table :channel_identity_claims do |t|
      t.bigint :platform_app_id, null: false
      t.bigint :account_id, null: false

      # The capability key from Channels::Capability -- whatsapp, instagram, facebook, email...
      # Reused rather than invented so there is one vocabulary for "which channel is this".
      t.string :provider, null: false, limit: 32

      # The normalized provider identity. Opaque to Lynomia beyond being a string.
      t.string :identity, null: false, limit: 255

      # active | released. Deliberately only two -- see ChannelIdentityClaim.
      t.string :state, null: false, limit: 32, default: 'active'

      # What the integration calls the holder on its own side -- a Store Syria store id. Carried
      # so an operator looking at a conflict can say WHICH store holds it without asking the
      # other system. Never interpreted here.
      t.string :external_owner_ref, limit: 128

      t.datetime :released_at
      t.timestamps
    end

    add_index :channel_identity_claims, [:platform_app_id, :provider, :identity],
              unique: true,
              where: "state = 'active'",
              name: 'index_channel_identity_claims_active_unique'

    add_index :channel_identity_claims, [:account_id, :state]
    add_index :channel_identity_claims, [:platform_app_id, :external_owner_ref]
  end
end
