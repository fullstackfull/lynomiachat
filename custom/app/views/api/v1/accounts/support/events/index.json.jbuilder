json.meta do
  json.current_page @current_page
  json.total_entries @total_entries
  json.per_page @per_page
end

json.payload do
  json.array! @events do |event|
    json.partial! 'api/v1/accounts/support/events/event', event: event
  end
end
