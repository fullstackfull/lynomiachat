require 'rails_helper'

# The resolver is the one place the `media:` key grammar lives (R2-MEDIA-INTERFACE.md section 1.5) and the one
# place a key becomes a blob. These examples pin the two properties the rest of R2 is built on: the grammar
# rejects everything the contract says it rejects, and resolution is per-portal with no cross-portal fallback.
describe Documentation::MediaResolver do
  # 68 bytes, 4x3, grayscale. Built by hand rather than committed as a fixture so the dimensions are visible in
  # the spec that asserts them, and so no spec depends on a binary file it cannot read.
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil)
  end
  let(:other_portal) do
    create(:portal, name: 'Lynomia Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                    platform_owned: true, account: nil)
  end
  let(:article) do
    create(:article, title: 'Connect WhatsApp', slug: 'connect-whatsapp', content: 'Body', locale: 'en',
                     portal: portal, account_id: nil, author: create(:super_admin))
  end
  let(:resolver) { described_class.new(portal: portal, article: article) }

  def attach(target_portal, key, bytes = png)
    Documentation::MediaUpload.new(portal: target_portal)
                              .attach!(key: key, io: StringIO.new(bytes), filename: File.basename(key),
                                       content_source_path: "custom/db/documentation/media/#{key}")
  end

  describe '.valid_key?' do
    it 'accepts the documented form' do
      expect(described_class).to be_valid_key('whatsapp/connect-number/step-2.png')
    end

    it 'accepts every permitted extension and two to five segments' do
      %w[a/b.png a/b.jpg a/b.jpeg a/b.gif a/b.webp a/b/c/d/e.png].each do |key|
        expect(described_class).to be_valid_key(key), key
      end
    end

    # Each row is a rejection the contract names, with the reason it names.
    {
      'whatsapp/step 2.png' => 'a space is not an image node at all',
      '../../etc/passwd' => 'traversal is a grammar violation',
      '/absolute/x.png' => 'a leading slash is not a segment',
      'eyJfcmFpbHMiOnt9fQ==.png' => 'an ActiveStorage signed id is base64, and uppercase is rejected',
      '' => 'the empty key parses as an image, so it is rejected explicitly',
      'x.png' => 'one segment is below the minimum depth',
      'a/b.png?cw_image_width=400px' => 'a query string is part of the key and the width is never read',
      'a/b.png#frag' => 'a fragment is not in the character set',
      'a%2Fb.png' => 'a pre-escaped key would be a distinct, unmatchable string',
      'WhatsApp/Step.PNG' => 'uppercase would seed on one filesystem and 404 on another',
      'a/b.svg' => 'raster only, no SVG',
      'a/b/c/d/e/f.png' => 'six segments is past the maximum depth',
      'a/-b.png' => 'a segment may not start with a hyphen',
      'a/b_c.png' => 'an underscore is not in the character set'
    }.each do |key, reason|
      it "rejects #{key.inspect} because #{reason}" do
        expect(described_class).not_to be_valid_key(key)
      end
    end

    it 'rejects a key longer than the 200 character cap' do
      expect(described_class).not_to be_valid_key("a/#{'b' * 200}.png")
    end
  end

  describe '.operator_key?' do
    it 'is true only under the reserved first segment' do
      expect(described_class).to be_operator_key('uploads/8f3a1c2b5d7e9a04-step.png')
      expect(described_class).not_to be_operator_key('whatsapp/uploads/step.png')
      expect(described_class).not_to be_operator_key('uploaded/step.png')
    end
  end

  describe '#resolve' do
    it 'returns the blob, its content type, size and intrinsic dimensions' do
      attach(portal, 'whatsapp/connect-number/step-2.png')

      image = resolver.resolve('whatsapp/connect-number/step-2.png')

      expect(image.key).to eq('whatsapp/connect-number/step-2.png')
      expect(image.content_type).to eq('image/png')
      expect(image.byte_size).to eq(png.bytesize)
      expect([image.width, image.height]).to eq([4, 3])
    end

    it 'returns nil rather than raising for a key that fails the grammar' do
      expect(resolver.resolve('WhatsApp/Step.PNG')).to be_nil
      expect(resolver.resolve(nil)).to be_nil
    end

    it 'returns nil for a valid key this portal has no attachment for' do
      expect(resolver.resolve('whatsapp/connect-number/step-2.png')).to be_nil
    end

    # Contract section 0.2: the namespace is per-portal and there is no cross-portal fallback, deliberately --
    # otherwise one corpus's purge could break the other corpus's article.
    it 'does not resolve a key attached to the OTHER platform portal' do
      attach(other_portal, 'whatsapp/connect-number/step-2.png')

      expect(resolver.resolve('whatsapp/connect-number/step-2.png')).to be_nil
      expect(described_class.new(portal: other_portal, article: article)
                            .resolve('whatsapp/connect-number/step-2.png')).to be_present
    end

    it 'never exposes a signed id, a blob id or a storage path in the path it builds' do
      blob = attach(portal, 'whatsapp/connect-number/step-2.png')

      path = resolver.resolve('whatsapp/connect-number/step-2.png').path

      expect(path).to eq("/hc/#{portal.slug}/articles/#{article.slug}/media/whatsapp/connect-number/step-2.png")
      expect(path).not_to include(blob.signed_id, blob.id.to_s, blob.key, 'storage')
      expect(path).to start_with('/')
    end
  end

  # The N+1 answer, asserted rather than argued: the set is loaded once per instance, so twenty resolve calls
  # cost the same two queries as one.
  describe 'query cost' do
    it 'loads the portal media set once however many keys are resolved' do
      keys = Array.new(5) { |i| "whatsapp/connect-number/step-#{i}.png" }
      keys.each { |key| attach(portal, key) }
      fresh = described_class.new(portal: portal.reload, article: article)

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
        queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:sql].start_with?('BEGIN', 'COMMIT')
      end
      keys.each { |key| expect(fresh.resolve(key)).to be_present }
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(queries.length).to eq(2)
    end
  end

  describe '#keys' do
    it 'lists this portal`s attached keys, for the seeder`s orphan pass' do
      attach(portal, 'whatsapp/a.png')
      attach(portal, 'commerce/b.png')
      attach(other_portal, 'whatsapp/c.png')

      expect(described_class.new(portal: portal.reload, article: article).keys)
        .to contain_exactly('whatsapp/a.png', 'commerce/b.png')
    end
  end
end
