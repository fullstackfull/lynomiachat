# B1 -- an account's settings change (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# `associated_with: :itself` because an account's owning account is the account: the gem resolves the
# association with `send`, and package A scopes the trail on `associated`, so the row has to point at the
# account it describes like every other row does.
#
# Only the fields an operator changes. `feature_flags` and `feature_flags_ext_1` are deliberately absent: a
# capability moving is already recorded, with the reason, by P11's own writers
# (custom/app/services/billing/{override_grant,feature_sync}.rb), and auditing the column here would put two
# rows on the trail for one decision. `limits` and `internal_attributes` are machine bookkeeping.
module Custom::Audit::Account
  extend ActiveSupport::Concern

  SETTINGS = %i[name locale domain support_email custom_attributes settings auto_resolve_duration status].freeze

  included do
    prepend Custom::Audit::Capture
    audited associated_with: :itself, on: [:update], only: SETTINGS
  end
end
