json.payload do
  json.array! @sla_policies do |sla_policy|
    json.partial! 'api/v1/accounts/support/sla_policies/sla_policy', sla_policy: sla_policy
  end
end
