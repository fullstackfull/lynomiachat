json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/accounts/platform_support/messages/message', message: message
  end
end
