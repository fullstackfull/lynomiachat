require 'rails_helper'

# Public delivery for documentation media. The predicate is contract section 0.1 -- published OR the requester is
# a signed-in super admin -- and it is the same rule ArticlesController#set_article applies, because a media
# predicate of "published only" would render the one surface whose entire purpose is pre-publication review with
# broken images.
#
# Every refusal is 404 and never 403: a 403 would distinguish "exists but hidden" from "does not exist", which is
# an existence oracle for unpublished content on an unauthenticated endpoint.
RSpec.describe 'Documentation media delivery', type: :request do
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:super_admin) { create(:super_admin) }
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let!(:published) do
    create(:article, title: 'Connect WhatsApp', slug: 'connect-whatsapp', content: 'Body', status: :published,
                     locale: 'en', portal: portal, account_id: nil, author: super_admin)
  end
  let!(:draft) do
    create(:article, title: 'Not ready', slug: 'not-ready', content: 'Soon', status: :draft, locale: 'en',
                     portal: portal, account_id: nil, author: super_admin)
  end
  let(:key) { 'whatsapp/connect-number/step-2.png' }
  let!(:blob) do
    Documentation::MediaUpload.new(portal: portal)
                              .attach!(key: key, io: StringIO.new(png), filename: 'step-2.png',
                                       content_source_path: "custom/db/documentation/media/#{key}")
  end

  # The public portal serves only on a host this installation knows itself by (DomainHelper.chatwoot_domain?),
  # which is a deployment prerequisite rather than a code path, so these run with it satisfied.
  def get_public(path, **)
    with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
      get(path, **)
    end
  end

  def media_path(article_slug, media_key = key, portal_slug = portal.slug)
    "/hc/#{portal_slug}/articles/#{article_slug}/media/#{media_key}"
  end

  describe 'a published article' do
    it 'serves the bytes to an anonymous visitor, with the blob content type' do
      get_public media_path(published.slug)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
      expect(response.body.b).to eq(png)
    end

    # A long immutable max-age would be wrong: the URL is not content-addressed, and the same key may take new
    # bytes, so a year-long cache would serve a replaced screenshot indefinitely.
    it 'is cacheable by anyone, with a checksum ETag so revalidation is a 304' do
      get_public media_path(published.slug)

      expect(response.headers['Cache-Control']).to include('public', 'max-age=3600')
      expect(response.headers['ETag']).to be_present
      expect(response.headers['Last-Modified']).to be_present

      get_public media_path(published.slug), headers: { 'If-None-Match' => response.headers['ETag'] }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    it 'leaks no signed id, blob id, blob key or storage path in the response' do
      get_public media_path(published.slug)

      headers = response.headers.to_h.to_s
      expect(headers).not_to include(blob.signed_id, blob.key, 'storage')
      expect(response.headers['Location']).to be_nil
    end
  end

  describe 'an unpublished article' do
    it 'is 404 to an anonymous visitor rather than 403' do
      get_public media_path(draft.slug)

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it 'is served to a signed-in super admin, and is never cacheable' do
      sign_in(super_admin, scope: :super_admin)

      get_public media_path(draft.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to eq(png)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      # The controller sets NO validator on a draft: no fresh_when, so no blob checksum and no Last-Modified.
      # Measured: Rack's own middleware still appends a weak body digest to any 200 with an array body unless one
      # of those two headers is already present (rack-3.2.6/lib/rack/etag.rb:31-34,57-59), and it has no
      # `no-store` escape. `no-store` is what makes the response uncacheable; the weak digest is not the blob's
      # checksum, so it discloses nothing about the blob.
      expect(response.headers['ETag']).not_to include(blob.checksum)
      expect(response.headers['Last-Modified']).to be_nil
    end

    # The property that actually matters about a draft validator: it cannot be replayed by someone who is not a
    # super admin. The predicate runs on every request, so the article lookup 404s before any cache logic.
    it 'does not let a draft validator be replayed by an anonymous requester' do
      sign_in(super_admin, scope: :super_admin)
      get_public media_path(draft.slug)
      validator = response.headers['ETag']
      sign_out(:super_admin)

      get_public media_path(draft.slug), headers: { 'If-None-Match' => validator }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the 404 cases' do
    it 'is 404 for an unknown portal slug' do
      get_public media_path(published.slug, key, 'no-such-portal')

      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 for an archived portal' do
      portal.update!(archived: true)

      get_public media_path(published.slug)

      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 for an article slug that is not in this portal' do
      get_public media_path('no-such-article')

      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 for a key that fails the grammar, and never a redirect' do
      ['WhatsApp/Step.PNG', '../../etc/passwd', 'a/b.svg'].each do |bad|
        get_public media_path(published.slug, bad)

        expect(response).to have_http_status(:not_found), bad
        expect(response.headers['Location']).to be_nil
      end
    end

    it 'is 404 for a valid key this portal has no attachment for' do
      get_public media_path(published.slug, 'whatsapp/absent.png')

      expect(response).to have_http_status(:not_found)
    end

    # Contract section 0.2: no cross-portal fallback, deliberately.
    it 'is 404 for a key belonging to the other platform portal' do
      changelog = create(:portal, name: 'Lynomia Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                                  platform_owned: true, account: nil)
      Documentation::MediaUpload.new(portal: changelog)
                                .attach!(key: 'releases/only-here.png', io: StringIO.new(png),
                                         filename: 'only-here.png',
                                         content_source_path: 'custom/db/changelog/media/releases/only-here.png')

      get_public media_path(published.slug, 'releases/only-here.png')

      expect(response).to have_http_status(:not_found)
    end
  end

  # The route is nested under the article so the predicate can be applied, and the glob has to survive the
  # extension: without `format: false` the non-greedy glob loses `.png` to params[:format] and the key can never
  # match. This asserts the whole key arrived, which is the observable consequence.
  describe 'the route shape' do
    it 'delivers a multi-segment key with its extension intact' do
      get_public media_path(published.slug)

      expect(request.params[:media_key]).to eq(key)
      expect(request.params[:format]).to be_nil
    end
  end

  # The whole chain in one example, because every other example here starts from an attachment rather than from a
  # corpus file: a committed file is seeded, the article renders an <img> whose src is the app-owned route, and
  # that exact src serves the bytes. If any link in the chain disagrees about the key, this fails.
  describe 'end to end, from a corpus file to served bytes' do
    let(:root) { Pathname.new(Dir.mktmpdir) }

    before do
      FileUtils.mkdir_p(root.join('en', 'whatsapp'))
      FileUtils.mkdir_p(root.join('media', 'whatsapp', 'connect-number'))
      root.join('media', 'whatsapp', 'connect-number', 'step-2.png').binwrite(png)
      root.join('en', 'whatsapp', 'connect-whatsapp.md')
          .write("---\ntitle: T\nposition: 10\n---\n\n![Paste the token](media:#{key})\n")
      published.update!(content: "![Paste the token](media:#{key})")
    end

    after { FileUtils.remove_entry(root) }

    it 'renders the app-owned src and serves the bytes from it' do
      # The attachment the other examples build by hand, built instead by the seeder from the committed file.
      portal.documentation_media.each(&:purge)
      expect(Documentation::MediaSeeder.new(portal: portal.reload, root: root).perform!.uploaded).to eq(1)

      get_public "/hc/#{portal.slug}/articles/#{published.slug}"

      expect(response).to have_http_status(:ok)
      src = Nokogiri::HTML5(response.body).at_css('#cw-article-content img')['src']
      expect(src).to eq(media_path(published.slug))

      get_public src

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to eq(png)
      expect(response.media_type).to eq('image/png')
    end
  end

  # REQUESTED CHANGES #4 landed: both controllers now include Public::PortalArticleVisibility, so there is one
  # copy of the rule. This stays because it asserts the two ROUTES behave identically end to end, which sharing a
  # method does not by itself prove -- a before_action order or a scope applied elsewhere could still diverge them,
  # and `show` vs `show_markdown` (R2-O1) is the precedent for that happening.
  describe 'agreement with the article page' do
    it 'serves media exactly where the article page itself is served, for both roles' do
      [published, draft].each do |article|
        get_public "/hc/#{portal.slug}/articles/#{article.slug}"
        page_status = response.status
        get_public media_path(article.slug)

        expect(response.status).to eq(page_status), "anonymous, #{article.slug}"
      end

      sign_in(super_admin, scope: :super_admin)
      [published, draft].each do |article|
        get_public "/hc/#{portal.slug}/articles/#{article.slug}"
        page_status = response.status
        get_public media_path(article.slug)

        expect(response.status).to eq(page_status), "super admin, #{article.slug}"
      end
    end
  end
end
