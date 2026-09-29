# frozen_string_literal: true

# In-process simulator of the Meta Graph API (WhatsApp Cloud API + Embedded Signup endpoints).
# Used ONLY by the Lynomia staging harness, never loaded by the app.
# Every request is recorded in FakeGraph.log so checks can assert what the app called.
require 'json'
require 'rack'
require 'securerandom'

module FakeGraph
  APP_ID = 'fake-app-id'
  PNG = ['89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4890000000D4944415478DA63F8FFFF3F0005FE02FEA7A6F7EB0000000049454E44AE426082'].pack('H*')

  class << self
    attr_accessor :wabas, :failures, :log, :seq, :run

    # wabas: { 'WABA-A' => { name:, numbers: [{ id:, display: '+1 555-000-1001', verified_name:, is_on_biz_app:, platform_type:, status:, code_verification_status: }] } }
    def reset!(wabas: {}, failures: {})
      @wabas = wabas
      @failures = failures
      @log = []
      @seq = 0
      @run = SecureRandom.hex(3)
    end

    def calls(method = nil, pattern = nil)
      log.select { |l| (method.nil? || l[:method] == method) && (pattern.nil? || l[:path].match?(pattern)) }
    end

    def call(env)
      req = Rack::Request.new(env)
      body = req.body&.read.to_s
      req.body&.rewind
      path = req.path.sub(%r{\A/v\d+(\.\d+)?}, '')
      token = req.GET['access_token'] || env['HTTP_AUTHORIZATION'].to_s.sub(/\ABearer /, '')
      log << { method: req.request_method, host: req.host, path: path, query: req.GET, body: body, token: token }
      return [200, { 'Content-Type' => 'image/png' }, [PNG]] if req.host.include?('lookaside')

      route(req.request_method, path, req.GET, body, token)
    end

    private

    def json(status, obj) = [status, { 'Content-Type' => 'application/json' }, [obj.to_json]]

    def graph_error(status, message, code: 100, subcode: nil)
      json(status, { error: { message: message, type: 'OAuthException', code: code, error_subcode: subcode, fbtrace_id: 'FAKE' }.compact })
    end

    def number_by_id(id)
      wabas.each_value { |w| w[:numbers].each { |n| return n if n[:id] == id } }
      nil
    end

    def revoked?(token) = token.to_s.include?('revoked') || failures[:revoked_tokens]&.include?(token)

    def route(method, path, query, body, token)
      return graph_error(401, 'Error validating access token: The session has been invalidated.', code: 190, subcode: 460) if revoked?(token) && path != '/debug_token'
      return graph_error(500, 'An unexpected error has occurred. Please retry your request later.', code: 2) if failures[:meta_down]

      segs = path.split('/').reject(&:empty?)
      case [method, *segs]
      in ['GET', 'oauth', 'access_token']
        code = query['code'].to_s
        return graph_error(400, 'Error validating verification code. Please make sure your redirect_uri is identical.', subcode: 36_008) if code.include?('expired') || code.include?('used')

        json(200, { access_token: "EAAG-#{code}", token_type: 'bearer' })
      in ['GET', 'debug_token']
        input = query['input_token'].to_s
        return json(200, { data: { app_id: APP_ID, is_valid: false, error: { code: 190, message: 'Session has been invalidated' } } }) if revoked?(input)

        ids = wabas.keys
        json(200, { data: { app_id: APP_ID, type: 'SYSTEM_USER', is_valid: true,
                            scopes: %w[whatsapp_business_management whatsapp_business_messaging business_management],
                            granular_scopes: [{ scope: 'whatsapp_business_management', target_ids: ids },
                                              { scope: 'whatsapp_business_messaging', target_ids: ids }] } })
      in ['GET', 'me', 'permissions']
        json(200, { data: %w[whatsapp_business_management whatsapp_business_messaging business_management].map { |p| { permission: p, status: 'granted' } } })
      in ['GET', waba_id, 'phone_numbers']
        waba = wabas[waba_id]
        return graph_error(400, "Unsupported get request. Object with ID '#{waba_id}' does not exist", subcode: 33) unless waba

        json(200, { data: waba[:numbers].map { |n| phone_payload(n) }, paging: { cursors: { before: 'a', after: 'b' } } })
      in ['GET', waba_id, 'message_templates']
        return graph_error(400, "Unsupported get request. Object with ID '#{waba_id}' does not exist", subcode: 33) unless wabas[waba_id]

        # Like Graph: a page after the last one is empty and carries no paging cursors
        return json(200, { data: [] }) if query['after'].present?

        json(200, { data: templates, paging: { cursors: { before: 'a', after: 'b' } } })
      in ['POST', waba_id, 'subscribed_apps']
        return graph_error(400, 'Webhook subscription failed (simulated)', code: 100) if failures[:subscribe]

        json(200, { success: true })
      in ['GET', waba_id, 'subscribed_apps']
        json(200, { data: [{ whatsapp_business_api_data: { id: APP_ID, name: 'Lynomia' } }] })
      in ['DELETE', waba_id, 'subscribed_apps']
        json(200, { success: true })
      in ['POST', phone_id, 'register']
        json(200, { success: true })
      in ['POST', phone_id, 'deregister']
        json(200, { success: true })
      in ['GET' | 'POST', phone_id, 'whatsapp_business_profile']
        json(200, { data: [{ about: 'Lynomia test', messaging_product: 'whatsapp' }] })
      in ['POST', phone_id, 'messages']
        return graph_error(400, '(#131030) Recipient phone number not in allowed list', code: 131_030) if failures[:send]

        self.seq += 1
        to = (JSON.parse(body) rescue {})['to'] || (JSON.parse(body) rescue {})['recipient']
        json(200, { messaging_product: 'whatsapp', contacts: [{ input: to, wa_id: to }], messages: [{ id: "wamid.FAKE-#{run}-#{seq}" }] })
      in ['POST', phone_id, 'media']
        self.seq += 1
        json(200, { id: "media-up-#{seq}" })
      in ['GET', id] if id.start_with?('media')
        json(200, { url: "https://lookaside.fbsbx.com/whatsapp_business/attachments/?mid=#{id}", mime_type: 'image/png', sha256: 'x', file_size: PNG.bytesize, id: id, messaging_product: 'whatsapp' })
      in ['POST', id]
        json(200, { success: true })
      in ['GET', id]
        if (n = number_by_id(id))
          json(200, phone_payload(n))
        elsif (w = wabas[id])
          json(200, { id: id, name: w[:name], owner_business_info: { id: w[:business_id] || "BIZ-#{id}", name: w[:name] } })
        else
          graph_error(400, "Unsupported get request. Object with ID '#{id}' does not exist", subcode: 33)
        end
      else
        log.last[:unhandled] = true
        json(200, {})
      end
    end

    def phone_payload(n)
      {
        id: n[:id], display_phone_number: n[:display], verified_name: n[:verified_name] || 'Lynomia Test',
        code_verification_status: n[:code_verification_status] || 'VERIFIED', quality_rating: 'GREEN',
        platform_type: n[:platform_type] || 'CLOUD_API', throughput: { level: n[:throughput_level] || 'STANDARD' },
        status: n[:status] || 'CONNECTED', name_status: 'APPROVED', account_mode: 'LIVE',
        is_on_biz_app: n[:is_on_biz_app] || false, messaging_limit_tier: 'TIER_1K',
        whatsapp_business_manager_messaging_limit: 'TIER_1K', last_onboarded_time: '2026-09-01T00:00:00+0000'
      }
    end

    def templates
      [{ name: 'order_update', status: 'APPROVED', category: 'UTILITY', language: 'ar', id: 't1',
         components: [{ type: 'BODY', text: 'مرحبا {{1}}، طلبك {{2}} في الطريق' }] },
       { name: 'hello_world', status: 'APPROVED', category: 'MARKETING', language: 'en_US', id: 't2',
         components: [{ type: 'BODY', text: 'Hello World' }] }]
    end
  end
end
