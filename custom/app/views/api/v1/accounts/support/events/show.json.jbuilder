json.payload do
  json.partial! 'api/v1/accounts/support/events/event', event: @event
end
