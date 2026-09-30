require_relative 'lib'
FakeGraph.reset!(wabas: { 'WABA-A' => { name: 'A', numbers: [{ id: '1110001', display: '+1 555-000-1001' }] } })
ch = Channel::Whatsapp.find_by(phone_number: '+15550001001')
orig = ch.phone_number_health_error
ch.update_columns(phone_number_health_error: 'x' * 300)
ch.reload
ch.provider_config = ch.provider_config.merge('lynomia_probe' => '1')
ok = ch.valid?
puts "validated save with 300-char health error: #{ok ? 'OK' : "FAILS: #{ch.errors.full_messages.join(', ')}"}"
ch.update_columns(phone_number_health_error: orig)
