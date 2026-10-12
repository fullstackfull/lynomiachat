# The account's audit trail (docs/p-final/clean-room/specs/A-audit-trail-read.md).
#
# `resource :audit_logs, only: [:show]` is a singular resource in config/routes.rb:84, so the whole page is one
# `show`. The shipped settings page is the only caller (app/javascript/dashboard/api/auditLogs.js).
#
# Administrator-only, through the same boundary the rest of the account's settings use. A named permission set
# does not open this page and must not: the trail records what administrators did, and an agent who can read it
# can see every configuration change in the account (package A §2, §5).
#
# An account without the `audit_logs` capability gets an empty page and a 200 rather than a refusal, so the page
# renders its own empty state instead of an error. That decision lives in AuditTrail::Query, with the scope.
class Api::V1::Accounts::AuditLogsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def show
    @query = AuditTrail::Query.new(account: Current.account, params: params)
    @disclosure = AuditTrail::Disclosure.new(Current.account)
  end
end
