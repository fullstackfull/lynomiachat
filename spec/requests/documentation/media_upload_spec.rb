require 'rails_helper'

# The Super Admin upload path owner correction F1 requires. The examples that matter most are the boundary ones:
# Lynomia is the author and tenants are readers, so there must be no tenant-reachable route here, and a tenant
# portal id must not be addressable even by a super admin -- the `media:` namespace is per-portal and only the two
# platform portals have a documentation corpus.
RSpec.describe 'Super Admin documentation media upload', type: :request do
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:other_png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAYAAAACCAAAAABeNvKCAAAAC0lEQVR4nGNgQAYAAA4AAamRc7EAAAAASUVORK5CYII=') }
  let(:super_admin) { create(:super_admin) }
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil)
  end
  let(:tenant_portal) { create(:portal, name: 'Tenant help', slug: 'tenant-help') }
  let(:file) { Rack::Test::UploadedFile.new(StringIO.new(png), 'image/png', original_filename: 'Step Two.png') }
  let(:body) { response.parsed_body }

  describe 'POST /super_admin/documentation_media' do
    it 'is refused to anyone who is not a signed-in super admin' do
      post '/super_admin/documentation_media', params: { portal_id: portal.id, file: file, alt: 'Alt' }

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(new_super_admin_session_path)
      expect(portal.reload.documentation_media).to be_empty
    end

    context 'when signed in as a super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'attaches the file and returns the key and the Markdown to insert' do
        post '/super_admin/documentation_media', params: { portal_id: portal.id, file: file, alt: 'Paste the token' }

        expect(response).to have_http_status(:created)
        expect(body['key']).to match(%r{\Auploads/[0-9a-f]{16}-step-two\.png\z})
        expect(body['markdown']).to eq("![Paste the token](media:#{body['key']})")
        expect([body['width'], body['height']]).to eq([4, 3])
        expect(portal.reload.documentation_media.count).to eq(1)
      end

      it 'leaks no signed id, blob id or storage path in the response' do
        post '/super_admin/documentation_media', params: { portal_id: portal.id, file: file, alt: 'Alt' }
        blob = portal.reload.documentation_media.first.blob

        expect(response.body).not_to include(blob.signed_id, blob.key, 'storage')
        expect(body.keys).to contain_exactly('key', 'markdown', 'width', 'height', 'replaced')
      end

      # A tenant portal is not addressable here: the namespace is per-portal, and only the platform portals have a
      # documentation corpus. This is the Super Admin half of "tenants are readers".
      it 'is 404 for a tenant portal, even for a super admin' do
        post '/super_admin/documentation_media',
             params: { portal_id: tenant_portal.id, file: file, alt: 'Alt' }

        expect(response).to have_http_status(:not_found)
        expect(tenant_portal.reload.documentation_media).to be_empty
      end

      it 'is 404 for an unknown portal id' do
        post '/super_admin/documentation_media', params: { portal_id: 0, file: file, alt: 'Alt' }

        expect(response).to have_http_status(:not_found)
      end

      it 'is 422 with the service message when the alt is missing' do
        post '/super_admin/documentation_media', params: { portal_id: portal.id, file: file, alt: '' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to match(/Alt text is required/)
      end

      it 'is 422 for a type outside the raster allowlist' do
        svg = Rack::Test::UploadedFile.new(
          StringIO.new('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>'),
          'image/svg+xml', original_filename: 'logo.svg'
        )

        post '/super_admin/documentation_media', params: { portal_id: portal.id, file: svg, alt: 'Logo' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to match(%r{image/svg\+xml is not permitted})
      end

      it 'is 422 when no file was sent, rather than failing inside the service' do
        post '/super_admin/documentation_media', params: { portal_id: portal.id, alt: 'Alt' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to eq('A file is required.')
      end
    end
  end

  describe 'PATCH /super_admin/documentation_media/*key' do
    before { sign_in(super_admin, scope: :super_admin) }

    let(:key) do
      Documentation::MediaUpload.new(portal: portal)
                                .create!(io: StringIO.new(png), filename: 'a.png', alt: 'Alt').key
    end
    let(:replacement) do
      Rack::Test::UploadedFile.new(StringIO.new(other_png), 'image/png', original_filename: 'b.png')
    end

    it 'keeps the key and swaps the bytes' do
      patch "/super_admin/documentation_media/#{key}", params: { portal_id: portal.id, file: replacement }

      expect(response).to have_http_status(:ok)
      expect(body['key']).to eq(key)
      expect(body['replaced']).to be(true)
      expect([body['width'], body['height']]).to eq([6, 2])
      expect(portal.reload.documentation_media.count).to eq(1)
    end

    it 'is 422 for a key the seeder owns, because the corpus wins for corpus content' do
      Documentation::MediaUpload.new(portal: portal)
                                .attach!(key: 'whatsapp/step-2.png', io: StringIO.new(png), filename: 'step-2.png',
                                         content_source_path: 'custom/db/documentation/media/whatsapp/step-2.png')

      patch '/super_admin/documentation_media/whatsapp/step-2.png',
            params: { portal_id: portal.id, file: replacement }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to match(/seeded from the corpus/)
    end

    # The glob has to keep the whole key, extension included, for the same reason the public route needs
    # `format: false`: a non-greedy glob otherwise loses `.png` to params[:format].
    it 'receives the whole multi-segment key, extension included' do
      patch "/super_admin/documentation_media/#{key}", params: { portal_id: portal.id, file: replacement }

      expect(request.params[:key]).to eq(key)
      expect(request.params[:format]).to be_nil
    end
  end

  # Item 12 is a standing rule, not an observation: a new Portal/Article/Category policy action would be granted
  # to every tenant administrator by default, because that policy family is an enumerated deny list. This change
  # adds no such action, and this is the assertion that says so rather than the claim.
  describe 'the tenant boundary' do
    it 'adds no Portal, Article or Category policy action for a tenant to inherit' do
      %w[documentation_media media upload attach].each do |action|
        [PortalPolicy, ArticlePolicy, CategoryPolicy].each do |policy|
          expect(policy.instance_methods).not_to include(:"#{action}?"), "#{policy}##{action}?"
        end
      end
    end

    it 'exposes no tenant-reachable route for documentation media' do
      tenant_reachable = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
                              .select { |path| path.include?('documentation_media') }
                              .reject { |path| path.start_with?('/super_admin') }

      expect(tenant_reachable).to be_empty
    end
  end
end
