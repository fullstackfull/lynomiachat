# The four meta keys are read by name by app/javascript/dashboard/store/modules/auditlogs.js:40-45.
json.audit_logs do
  json.array! @query.entries do |entry|
    json.partial! 'api/v1/accounts/audit_logs/audit_log', entry: entry, disclosure: @disclosure
  end
end

json.total_entries @query.total_entries
json.per_page @query.per_page
json.current_page @query.current_page
