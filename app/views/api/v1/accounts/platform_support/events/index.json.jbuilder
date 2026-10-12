json.payload do
  json.array! @events do |event|
    json.partial! 'api/v1/accounts/platform_support/events/event', event: event
  end
end
