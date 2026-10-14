require 'rails_helper'

# ONE CONTINUOUS CHAIN, from an authorized Super Admin upload to authorized delivery of those same bytes:
#
#   POST /super_admin/documentation_media  ->  portal.documentation_media (operator namespace, no corpus owner)
#     ->  the server-composed `![alt](media:<key>)`  ->  the article's own content
#     ->  ChatwootMarkdownRenderer#render_article through the real public page  ->  the <img src>
#     ->  GET that src  ->  the uploaded bytes
#
# Every link already has a spec of its own. What none of them establishes is that the links AGREE: the upload
# allocates a key, the renderer resolves one, and the delivery route validates one, in three files and two
# request cycles. So this walks the whole thing once, in order, simulating no step it can perform -- a real
# multipart POST as a signed-in super admin, the real article page, and a real GET of the src that page minted.
#
# The four negatives are the same chain with one role, portal, status or key changed, each asserted by what an
# attacker or an operator can actually observe.
#
# The fixture is four bytes of PNG built here. The corpus media tree is the corpus, and an upload fixture is not
# part of it -- nothing in this file needs a real screenshot.
RSpec.describe 'Documentation media -- the whole chain, end to end', type: :request do
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:super_admin) { create(:super_admin) }
  let(:upload) { Rack::Test::UploadedFile.new(StringIO.new(png), 'image/png', original_filename: 'Step Two.png') }
  # An alt an operator would really type. `[` and `]` are what Documentation::MediaUpload escapes on the way out
  # (media_upload.rb:143), so carrying one through proves the server's escaping survives the renderer rather than
  # publishing a broken image node.
  let(:alt) { 'Step 2 [see note]' }
  let(:operator_key) { %r{\Auploads/[0-9a-f]{16}-step-two\.png\z} }

  let!(:docs_portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let!(:article) do
    create(:article, title: 'Connect WhatsApp', slug: 'connect-whatsapp', content: 'Body', status: :published,
                     locale: 'en', portal: docs_portal, account_id: nil, author: super_admin)
  end

  # The public portal serves only on a host this installation knows itself by (DomainHelper.chatwoot_domain?),
  # which is a deployment prerequisite rather than a code path, so these run with it satisfied.
  def get_public(path, **)
    with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
      get(path, **)
    end
  end

  def rendered_image(path)
    get_public path
    Nokogiri::HTML5(response.body).at_css('#cw-article-content img')
  end

  describe 'the authorized path' do
    it 'holds from a Super Admin upload to the delivery of those exact bytes' do
      sign_in(super_admin, scope: :super_admin)

      # 1. AUTHORIZED UPLOAD. Multipart, through the route, with the Super Admin session as the authorization.
      post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: upload, alt: alt }
      key = response.parsed_body['key']
      attachment = docs_portal.reload.documentation_media.first

      # 2. PORTAL-OWNED DOCUMENTATION MEDIA, under the reserved operator segment, with no corpus file owning it --
      #    which is what keeps the seeder's orphan sweep off it (owner correction F1.1).
      expect(
        { status: response.status, key_shape: key.match?(operator_key), attached: docs_portal.documentation_media.count,
          record: attachment.record, stored_key: attachment.blob.metadata['documentation_key'],
          corpus_owned: attachment.blob.metadata.key?('content_source_path') }
      ).to eq(status: 201, key_shape: true, attached: 1, record: docs_portal, stored_key: key, corpus_owned: false)

      # 3. A STABLE `media:` REFERENCE, composed by the server and inserted verbatim: no URL, no blob id, no
      #    signed id, and the alt escaped once, server-side.
      expect(response.parsed_body['markdown']).to eq("![Step 2 \\[see note\\]](media:#{key})")

      # 4. ARTICLE RENDERER RESOLUTION. The operator saves that string; the public page renders it through the
      #    real renderer and the per-request, per-portal resolver.
      article.update!(content: response.parsed_body['markdown'])
      sign_out(:super_admin)
      image = rendered_image("/hc/#{docs_portal.slug}/articles/#{article.slug}")

      expect(response).to have_http_status(:ok)
      expect([image['src'], image['alt'], image['width'], image['height'], image['loading']])
        .to eq(["/hc/#{docs_portal.slug}/articles/#{article.slug}/media/#{key}", alt, '4', '3', 'lazy'])
      expect(response.body).not_to include(attachment.blob.signed_id, attachment.blob.key, 'storage')

      # 5. AUTHORIZED, APPLICATION-OWNED DELIVERY of the uploaded bytes, from the src the page itself minted.
      get_public image['src']

      expect([response.status, response.media_type, response.body.b, response.headers['Location']])
        .to eq([200, 'image/png', png, nil])
    end
  end

  # NEGATIVE 1 -- the chain cannot be STARTED by a tenant. A tenant is a reader of this documentation, so no
  # tenant principal may obtain a `media:` key; without one there is no link 2 to reach.
  describe 'a tenant' do
    let(:account) { create(:account) }
    let(:tenant_admin) { create(:user, account: account, role: :administrator) }

    it 'is issued no key, and cannot take over the bytes of one a super admin already owns' do
      sign_in(super_admin, scope: :super_admin)
      post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: upload, alt: alt }
      key = response.parsed_body['key']
      sign_out(:super_admin)

      sign_in(tenant_admin, scope: :user)
      post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: upload, alt: 'Mine' }

      expect(response).to redirect_to(new_super_admin_session_path)
      expect(response.parsed_body).not_to include('key', 'markdown')

      patch "/super_admin/documentation_media/#{key}",
            params: { portal_id: docs_portal.id,
                      file: Rack::Test::UploadedFile.new(StringIO.new('<html>x</html>'), 'image/png',
                                                         original_filename: 'x.png') }

      expect(response).to redirect_to(new_super_admin_session_path)
      expect([docs_portal.reload.documentation_media.count, docs_portal.documentation_media.first.blob.download.b])
        .to eq([1, png])
    end
  end

  # NEGATIVE 2 -- the chain cannot be CROSSED between portals. The key is per-portal by construction, so the
  # other platform portal neither renders nor delivers it, and the refusal is a 404 rather than a 403.
  describe 'the other platform portal' do
    let!(:changelog_portal) do
      create(:portal, name: 'Lynomia Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                      platform_owned: true, account: nil,
                      config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
    end
    let!(:changelog_article) do
      create(:article, title: 'Release 4.18', slug: 'release-4-18', content: 'Body', status: :published,
                       locale: 'en', portal: changelog_portal, account_id: nil, author: super_admin)
    end

    it 'cannot resolve or deliver a key uploaded to the documentation portal' do
      sign_in(super_admin, scope: :super_admin)
      post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: upload, alt: alt }
      key = response.parsed_body['key']
      changelog_article.update!(content: response.parsed_body['markdown'])
      sign_out(:super_admin)

      # The renderer resolves against the portal being rendered, so there is no <img> at all -- an inert comment
      # instead, and never a `src=""`, which several browsers re-request the current page for.
      expect(rendered_image("/hc/#{changelog_portal.slug}/articles/#{changelog_article.slug}")).to be_nil
      expect(response.body).to include("<!-- media: unresolved key #{key} -->")

      get_public "/hc/#{changelog_portal.slug}/articles/#{changelog_article.slug}/media/#{key}"
      refused = [response.status, response.body, response.headers['Location']]

      # The control, without which the 404 above could mean the key is simply broken: the portal it WAS uploaded
      # to serves it.
      get_public "/hc/#{docs_portal.slug}/articles/#{article.slug}/media/#{key}"

      expect(refused).to eq([404, '', nil])
      expect([response.status, response.body.b]).to eq([200, png])
    end
  end

  # NEGATIVE 3 -- a draft's media is not exposed to an unauthorized public request, and IS exposed to a super
  # admin, because pre-publication review is the whole reason the section 0.1 predicate is not "published only".
  # Same key, same URL, same bytes: only the requester changes.
  describe 'a draft article' do
    it 'refuses the anonymous requester and serves the signed-in super admin the same chain' do
      sign_in(super_admin, scope: :super_admin)
      post '/super_admin/documentation_media', params: { portal_id: docs_portal.id, file: upload, alt: alt }
      key = response.parsed_body['key']
      article.update!(content: response.parsed_body['markdown'], status: :draft)
      media_url = "/hc/#{docs_portal.slug}/articles/#{article.slug}/media/#{key}"
      sign_out(:super_admin)

      get_public "/hc/#{docs_portal.slug}/articles/#{article.slug}"
      page_status = response.status
      get_public media_url

      # 404 and never 403: a 403 would distinguish "exists but hidden" from "does not exist", which is an
      # existence oracle for unpublished content on an unauthenticated endpoint.
      expect([page_status, response.status, response.body]).to eq([404, 404, ''])

      sign_in(super_admin, scope: :super_admin)
      image = rendered_image("/hc/#{docs_portal.slug}/articles/#{article.slug}")

      expect([response.status, image['src']]).to eq([200, media_url])

      get_public image['src']

      expect([response.status, response.body.b]).to eq([200, png])
      # A draft's media is never cacheable, so the preview cannot leave a copy in a shared cache.
      expect(response.headers['Cache-Control']).to eq('private, no-store')
    end
  end

  # NEGATIVE 4 -- a missing or invalid key fails SAFELY, which is a claim with four parts: the status, the absence
  # of a redirect, a body that says nothing, and what the renderer puts on the page in place of the image.
  describe 'a missing or invalid key' do
    let(:unresolvable) do
      { 'a valid key with no attachment' => 'whatsapp/absent.png',
        'an operator key that was never issued' => 'uploads/0000000000000000-never.png',
        'uppercase, which the grammar rejects' => 'WhatsApp/Step.PNG',
        'a traversal attempt' => '../../etc/passwd',
        'an SVG extension, which is not raster' => 'a/b.svg',
        'a width query the grammar has no room for' => 'a/b.png?cw_image_width=400px' }
    end

    it 'answers 404 with no redirect and an empty body, for every shape' do
      results = unresolvable.transform_values do |key|
        get_public "/hc/#{docs_portal.slug}/articles/#{article.slug}/media/#{key}"
        [response.status, response.body, response.headers['Location'], response.media_type]
      end

      expect(results.values.uniq).to eq([[404, '', nil, nil]])
    end

    it 'renders an inert comment rather than an image, and leaks no path into the page' do
      article.update!(content: "![Alt](media:whatsapp/absent.png)\n\n![Alt](media:../../etc/passwd)")

      expect(rendered_image("/hc/#{docs_portal.slug}/articles/#{article.slug}")).to be_nil
      expect(response.body).to include('<!-- media: unresolved key whatsapp/absent.png -->',
                                       '<!-- media: unresolved key ../../etc/passwd -->')
      expect(response.body).not_to include('src=""', Rails.root.to_s, 'ActiveStorage')
    end
  end
end
