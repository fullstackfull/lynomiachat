require_relative 'lib'
FakeGraph.reset!(wabas: { 'WABA-A' => { name: 'A', numbers: [{ id: '1110001', display: '+1 555-000-1001' }] } })
id = "wamid.UNSIGNED-#{Time.now.to_i}"
body = H.inbound('WABA-A', '1110001', '15550001001', from: '15557779999', id: id, type: 'text', content: { body: 'unsigned' }).to_json
H.session.post('/webhooks/whatsapp/+15550001001', params: body, headers: { 'CONTENT_TYPE' => 'application/json' })
puts "manual Cloud API number, NO signature: http=#{H.session.response.status} message_created=#{Message.exists?(source_id: id)}"
id2 = "wamid.UNSIGNED2-#{Time.now.to_i}"
body2 = H.inbound('WABA-B', '2220001', '15550002001', from: '15557779999', id: id2, type: 'text', content: { body: 'unsigned' }).to_json
H.session.post('/webhooks/whatsapp/+15550002001', params: body2, headers: { 'CONTENT_TYPE' => 'application/json' })
puts "embedded-signup number, NO signature: http=#{H.session.response.status} message_created=#{Message.exists?(source_id: id2)}"
