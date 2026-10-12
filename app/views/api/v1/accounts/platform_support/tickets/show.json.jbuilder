json.payload do
  json.partial! 'api/v1/accounts/platform_support/tickets/ticket', ticket: @ticket, totals: @totals
end
