FactoryBot.define do
  factory :custom_role do
    account
    name { Faker::Name.name }
    description { Faker::Lorem.sentence }

    # Deterministic, because `permissions` is an authorization input that is now enforced server-side
    # (DECISION 1: the conversation_* capabilities narrow what a holder can read). A random sample would make
    # every spec that attaches a set and then reads a conversation pass or fail by chance. The default names
    # `conversation_manage` so the factory's own behaviour is the unrestricted one it was before enforcement;
    # a spec that cares about narrowing says so explicitly.
    permissions { %w[conversation_manage contact_manage] }
  end
end
