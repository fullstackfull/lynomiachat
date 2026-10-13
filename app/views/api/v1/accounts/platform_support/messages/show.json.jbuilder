json.payload do
  json.partial! 'api/v1/accounts/platform_support/messages/message', message: @message
end
