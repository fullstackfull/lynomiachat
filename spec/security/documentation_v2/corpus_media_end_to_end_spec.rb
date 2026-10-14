require 'rails_helper'

# THE CORPUS HALF OF THE CHAIN, which media_end_to_end_spec.rb does not cover.
#
# That file walks an OPERATOR upload from the Super Admin route to delivered bytes. This one walks a
# REPOSITORY image through the seed run that publishes the articles around it:
#
#   custom/db/documentation/media/<key>  ->  `rake documentation:content`, i.e. ContentSeeder#perform!
#     ->  portal.documentation_media under the stable `media:` key, marked corpus-owned
#     ->  the EN article AND the AR article, which reference the same key because the media tree is
#         locale-independent
#     ->  ChatwootMarkdownRenderer#render_article through the real public pages  ->  two <img src>
#     ->  GET either src  ->  the committed bytes
#
# It exists because the seed run was the missing link: `Documentation::MediaSeeder` was implemented, specced and
# documented while no production path called it (owner item A5'-O1), so the preflight CERTIFIED a `media:`
# reference that the apply never attached. Every example here runs the real `ContentSeeder`, never the media
# seeder directly -- "the service can do it" is what was already proven, and is not the thing that was broken.
#
# The fixture is a 4x3 PNG decoded from base64. Real bytes with real dimensions, so the width and height the
# analyzer reads are checkable, and because the attach boundary identifies the content type FROM the bytes. No
# screenshot from the shipped corpus is needed or used.
RSpec.describe 'Corpus documentation media -- seed to delivered bytes', type: :request do
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:key) { 'getting-started/inbox.png' }
  let!(:super_admin) { create(:super_admin) }
  let!(:docs_portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let(:root) { Pathname.new(Dir.mktmpdir) }

  before do
    root.join('manifest.yml').write(<<~YAML)
      sections:
        - slug: getting-started
          position: 10
          icon: rocket
          en:
            name: Getting started
            description: The first thing to do.
          ar:
            name: البداية
            description: أول ما تفعله.
    YAML
    { 'en' => ['Open the inbox.', 'The inbox'], 'ar' => ['افتح صندوق الوارد.', 'صندوق الوارد'] }
      .each do |locale, (body, alt)|
      FileUtils.mkdir_p(root.join(locale, 'getting-started'))
      root.join(locale, 'getting-started', 'welcome.md')
          .write("---\ntitle: Welcome\ndescription: d\nposition: 10\n---\n\n#{body}\n\n![#{alt}](media:#{key})\n")
    end
    FileUtils.mkdir_p(root.join('media', 'getting-started'))
    root.join('media', 'getting-started', 'inbox.png').binwrite(png)
  end

  after { FileUtils.remove_entry(root) }

  # The public portal serves only on a host this installation knows itself by, which is a deployment
  # prerequisite rather than a code path, so these run with it satisfied. Same arrangement as
  # media_end_to_end_spec.rb.
  def get_public(path, **)
    with_modified_env(FRONTEND_URL: 'http://www.example.com', HELPCENTER_URL: 'http://www.example.com') do
      get(path, **)
    end
  end

  def rendered_image(path)
    get_public path
    Nokogiri::HTML5(response.body).at_css('#cw-article-content img')
  end

  def seed(portal: docs_portal, corpus: root)
    Documentation::ContentSeeder.new(portal: portal, root: corpus).perform!
  end

  # OWNER TESTS D and H together, because they are the same chain read at two locales: the per-portal corpus
  # media resolves on BOTH translations after the seed, and the src each page mints delivers the committed bytes.
  describe 'after one seed run' do
    it 'resolves the one corpus image on both the English and the Arabic page, and delivers its bytes' do
      result = seed

      # ONE attachment for the key both locales reference -- the media tree is a sibling of the locale trees, so
      # a screenshot is not duplicated per language.
      expect([result.created, result.media.uploaded, docs_portal.reload.documentation_media.count]).to eq([2, 1, 1])
      attachment = docs_portal.documentation_media.first
      expect([attachment.blob.metadata['documentation_key'],
              attachment.blob.metadata['content_source_path'].present?]).to eq([key, true])

      english = docs_portal.articles.find_by!(locale: 'en')
      arabic = docs_portal.articles.find_by!(locale: 'ar')

      # Both pages, each through the real renderer and the real per-request resolver. Presence first, so a
      # disagreement about the key reads as "nothing resolved" rather than as a NoMethodError.
      images = { 'en' => rendered_image("/hc/#{docs_portal.slug}/articles/#{english.slug}"),
                 'ar' => rendered_image("/hc/#{docs_portal.slug}/articles/#{arabic.slug}") }
      expect(images.transform_values(&:present?)).to eq('en' => true, 'ar' => true)

      # Same key, same dimensions, each page's own article-scoped src, and the alt each locale's own file wrote.
      expect([images['en']['src'], images['en']['alt'], images['en']['width'], images['en']['height']])
        .to eq(["/hc/#{docs_portal.slug}/articles/#{english.slug}/media/#{key}", 'The inbox', '4', '3'])
      expect([images['ar']['src'], images['ar']['alt'], images['ar']['width'], images['ar']['height']])
        .to eq(["/hc/#{docs_portal.slug}/articles/#{arabic.slug}/media/#{key}", 'صندوق الوارد', '4', '3'])
      # No storage path, no signed id, no blob key anywhere on either page.
      expect(response.body).not_to include(attachment.blob.signed_id, attachment.blob.key, 'storage')

      # OWNER TEST H: the src the page itself minted serves the committed bytes, for both locales.
      served = images.values.map do |image|
        get_public image['src']
        [response.status, response.media_type, response.body.b]
      end

      expect(served).to eq([[200, 'image/png', png], [200, 'image/png', png]])
    end
  end

  # OWNER TEST G: cross-portal reuse stays forbidden. The changelog portal is seeded from its OWN corpus root, so
  # it never attaches the documentation portal's key -- and a changelog article that references it anyway renders
  # nothing and is served nothing.
  describe 'the other platform portal' do
    let!(:changelog_portal) do
      create(:portal, name: 'Lynomia Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                      platform_owned: true, account: nil,
                      config: { 'allowed_locales' => ['en'], 'default_locale' => 'en', 'layout' => 'documentation' })
    end
    let(:changelog_root) { Pathname.new(Dir.mktmpdir) }

    before do
      changelog_root.join('manifest.yml').write(<<~YAML)
        sections:
          - slug: releases
            position: 10
            icon: rocket
            en:
              name: Releases
              description: What shipped.
      YAML
      FileUtils.mkdir_p(changelog_root.join('en', 'releases'))
      changelog_root.join('en', 'releases', 'release-1.md')
                    .write("---\ntitle: Release 1\ndescription: d\nposition: 10\n---\n\nShipped.\n\n![The inbox](media:#{key})\n")
    end

    after { FileUtils.remove_entry(changelog_root) }

    it 'cannot resolve or deliver a corpus key seeded into the documentation portal' do
      seed
      # Its own corpus has no media/ directory at all, so its reference has no file: the preflight refuses it
      # rather than letting it adopt the documentation portal's attachment, which is the forbidden reuse stated
      # as a seed-time refusal.
      expect { seed(portal: changelog_portal, corpus: changelog_root) }
        .to raise_error(Documentation::ContentSeeder::PreflightError, /has no file at/)
      expect(changelog_portal.reload.documentation_media.count).to eq(0)

      # And with the reference published by hand anyway -- the case a corpus refusal cannot prevent, because an
      # operator can type it into the editor -- the renderer resolves against the portal being rendered.
      note = create(:article, portal: changelog_portal, account_id: nil, author: super_admin, locale: 'en',
                              slug: 'release-1', title: 'Release 1', status: :published,
                              content: "![The inbox](media:#{key})")

      expect(rendered_image("/hc/#{changelog_portal.slug}/articles/#{note.slug}")).to be_nil
      expect(response.body).to include("<!-- media: unresolved key #{key} -->")

      get_public "/hc/#{changelog_portal.slug}/articles/#{note.slug}/media/#{key}"
      refused = [response.status, response.body, response.headers['Location']]

      # The control, without which the 404 could mean the key is simply broken: the portal it WAS seeded into
      # serves it.
      english = docs_portal.articles.find_by!(locale: 'en')
      get_public "/hc/#{docs_portal.slug}/articles/#{english.slug}/media/#{key}"

      expect(refused).to eq([404, '', nil])
      expect([response.status, response.body.b]).to eq([200, png])
    end
  end
end
