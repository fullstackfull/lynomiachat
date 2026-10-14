# Lynomia documentation media: the one place bytes become a documentation attachment.
#
# Owner correction F1 (docs/documentation-v2/P2-WORKSTREAM-OWNERSHIP.md) gives documentation its OWN Super
# Admin-only upload path, on the same portal namespace, addressed by the same `media:` key grammar and resolved
# by the same Documentation::MediaResolver. Seeded media and operator-uploaded media are one abstraction.
#
# The bare ActiveStorage::DirectUploadsController route is NOT relaxed by this and is not reached for: it still
# answers 403 (config/initializers/active_storage.rb:52-63). This is an ordinary service called from an
# authenticated Super Admin action.
#
# `attach!` being the single attach boundary is the point. CLAUDE.md asks for enforcement at the earliest SHARED
# entry point, and for "these bytes become documentation media under this key" that point is one method -- so the
# content-type check, the byte cap, the metadata shape, the replace-then-purge order and the synchronous analyze
# exist exactly once, for the corpus path and the operator path alike. Documentation::MediaSeeder calls it too.
class Documentation::MediaUpload
  class Error < StandardError; end

  # Raster only, no SVG (contract item 5). The mechanism that forces image/svg+xml to octet-stream + attachment
  # on the way out is also the stored-XSS defence, and is not to be relaxed; refusing SVG at the boundary means
  # that defence never has to be the last line. The value is the extension an allocated key gets (section 9.1).
  CONTENT_TYPES = { 'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/gif' => 'gif', 'image/webp' => 'webp' }.freeze
  MAX_BYTES = 2.megabytes

  # 16 lowercase hex characters, which the key grammar accepts as-is. Collision inside the operator namespace is
  # a 2^-64 event and is NOT what makes the namespaces disjoint -- the reserved first segment is (section 9.1) --
  # so this needs no retry loop.
  TOKEN_BYTES = 8
  MAX_SLUG_LENGTH = 60

  # An Arabic filename parameterizes to the empty string, and this product ships Arabic
  # (Documentation::Library::LOCALES). So this is an ordinary case, not a speculative guard.
  FALLBACK_SLUG = 'image'.freeze

  Result = Struct.new(:key, :markdown, :width, :height, :replaced, keyword_init: true)

  def initialize(portal:)
    @portal = portal
  end

  # EVERYTHING DECIDABLE FROM THE BYTES, in one public method, so a seed PREFLIGHT can decide it before any
  # write. Owner ruling 3 asks for exactly that, and these two were the last decidable defects left inside the
  # write loop: measured consequence, a corpus whose second image was a 2.5 MB screenshot (the cap is 2 MB) or a
  # `.png` holding SVG uploaded the first image and then raised. `attach!` calls this too, so the preflight and
  # the boundary cannot drift: there is one implementation, judged on the same bytes.
  #
  # `key` is only for the message. The seeder passes the `media:` key; `create!` passes the file name, because
  # an operator uploading a too-large image has no key yet and the file name is what they recognise.
  def validate_bytes!(key:, io:)
    content_type = content_type_for!(io, key)
    raise Error, "#{key} is #{io.size} bytes; the cap is #{MAX_BYTES}." if io.size > MAX_BYTES

    content_type
  end

  # The operator path. Allocates a key that cannot collide with a seeded one and returns the finished Markdown
  # for the editor to insert at the caret, so the grammar is never transcribed into JS and the alt requirement
  # cannot be skipped client-side.
  def create!(io:, filename:, alt:)
    alt = alt.to_s.strip
    raise Error, 'Alt text is required: it is the public search snippet as well as the accessible name.' if alt.blank?

    # The key's extension comes from the verified content type, so the type has to be known before the key is
    # allocated. `attach!` judges the same bytes again rather than being handed a type to trust.
    content_type = validate_bytes!(key: File.basename(filename.to_s), io: io)
    key = allocate_key(filename, content_type)
    blob = attach!(key: key, io: io, filename: filename)

    Result.new(key: key, markdown: markdown_for(key, alt),
               width: blob.metadata['width'], height: blob.metadata['height'], replaced: false)
  end

  # Replacement (F1): same key, new bytes, so the reference already in the article keeps working and its alt is
  # untouched. There is no markdown to return for the same reason.
  def replace!(key:, io:, filename:)
    existing = attachment_for(key)
    raise Error, "No documentation media is attached to this portal at #{key}." if existing.nil?
    # The corpus is the source of truth for corpus content (F2 class A), so replacing a seeded image's bytes in
    # the database would be silently reverted by the next seed. Refuse the edit that cannot survive instead.
    raise Error, "#{key} is seeded from the corpus; change the file in the repository instead." if seeded?(existing)

    blob = attach!(key: key, io: io, filename: filename)
    Result.new(key: key, markdown: nil, width: blob.metadata['width'], height: blob.metadata['height'], replaced: true)
  end

  # The shared attach boundary. content_source_path nil means no corpus file owns these bytes, which is exactly
  # an operator upload -- one vocabulary with Agent 5's row provenance (MediaResolver::SOURCE_PATH_METADATA).
  def attach!(key:, io:, filename:, content_source_path: nil)
    raise Error, "#{key.inspect} is not a valid documentation media key." unless Documentation::MediaResolver.valid_key?(key)

    # No `content_type:` parameter: a type supplied by a caller is a claim, and the bytes are the fact. Both
    # callers now go through the same check, which is also what the seed preflight calls.
    content_type = validate_bytes!(key: key, io: io)
    previous = attachment_for(key)
    blob = upload(key, io, filename, content_type, content_source_path)
    # Only after the new attachment has succeeded (contract item 8). A row without bytes is a broken published
    # page; bytes without a row are an orphan the next run reclaims, so this order is the safe one. Transiently
    # two attachments carry one key, which is why correctness comes from the order here and never from resolver
    # ordering -- the generated association has no ORDER BY, so "the newer one" is not a thing to rely on.
    previous&.purge_later
    blob
  end

  private

  attr_reader :portal

  def upload(key, io, filename, content_type, content_source_path)
    io.rewind if io.respond_to?(:rewind)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: io, filename: File.basename(filename.to_s), content_type: content_type, identify: false,
      metadata: { Documentation::MediaResolver::KEY_METADATA => key,
                  Documentation::MediaResolver::SOURCE_PATH_METADATA => content_source_path }.compact
    )
    # Synchronously, and before attaching: the attachment's own after_create_commit calls `analyze_later unless
    # analyzed?` (activestorage-7.2.3.2/app/models/active_storage/attachment.rb:127,137), so analyzing first both
    # skips the job and makes a missing libvips a visible seed count rather than a silent SEO regression.
    blob.analyze
    portal.documentation_media.attach(blob)
    # AN ATTACH THAT ATTACHED NOTHING MUST NOT REPORT SUCCESS. `Attached::Many#attach` saves the record only
    # `if record.persisted? && !record.changed?`, and on a failed save it does `return if !record.save`
    # (activestorage-7.2.3.2/lib/active_storage/attached/many.rb:51-57) -- so a portal that is dirty, or one whose
    # association target holds an invalid unsaved child, leaves the attachment pending in memory and this method
    # would still return the blob. Measured: the corpus media pass counted `uploaded: 1` against zero attachment
    # rows. The cause is fixed where it was created (ContentSeeder#plan_file), and this is the loud failure if it
    # ever recurs -- read from the database rather than from the in-memory proxy, which is what was lying.
    # `name:` as well as `record:`, because one blob can be attached to several records AND under several names:
    # without it, a blob that happened to be the portal's `logo` would satisfy the check while the
    # documentation_media attach had failed. The name comes from the association itself -- `Attached` declares
    # `attr_reader :name` (activestorage-7.2.3.2/lib/active_storage/attached.rb:11) -- rather than from a third
    # copy of the string. Read from the BLOB side, because `portal.documentation_media` returns the PENDING
    # change's attachments when one exists (attached/many.rb:32-34), which is the in-memory state that lied.
    unless blob.attachments.exists?(record: portal, name: portal.documentation_media.name)
      # The blob row and its stored object already exist by here, and nothing in this application reclaims an
      # unattached blob (app/models/portal.rb says so of the media namespace). Purged before raising, so a
      # failure that recurs does not leave one orphan row and one orphan object per attempt per key.
      blob.purge
      raise Error, "#{key} was not attached to #{portal.slug}: #{portal.errors.full_messages.to_sentence.presence || 'the record would not save'}."
    end

    blob
  end

  # The bytes are the fact and the extension is the author's claim, so the type is identified from the content
  # with ActiveStorage's own identifier -- used directly here so a bad type fails BEFORE anything is uploaded.
  # The message names what is being refused, because a seed run can refuse one file out of many and "image/svg+xml
  # is not permitted" on its own does not say which.
  def content_type_for!(io, key)
    io.rewind if io.respond_to?(:rewind)
    type = Marcel::MimeType.for(io)
    return type if CONTENT_TYPES.key?(type)

    raise Error, "#{key}: #{type} is not permitted; documentation media must be one of " \
                 "#{CONTENT_TYPES.keys.join(', ')} (raster only, no SVG)."
  end

  # `uploads/<16 hex>-<slug>.<ext>`: two segments, so it matches the frozen key grammar with no change to it. The
  # slug is in the key because the key is visible in the article Markdown an operator reads and edits, and the
  # extension comes from the verified content type so it is true by construction.
  def allocate_key(filename, content_type)
    key = "#{Documentation::MediaResolver::OPERATOR_SEGMENT}/" \
          "#{SecureRandom.hex(TOKEN_BYTES)}-#{slug_for(filename)}.#{CONTENT_TYPES.fetch(content_type)}"
    # A permanent two-attachments-one-key state would be a bug rather than the brief window `attach!` tolerates,
    # and CLAUDE.md says an impossible state fails loudly instead of being silently worked around.
    raise Error, "#{key} is already attached to this portal." if attachment_for(key)

    key
  end

  # `parameterize` alone is not enough: measured, it leaves underscores through ("___.png" -> "___"), and `_` is
  # not in the key grammar's character set. So the result is filtered to the grammar, squeezed and stripped, and
  # only then truncated -- re-stripping afterwards, because a truncation can land on a hyphen.
  def slug_for(filename)
    slug = File.basename(filename.to_s, '.*').parameterize
               .gsub(/[^a-z0-9-]/, '-').squeeze('-').delete_prefix('-').delete_suffix('-')
               .first(MAX_SLUG_LENGTH).sub(/-+\z/, '')
    slug.presence || FALLBACK_SLUG
  end

  def markdown_for(key, alt)
    # `[`, `]` and `\` are backslash-escaped and newlines collapsed because an operator typing "Step 2 [see
    # note]" would otherwise produce a destination CommonMark does not read as an image -- and a malformed image
    # node is published as literal Markdown rather than failing visibly (interface section 0.3).
    escaped = alt.gsub(/[\\\[\]]/) { |char| "\\#{char}" }.gsub(/\s+/, ' ')
    "![#{escaped}](#{Documentation::MediaResolver::SCHEME}#{key})"
  end

  def attachment_for(key)
    portal.documentation_media.includes(:blob).detect do |attachment|
      attachment.blob.metadata[Documentation::MediaResolver::KEY_METADATA] == key
    end
  end

  def seeded?(attachment)
    attachment.blob.metadata[Documentation::MediaResolver::SOURCE_PATH_METADATA].present?
  end
end
