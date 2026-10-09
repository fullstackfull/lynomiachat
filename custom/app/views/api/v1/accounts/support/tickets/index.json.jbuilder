json.meta do
  json.current_page @tickets.current_page
  json.total_entries @tickets.total_count
  json.per_page @tickets.limit_value
  json.counts @counts
end

json.payload do
  json.array! @tickets do |ticket|
    json.partial! 'api/v1/accounts/support/tickets/ticket', ticket: ticket
  end
end
