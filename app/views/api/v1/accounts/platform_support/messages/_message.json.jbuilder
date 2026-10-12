# One public message in a Platform Support thread.
#
# `author_role` is `customer` or `lynomia`, and `author_name` is the literal "Lynomia Support" for every
# operator message: the individual operator's name is never serialized to a customer. The model decides both,
# so no serializer has to remember.
#
# THE ATTACHMENT OBJECTS CARRY NO URL. Download goes through GET /platform_support/attachments/:id, which
# authorizes the blob's parent record through the policy scope before streaming -- because blob URLs do not
# expire in this installation, so a signed id in a JSON response would be a permanent bearer token.
json.id message.id
json.author_role message.author_role
json.author_name message.display_author_name
json.body message.body

json.attachments do
  json.array! message.platform_support_message_files.attachments do |attachment|
    json.id attachment.id
    json.filename attachment.blob.filename.to_s
    json.byte_size attachment.blob.byte_size
    json.content_type attachment.blob.content_type
  end
end

json.created_at message.created_at.to_i
