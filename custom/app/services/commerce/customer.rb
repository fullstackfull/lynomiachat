# A store customer as found by a provider: the candidate shape the matcher compares and agents choose from.
# `emails` are downcased and `phones` are E.164, so matching is an exact comparison.
Commerce::Customer = Data.define(:external_id, :name, :emails, :phones, :registered)
