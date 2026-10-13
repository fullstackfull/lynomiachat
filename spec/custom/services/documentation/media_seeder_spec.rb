require 'rails_helper'

# The seeder is operator-run and idempotent in the same way ContentSeeder is: the files are the source, and a
# re-run updates rather than duplicates. These examples seed a temporary corpus rather than the shipped one, so
# they assert the seeder's behaviour instead of restating the contents of custom/db/documentation.
#
# The example that matters most is the orphan sweep: contract item 9 as amended by owner correction F1.1 purges
# only what the SEEDER created, because an operator upload has no corpus file by construction and the unamended
# sweep would delete every one of them on the next seed.
describe Documentation::MediaSeeder do
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:other_png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAYAAAACCAAAAABeNvKCAAAAC0lEQVR4nGNgQAYAAA4AAamRc7EAAAAASUVORK5CYII=') }
  let(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil)
  end
  let(:root) { Pathname.new(Dir.mktmpdir) }

  before { FileUtils.mkdir_p(root.join('en', 'whatsapp')) }

  after { FileUtils.remove_entry(root) }

  # Two helpers only, because each removes real repeated setup: a corpus article is a file in a locale/section
  # directory, and a media file is bytes at a path under media/.
  def article(body, name: 'connect-whatsapp', locale: 'en', section: 'whatsapp')
    FileUtils.mkdir_p(root.join(locale, section))
    root.join(locale, section, "#{name}.md").write("---\ntitle: T\nposition: 10\n---\n\n#{body}\n")
  end

  def media(key, bytes = png)
    path = root.join('media', key)
    FileUtils.mkdir_p(path.dirname)
    path.binwrite(bytes)
  end

  def seed = described_class.new(portal: portal.reload, root: root).perform!

  def keys_attached
    portal.reload.documentation_media.map { |a| a.blob.metadata['documentation_key'] }
  end

  describe 'the happy path' do
    before do
      article('![Step two: paste the token](media:whatsapp/connect-number/step-2.png)')
      media('whatsapp/connect-number/step-2.png')
    end

    it 'uploads each referenced file once and records the corpus file as its provenance' do
      result = seed

      expect(result.uploaded).to eq(1)
      expect(keys_attached).to eq(['whatsapp/connect-number/step-2.png'])
      blob = portal.documentation_media.first.blob
      expect(blob.metadata['content_source_path'])
        .to eq(root.join('media/whatsapp/connect-number/step-2.png').relative_path_from(Rails.root).to_s)
      expect([blob.metadata['width'], blob.metadata['height']]).to eq([4, 3])
    end

    # The property that makes it safe to run on every deploy.
    it 'changes nothing when run again' do
      seed
      second = seed
      third = seed

      expect([second.uploaded, second.replaced, second.unchanged]).to eq([0, 0, 1])
      expect([third.uploaded, third.replaced, third.unchanged]).to eq([0, 0, 1])
      expect(portal.reload.documentation_media.count).to eq(1)
    end

    it 'reports nothing unmeasured when the host can read the dimensions' do
      expect(seed.unmeasured).to eq(0)
    end

    # One blob for one screenshot referenced by both translations: the media tree is locale-independent.
    it 'uploads one blob for a key both locales reference' do
      article('![Step two](media:whatsapp/connect-number/step-2.png)', locale: 'ar')

      expect(seed.uploaded).to eq(1)
      expect(portal.reload.documentation_media.count).to eq(1)
    end
  end

  describe 'replacement' do
    it 'attaches the new blob and purges the old one when the bytes change' do
      article('![Step two](media:whatsapp/connect-number/step-2.png)')
      media('whatsapp/connect-number/step-2.png')
      seed
      first_blob = portal.reload.documentation_media.first.blob

      media('whatsapp/connect-number/step-2.png', other_png)
      result = seed

      expect([result.uploaded, result.replaced, result.unchanged]).to eq([0, 1, 0])
      expect(portal.reload.documentation_media.count).to eq(1)
      expect(portal.documentation_media.first.blob.id).not_to eq(first_blob.id)
      expect(portal.documentation_media.first.blob.metadata['width']).to eq(6)
    end
  end

  describe 'the orphan sweep' do
    it 'purges a seeded attachment whose key has left the corpus' do
      article('![Step two](media:whatsapp/connect-number/step-2.png)')
      media('whatsapp/connect-number/step-2.png')
      seed

      article('No images any more.')
      result = seed

      expect(result.purged).to eq(1)
      expect(keys_attached).to be_empty
    end

    # Owner correction F1.1, and the single most important example in this file.
    it 'never touches an operator upload, which has no corpus file by construction' do
      operator = Documentation::MediaUpload.new(portal: portal)
                                           .create!(io: StringIO.new(png), filename: 'pasted.png', alt: 'Alt')
      article('No images any more.')

      result = seed

      expect(result.purged).to eq(0)
      expect(keys_attached).to eq([operator.key])
    end

    it 'never touches the other platform portal`s media, nor the portal logo' do
      changelog = create(:portal, name: 'Lynomia Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                                  platform_owned: true, account: nil)
      Documentation::MediaUpload.new(portal: changelog)
                                .attach!(key: 'releases/a.png', io: StringIO.new(png), filename: 'a.png',
                                         content_source_path: 'custom/db/changelog/media/releases/a.png')
      portal.logo.attach(io: StringIO.new(png), filename: 'logo.png', content_type: 'image/png')
      article('No images any more.')

      expect(seed.purged).to eq(0)
      expect(changelog.reload.documentation_media.count).to eq(1)
      expect(portal.reload.logo).to be_attached
    end
  end

  describe 'enforcement at the seed boundary' do
    before { media('whatsapp/connect-number/step-2.png') }

    it 'fails on empty alt text, and writes nothing' do
      article('![](media:whatsapp/connect-number/step-2.png)')

      expect { seed }.to raise_error(described_class::Error, /has empty alt text/)
      expect(portal.reload.documentation_media).to be_empty
    end

    it 'fails on a key that is not in the grammar' do
      article('![Alt](media:WhatsApp/Step.PNG)')

      expect { seed }.to raise_error(described_class::Error, /is not a valid media key/)
    end

    # The one case a parser cannot see: CommonMark does not read it as an image at all, so the Markdown source
    # itself would be published and no renderer or resolver would ever be called.
    it 'fails on a destination containing a space, which is not an image node at all' do
      article('![Alt](media:whatsapp/connect-number/step 2.png)')

      expect { seed }.to raise_error(described_class::Error, /contains a space/)
    end

    it 'fails on a `media:` key used as a link destination' do
      article('See [the screenshot](media:whatsapp/connect-number/step-2.png).')

      expect { seed }.to raise_error(described_class::Error, /used as a link destination/)
    end

    it 'fails on a corpus file in the reserved operator namespace' do
      article('![Alt](media:uploads/8f3a1c2b5d7e9a04-step.png)')
      media('uploads/8f3a1c2b5d7e9a04-step.png')

      expect { seed }.to raise_error(described_class::Error, %r{reserved `uploads/` namespace})
    end

    it 'fails when a referenced key has no file, naming the corpus file and line' do
      article("Intro.\n\n![Alt](media:whatsapp/missing.png)")

      expect { seed }.to raise_error(described_class::Error, /connect-whatsapp\.md:8.*has no file/)
    end

    it 'fails on a non-raster file, naming the key rather than a storage path' do
      article('![Alt](media:whatsapp/logo.png)')
      media('whatsapp/logo.png', '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>')

      expect { seed }.to raise_error(described_class::Error) do |error|
        expect(error.message).to match(%r{media:whatsapp/logo\.png.*not permitted})
        expect(error.message).not_to include('storage', Rails.root.to_s)
      end
    end
  end

  describe 'unreferenced files' do
    it 'counts them without failing, because they are committed and reviewed in diffs' do
      article('![Step two](media:whatsapp/connect-number/step-2.png)')
      media('whatsapp/connect-number/step-2.png')
      media('whatsapp/spare.png', other_png)

      result = seed

      expect(result.uploaded).to eq(1)
      expect(result.unreferenced).to eq(1)
    end
  end
end
