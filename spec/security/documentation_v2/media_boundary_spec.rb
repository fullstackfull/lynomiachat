require 'rails_helper'

# WAVE 4, AGENT 6 -- ADVERSARIAL. Nothing here is a product feature; every example is an attack that must fail,
# or a property of a refusal that must hold.
#
# What is deliberately NOT repeated here: the published/draft predicate, the 404-not-403 rule, the cross-portal
# key refusal and the ETag replay, all already pinned by spec/requests/documentation/media_delivery_spec.rb.
# These are the surfaces that spec does not reach.
RSpec.describe 'Documentation media -- adversarial boundary', type: :request do
  # A 4x3 PNG, and the same bytes with an HTML document appended: a content-sniffing polyglot. Marcel reads the
  # magic bytes, so the tail does not change the identified type -- what has to hold is that the RESPONSE cannot
  # be sniffed as HTML either.
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  # `dup.concat` rather than `+`: `png` is binary and the tail is a UTF-8 literal, and this keeps the byte
  # semantics explicit instead of relying on an encoding-compatibility rule in an operator.
  let(:polyglot) { png.dup.concat('<html><body><script>alert(1)</script></body></html>') }
  let(:super_admin) { create(:super_admin) }

  let!(:docs_portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let!(:docs_article) do
    create(:article, title: 'Connect WhatsApp', slug: 'connect-whatsapp', content: 'Body', status: :published,
                     locale: 'en', portal: docs_portal, account_id: nil, author: super_admin)
  end

  let(:key) { 'whatsapp/connect-number/step-2.png' }

  def attach(portal, media_key, bytes = png, source_path: "custom/db/documentation/media/#{media_key}")
    Documentation::MediaUpload.new(portal: portal)
                              .attach!(key: media_key, io: StringIO.new(bytes),
                                       filename: File.basename(media_key), content_source_path: source_path)
  end

  def get_public(path, **)
    with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
      get(path, **)
    end
  end

  def media_path(portal_slug, article_slug, media_key)
    "/hc/#{portal_slug}/articles/#{article_slug}/media/#{media_key}"
  end

  describe 'a tenant portal, which has no documentation media and must not be able to acquire any' do
    let(:account) { create(:account) }
    let(:tenant_admin) { create(:user, account: account, role: :administrator) }
    let!(:tenant_portal) { create(:portal, account_id: account.id, slug: 'tenant-portal') }
    let!(:tenant_article) do
      create(:article, portal: tenant_portal, account_id: account.id, author: tenant_admin, status: :published,
                       slug: 'tenant-page', title: 'Tenant page', content: 'Tenant body', locale: 'en')
    end

    # The whole write side in one place: `portal.documentation_media.attach` is reached from exactly two callers
    # and both resolve the portal inside Documentation::Library.portals -- the seeder and
    # SuperAdmin::DocumentationMediaController. The assertion is the consequence an attacker cares about.
    it 'has no attachment, and the public media route is 404 for every key shape' do
      attach(docs_portal, key)

      [key, 'tenant/own.png', 'uploads/0123456789abcdef-x.png'].each do |candidate|
        get_public media_path(tenant_portal.slug, tenant_article.slug, candidate)

        expect(response).to have_http_status(:not_found), candidate
      end
      expect(tenant_portal.reload.documentation_media).to be_empty
    end

    # The Portal model gains `has_many_attached :documentation_media`, which also defines a
    # `documentation_media=` mass-assignment writer. The tenant portal API is the one surface that could reach
    # it, and it is closed at the policy -- 401 before any parameter is read.
    it 'cannot be given documentation media through the tenant portal API' do
      patch "/api/v1/accounts/#{account.id}/portals/#{tenant_portal.slug}",
            params: { portal: { name: 'x', documentation_media: [] } },
            headers: tenant_admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(tenant_portal.reload.documentation_media).to be_empty
    end

    it 'is refused the operator upload path under every tenant role' do
      agent = create(:user, account: account, role: :agent)
      file = Rack::Test::UploadedFile.new(StringIO.new(png), 'image/png', original_filename: 'x.png')

      [tenant_admin, agent].each do |user|
        sign_in(user, scope: :user)
        post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: file, alt: 'Alt' }

        expect(response).to have_http_status(:redirect), user.id.to_s
        expect(response).to redirect_to(new_super_admin_session_path)
        sign_out(:user)
      end
      expect(docs_portal.reload.documentation_media).to be_empty
    end
  end

  # CONTENT SNIFFING. The upload boundary identifies from the bytes, so a PNG with an HTML tail is a legitimate
  # PNG to it. What stops that being stored XSS is the RESPONSE: the declared type is the blob's, and Rails'
  # default `X-Content-Type-Options: nosniff` is what makes a browser believe it.
  describe 'a content-sniffing polyglot' do
    it 'is served as its identified type, nosniff, and never as a document' do
      attach(docs_portal, key, polyglot)

      get_public media_path(docs_portal.slug, docs_article.slug, key)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['Content-Disposition']).to start_with('inline')
      expect(response.body.b).to eq(polyglot)
    end
  end

  # THE OPERATOR UPLOAD PATH, told a LIE about what it is being handed. The service reads only the IO
  # (`Marcel::MimeType.for(io)`), so the declared Content-Type and the `.png` filename are ignored by
  # construction -- but "by construction" is the claim, and this is the measurement of it over the real
  # multipart request, which is where the lie is actually told.
  describe 'a mismatched upload' do
    before { sign_in(super_admin, scope: :super_admin) }

    {
      'an HTML document renamed .png' => '<html><body><script>alert(1)</script></body></html>',
      'an SVG renamed .png' => %(<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><script>alert(1)</script></svg>),
      'an SVG with no xmlns, renamed .png' => '<svg><script>alert(1)</script></svg>',
      'a PHP script renamed .png' => "<?php system($_GET['c']); ?>"
    }.each do |label, bytes|
      it "is refused on the bytes, not the declaration: #{label}" do
        liar = Rack::Test::UploadedFile.new(StringIO.new(bytes), 'image/png', original_filename: 'innocent.png')

        post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: liar, alt: 'Alt' }

        expect(response).to have_http_status(:unprocessable_entity), label
        expect(response.parsed_body['error']).to match(/is not permitted/), label
        expect(docs_portal.reload.documentation_media).to be_empty
      end
    end

    # A real PNG with an HTML tail IS accepted -- it is a PNG to any identifier that reads magic bytes -- and
    # that is why the delivery assertions above (declared type + nosniff) are the control that matters.
    it 'accepts a real PNG with an HTML tail, which delivery then neutralises' do
      liar = Rack::Test::UploadedFile.new(StringIO.new(polyglot), 'image/png', original_filename: 'tail.png')

      post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: liar, alt: 'Alt' }

      expect(response).to have_http_status(:created)
      expect(docs_portal.reload.documentation_media.first.blob.content_type).to eq('image/png')
    end

    # THE BYTE CAP, SERVER-SIDE. `mediaUpload.js` has no size check at all, so the cap is the only one there
    # is; this proves it is enforced on the request rather than in the picker.
    it 'refuses bytes over the cap on the server, where the picker has no check at all' do
      oversize = Rack::Test::UploadedFile.new(
        StringIO.new(png.dup.concat("\x00" * (Documentation::MediaUpload::MAX_BYTES + 1))),
        'image/png', original_filename: 'big.png'
      )

      post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: oversize, alt: 'Alt' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/the cap is/)
      expect(docs_portal.reload.documentation_media).to be_empty
    end

    # REPLACE CANNOT CROSS A PORTAL. The key is addressed by a glob and the portal by a parameter, so the two
    # could disagree; `attachment_for` is scoped to the portal, so a key attached elsewhere is simply absent.
    it 'cannot replace another portal\'s attachment by naming this portal' do
      changelog = create(:portal, name: 'Lynomia Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                                  platform_owned: true, account: nil)
      operator_key = Documentation::MediaUpload.new(portal: changelog)
                                               .create!(io: StringIO.new(png), filename: 'a.png', alt: 'Alt').key
      replacement = Rack::Test::UploadedFile.new(StringIO.new(polyglot), 'image/png', original_filename: 'b.png')

      patch "/super_admin/documentation_media/#{operator_key}",
            params: { portal_id: docs_portal.id, file: replacement }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/No documentation media is attached/)
      expect(changelog.reload.documentation_media.first.blob.byte_size).to eq(png.bytesize)
    end

    # AN OPERATOR UPLOAD CANNOT TAKE A SEEDED KEY, in either direction: `create!` always allocates under the
    # reserved first segment, and the seeder refuses a corpus file that lives there. The two namespaces are
    # disjoint sets, which is what makes "an operator cannot overwrite a seeded key" a property rather than a
    # check someone has to remember.
    it 'allocates only inside the reserved operator namespace, so no seeded key is reachable' do
      attach(docs_portal, key)
      file = Rack::Test::UploadedFile.new(StringIO.new(png), 'image/png', original_filename: 'step-2.png')

      3.times do
        post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: file, alt: 'Alt' }
        expect(response).to have_http_status(:created)
        expect(response.parsed_body['key']).to start_with("#{Documentation::MediaResolver::OPERATOR_SEGMENT}/")
      end

      expect(Documentation::MediaResolver.new(portal: docs_portal.reload, article: docs_article)
                                        .resolve(key).blob.byte_size).to eq(png.bytesize)
    end
  end

  # "DOES ANY RESPONSE LEAK ... A CHECKSUM-AS-IDENTIFIER?" -- the one place a checksum is deliberately used is
  # the validator, so it is worth measuring rather than assuming. `fresh_when(etag:)` runs the value through
  # ActiveSupport::Digest before it reaches the header, so the header is not the blob's checksum; and a DRAFT
  # takes the `no-store` branch, which sets no validator at all.
  describe 'the validator' do
    it 'is derived from the checksum, not the checksum itself, and is absent for a draft' do
      blob = attach(docs_portal, key)
      get_public media_path(docs_portal.slug, docs_article.slug, key)

      expect(response.headers['ETag']).to be_present
      expect(response.headers['ETag']).not_to include(blob.checksum)
      expect(response.headers.to_h.to_s).not_to include(blob.checksum)

      draft = create(:article, portal: docs_portal, account_id: nil, author: super_admin, status: :draft,
                               slug: 'not-ready', title: 'Not ready', content: 'Soon', locale: 'en')
      sign_in(super_admin, scope: :super_admin)
      get_public media_path(docs_portal.slug, draft.slug, key)

      expect(response).to have_http_status(:ok)
      expect(response.headers['Last-Modified']).to be_nil
      expect(response.headers.to_h.to_s).not_to include(blob.checksum)
    end
  end

  # THE KEY GRAMMAR, THROUGH THE REAL ROUTE. The unit spec proves `valid_key?` rejects these; this proves the
  # rejected string actually arrives at the controller as `media_key` and is answered 404 rather than, say,
  # being swallowed by the router into a different route or reaching the filesystem.
  describe 'hostile keys over HTTP' do
    before { attach(docs_portal, key) }

    {
      'traversal' => '../../../../etc/passwd.png',
      'encoded traversal' => '%2e%2e/%2e%2e/etc/passwd.png',
      'null byte' => 'whatsapp/connect-number/step-2.png%00.svg',
      'cyrillic homoglyph' => 'whatsapp/%D0%B0bc.png',
      'uppercase' => 'WhatsApp/Connect-Number/Step-2.PNG',
      'too many segments' => 'a/b/c/d/e/f.png',
      'query smuggled into the glob' => 'whatsapp/connect-number/step-2.png%3Fx%3D1',
      'absurd length' => "#{'a' * 400}/b.png",
      'the operator namespace, unattached' => 'uploads/0123456789abcdef-nothing.png'
    }.each do |label, candidate|
      it "is 404 and never a redirect: #{label}" do
        get_public media_path(docs_portal.slug, docs_article.slug, candidate)

        expect(response).to have_http_status(:not_found), "#{label} -> #{response.status}"
        expect(response.headers['Location']).to be_nil
        expect(response.body).to be_empty
      end
    end

    # The grammar is case-SENSITIVE, which is load-bearing on a case-insensitive developer filesystem. The
    # attached key resolves; the same key in another case does not.
    it 'resolves the exact key only' do
      get_public media_path(docs_portal.slug, docs_article.slug, key)
      expect(response).to have_http_status(:ok)

      get_public media_path(docs_portal.slug, docs_article.slug, key.upcase)
      expect(response).to have_http_status(:not_found)
    end
  end

  # NO IDENTIFIER LEAK ON THE PAGE, which is a different surface from the media response the delivery spec
  # checks. The article page is where the src is MINTED, so it is where a signed id would be committed.
  describe 'the rendered article page' do
    it 'mints a root-relative, same-origin src carrying no signed id, blob id, blob key or checksum' do
      blob = attach(docs_portal, key)
      docs_article.update!(content: "![Paste the token](media:#{key})")

      get_public "/hc/#{docs_portal.slug}/articles/#{docs_article.slug}"

      expect(response).to have_http_status(:ok)
      src = Nokogiri::HTML5(response.body).at_css('#cw-article-content img')['src']
      expect(src).to eq(media_path(docs_portal.slug, docs_article.slug, key))
      expect(src).to start_with('/')
      # NOT `blob.id.to_s`: a bare integer primary key is two characters and matches incidental digits anywhere
      # on the page, so asserting its absence measures nothing. What identifies a blob in a URL is the signed
      # id, the storage key or an ActiveStorage route, and all three are asserted.
      [blob.signed_id, blob.key, blob.checksum, 'rails/active_storage'].each do |secret|
        expect(response.body).not_to include(secret), secret.to_s
      end
    end

    # An unresolved key is a corpus defect, and the renderer's diagnostic must not be able to close the comment
    # it is reported in.
    it 'cannot break out of the unresolved-key comment' do
      docs_article.update!(content: '![alt](media:a/--><script>alert(1)</script>.png)')

      get_public "/hc/#{docs_portal.slug}/articles/#{docs_article.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('<script>alert(1)</script>')
    end
  end

  # THE TWO ROUTES' PORTAL RESOLUTION, which is the one place their before_action chains genuinely differ:
  # `ensure_custom_domain_request` assigns @portal from the custom domain and BOTH controllers now keep that
  # resolution (`@portal ||=`): ArticlesController via base_controller.rb:35, MediaController via its own
  # `set_portal`. Before that fix the media route overwrote it from the URL slug, so on a custom domain the page
  # 404'd a documentation article while the media route served its media.
  #
  # What these examples hold is that the two routes agree, and that each still only ever serves the portal it
  # resolved -- neither reaches another portal's attachment.
  describe 'portal resolution on a registered custom domain' do
    let(:account) { create(:account) }
    let!(:tenant_portal) do
      create(:portal, account_id: account.id, slug: 'tenant-portal', custom_domain: 'help.tenant.example.com',
                      config: { 'allowed_locales' => ['en'], 'default_locale' => 'en' })
    end
    let!(:tenant_article) do
      create(:article, portal: tenant_portal, account_id: account.id, author: create(:user, account: account),
                       status: :published, slug: 'tenant-page', title: 'Tenant page', content: 'Body', locale: 'en')
    end

    before { attach(docs_portal, key) }

    # The divergence itself, measured. The page resolves the portal from the DOMAIN and so 404s the
    # documentation article; the media route resolves it from the SLUG and so serves documentation media.
    #
    # INVERTED, as the submission said it would be: `MediaController#set_portal` is now `@portal ||=`, matching
    # `BaseController#portal`, so both routes resolve the portal from the domain and both 404. The example is
    # kept rather than deleted because the property worth pinning is that the two routes AGREE on a custom
    # domain -- the previous expectation (200 / 404) is recorded here so the change is visible, not silent.
    it 'agrees with the article page on a custom domain, where it used to serve media the page refused' do
      host! 'help.tenant.example.com'

      get media_path(docs_portal.slug, docs_article.slug, key)
      media_status = response.status

      get "/hc/#{docs_portal.slug}/articles/#{docs_article.slug}"
      page_status = response.status

      expect([media_status, page_status]).to eq([404, 404])
    end

    # The property that makes the divergence a consistency defect rather than a disclosure: the bytes reachable
    # that way are the SAME public bytes the canonical host serves for the same published article, and nothing
    # on the tenant's own portal becomes reachable.
    it 'still reaches no attachment that is not the resolved portal\'s own' do
      host! 'help.tenant.example.com'

      get media_path(tenant_portal.slug, tenant_article.slug, key)

      expect(response).to have_http_status(:not_found)
      expect(tenant_portal.reload.documentation_media).to be_empty
    end
  end

  # REFUSAL ORDER. A key must not be resolvable on a portal whose public surface is itself refused, because the
  # article page applies both of these filters and the images must not outlive the page.
  describe 'the refusals that run before the key is looked at' do
    it 'is 401, not 404, for an unregistered host -- the same refusal the page gives' do
      attach(docs_portal, key)

      get media_path(docs_portal.slug, docs_article.slug, key)

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include(png)
    end

    it 'is payment_required on a cloud install whose portal has help_center disabled' do
      attach(docs_portal, key)
      tenant = create(:portal, account: create(:account), slug: 'paywalled',
                               config: { 'allowed_locales' => ['en'], 'default_locale' => 'en' })
      article = create(:article, portal: tenant, account_id: tenant.account_id, author: create(:user),
                                 status: :published, slug: 'paywalled-page', content: 'b', locale: 'en')
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)

      get_public media_path(tenant.slug, article.slug, key)

      expect(response).to have_http_status(:payment_required)
    end
  end
end
