# A bare array: the store commits the response body straight into its records
# (app/javascript/dashboard/store/modules/customRole.js:30).
json.array! @custom_roles do |custom_role|
  json.partial! 'api/v1/accounts/custom_roles/custom_role', custom_role: custom_role
end
