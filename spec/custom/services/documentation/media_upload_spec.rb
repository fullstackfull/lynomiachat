require 'rails_helper'

# Owner correction F1: documentation has its OWN Super Admin upload path, on the same portal namespace and the
# same key grammar as the seeded corpus. These examples pin the two things that makes safe -- an operator key can
# never collide with a seeded one, and the provenance marker distinguishes the two -- plus the validations that
# exist here because this is the single shared attach boundary.
describe Documentation::MediaUpload do
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:other_png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAYAAAACCAAAAABeNvKCAAAAC0lEQVR4nGNgQAYAAA4AAamRc7EAAAAASUVORK5CYII=') }
  let(:gif) do
    "GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00," \
    "\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b
  end
  let(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil)
  end
  let(:upload) { described_class.new(portal: portal) }

  describe '#create!' do
    it 'allocates a key under the reserved segment and returns the Markdown to insert' do
      result = upload.create!(io: StringIO.new(png), filename: 'Step Two.png', alt: 'Paste the token')

      expect(result.key).to match(%r{\Auploads/[0-9a-f]{16}-step-two\.png\z})
      expect(Documentation::MediaResolver).to be_valid_key(result.key)
      expect(Documentation::MediaResolver).to be_operator_key(result.key)
      expect(result.markdown).to eq("![Paste the token](media:#{result.key})")
      expect([result.width, result.height]).to eq([4, 3])
      expect(result.replaced).to be(false)
    end

    it 'derives the extension from the bytes, not from the uploaded filename' do
      result = upload.create!(io: StringIO.new(gif), filename: 'screenshot.png', alt: 'A divider')

      expect(result.key).to end_with('.gif')
    end

    # The product ships Arabic, so a filename that parameterizes to nothing is an ordinary case, not an edge one.
    it 'falls back to a usable slug when the filename yields none' do
      ['شرح.png', '___.png'].each do |filename|
        key = upload.create!(io: StringIO.new(png), filename: filename, alt: 'Alt').key

        expect(key).to match(%r{\Auploads/[0-9a-f]{16}-image\.png\z}), filename
      end
    end

    # Measured: File.basename('.png', '.*') is '.png', which parameterizes to 'png' -- a usable slug, so this is
    # not the no-slug case and the fallback is not reached.
    it 'keeps the slug a dotfile name yields' do
      expect(upload.create!(io: StringIO.new(png), filename: '.png', alt: 'Alt').key)
        .to match(%r{\Auploads/[0-9a-f]{16}-png\.png\z})
    end

    it 'marks the attachment as operator-owned by leaving the provenance absent' do
      key = upload.create!(io: StringIO.new(png), filename: 'a.png', alt: 'Alt').key
      blob = portal.reload.documentation_media.find { |a| a.blob.metadata['documentation_key'] == key }.blob

      expect(blob.metadata['content_source_path']).to be_nil
      expect(blob.metadata['documentation_key']).to eq(key)
    end

    it 'refuses a blank alt, because alt is the public search snippet as well as the accessible name' do
      ['', '   ', nil].each do |alt|
        expect { upload.create!(io: StringIO.new(png), filename: 'a.png', alt: alt) }
          .to raise_error(described_class::Error, /Alt text is required/)
      end
      expect(portal.reload.documentation_media).to be_empty
    end

    # A bracket in the alt would otherwise end the image node early, and section 0.3 showed that a malformed
    # destination is published as literal Markdown rather than failing visibly.
    it 'escapes brackets and collapses newlines in the alt it writes into the Markdown' do
      result = upload.create!(io: StringIO.new(png), filename: 'a.png', alt: "Step 2 [see\nnote]")

      expect(result.markdown).to eq("![Step 2 \\[see note\\]](media:#{result.key})")
    end

    it 'refuses a type outside the raster allowlist, including SVG, before anything is uploaded' do
      svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>'

      expect { upload.create!(io: StringIO.new(svg), filename: 'logo.svg', alt: 'Logo') }
        .to raise_error(described_class::Error, %r{image/svg\+xml is not permitted})
        .and(not_change(ActiveStorage::Blob, :count))
      expect { upload.create!(io: StringIO.new('not an image'), filename: 'a.png', alt: 'Alt') }
        .to raise_error(described_class::Error, /not permitted/)
        .and(not_change(ActiveStorage::Blob, :count))
    end

    it 'refuses bytes over the cap' do
      stub_const("#{described_class}::MAX_BYTES", 10)

      expect { upload.create!(io: StringIO.new(png), filename: 'a.png', alt: 'Alt') }
        .to raise_error(described_class::Error, /the cap is 10/)
        .and(not_change(ActiveStorage::Blob, :count))
    end

    it 'never collides with a seeded key, because the two namespaces are disjoint' do
      upload.attach!(key: 'whatsapp/step-2.png', io: StringIO.new(png), filename: 'step-2.png',
                     content_source_path: 'custom/db/documentation/media/whatsapp/step-2.png')

      key = upload.create!(io: StringIO.new(other_png), filename: 'step-2.png', alt: 'Alt').key

      expect(key).not_to eq('whatsapp/step-2.png')
      expect(portal.reload.documentation_media.count).to eq(2)
    end
  end

  describe '#replace!' do
    let!(:created) { upload.create!(io: StringIO.new(png), filename: 'a.png', alt: 'Alt') }

    it 'keeps the key, swaps the bytes and purges the old blob only after the new one is attached' do
      old_blob = portal.reload.documentation_media.first.blob

      result = described_class.new(portal: portal.reload)
                              .replace!(key: created.key, io: StringIO.new(other_png), filename: 'b.png')

      expect(result.key).to eq(created.key)
      expect(result.replaced).to be(true)
      expect([result.width, result.height]).to eq([6, 2])
      expect(portal.reload.documentation_media.count).to eq(1)
      expect(portal.documentation_media.first.blob.id).not_to eq(old_blob.id)
    end

    it 'refuses to replace a key the SEEDER owns, because the corpus wins for corpus content' do
      upload.attach!(key: 'whatsapp/step-2.png', io: StringIO.new(png), filename: 'step-2.png',
                     content_source_path: 'custom/db/documentation/media/whatsapp/step-2.png')

      expect do
        described_class.new(portal: portal.reload)
                       .replace!(key: 'whatsapp/step-2.png', io: StringIO.new(other_png), filename: 'b.png')
      end.to raise_error(described_class::Error, /seeded from the corpus/)
    end

    it 'refuses a key this portal has nothing attached at' do
      expect { upload.replace!(key: 'uploads/0000000000000000-x.png', io: StringIO.new(png), filename: 'b.png') }
        .to raise_error(described_class::Error, /No documentation media is attached/)
    end
  end

  describe '#attach!' do
    it 'refuses a key that fails the grammar, so no caller can bypass it' do
      expect { upload.attach!(key: 'WhatsApp/Step.PNG', io: StringIO.new(png), filename: 'a.png') }
        .to raise_error(described_class::Error, /not a valid documentation media key/)
    end

    it 'records the corpus file as provenance when the seeder passes one' do
      blob = upload.attach!(key: 'whatsapp/step-2.png', io: StringIO.new(png), filename: 'step-2.png',
                            content_source_path: 'custom/db/documentation/media/whatsapp/step-2.png')

      expect(blob.metadata['content_source_path']).to eq('custom/db/documentation/media/whatsapp/step-2.png')
    end

    # The key must survive analysis, which is what makes metadata a safe home for it: blob.analyze merges.
    it 'keeps the key and the provenance after analysis has written the dimensions' do
      blob = upload.attach!(key: 'whatsapp/step-2.png', io: StringIO.new(png), filename: 'step-2.png',
                            content_source_path: 'a/b.png')

      expect(blob.reload.metadata).to include('documentation_key' => 'whatsapp/step-2.png',
                                              'content_source_path' => 'a/b.png', 'width' => 4, 'height' => 3)
    end

    it 'stores the basename in filename, because a slash-bearing filename would read back lossily' do
      blob = upload.attach!(key: 'whatsapp/connect-number/step-2.png', io: StringIO.new(png),
                            filename: 'step-2.png')

      expect(blob.filename.to_s).to eq('step-2.png')
    end
  end
end
