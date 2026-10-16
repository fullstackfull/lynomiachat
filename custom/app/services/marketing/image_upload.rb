# The one place bytes become a marketing image.
#
# ITS OWN ATTACHMENT NAME, NOT THE DOCUMENTATION NAMESPACE. `site_pages.marketing_images` is separate from
# `portal.documentation_media` by design (docs/official-website/04-information-architecture.md D10): the
# documentation corpus reclaims orphan media it owns, and nothing that sweep does may reach a marketing image
# or the other way round. So this is a small service of its own rather than a branch inside
# Documentation::MediaUpload -- which also keys its blobs by a `media:` grammar that means nothing here.
#
# WHAT IS SHARED IS THE RULE, NOT THE CODE, and deliberately so: raster only, a byte cap, the type identified
# from the CONTENT rather than from the filename, and a synchronous `analyze` before the attach. Each of those
# is a line here and a line there; the alternative is a shared superclass whose two subclasses disagree about
# what they key on.
#
# NO SVG. An SVG is a script container, and this repository has already paid for a stored XSS
# (docs/documentation-v2/P0-PRODUCTION-HARDENING.md). Marketing::MediaController forces a non-inline
# disposition for one anyway; refusing it at the boundary means that is never the last line of defence.
class Marketing::ImageUpload
  class Error < StandardError; end

  CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  MAX_BYTES = 2.megabytes

  def initialize(page:)
    @page = page
  end

  # Returns the new attachment, whose id is what an `image` section and the SEO panel reference.
  def attach!(io:, filename:)
    raise Error, 'Choose a file to upload.' unless io.respond_to?(:read)

    content_type = content_type_for!(io)
    raise Error, "That file is #{io.size} bytes; the limit is #{MAX_BYTES}." if io.size > MAX_BYTES

    blob = build_blob(io, filename, content_type)
    page.marketing_images.attach(blob)
    confirm_attached!(blob)
    blob.attachments.find_by(record: page, name: page.marketing_images.name)
  end

  private

  attr_reader :page

  # The bytes are the fact; the extension is a claim. ActiveStorage's own identifier, used before anything is
  # uploaded, so a `.png` holding an SVG is refused rather than stored.
  def content_type_for!(io)
    io.rewind if io.respond_to?(:rewind)
    type = Marcel::MimeType.for(io)
    return type if CONTENT_TYPES.include?(type)

    raise Error, "#{type} is not an allowed image type; use one of #{CONTENT_TYPES.join(', ')} (no SVG)."
  end

  def build_blob(io, filename, content_type)
    io.rewind if io.respond_to?(:rewind)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: io, filename: File.basename(filename.to_s), content_type: content_type, identify: false
    )
    # SYNCHRONOUSLY AND BEFORE THE ATTACH. The attachment's own after_create_commit calls `analyze_later
    # unless analyzed?`, so analyzing first both skips the job and makes a missing libvips a visible failure
    # here rather than an image rendered with no width or height -- which is a layout shift on every first
    # view and an SEO regression nobody would attribute to an upload.
    blob.analyze
    blob
  end

  # AN ATTACH THAT ATTACHED NOTHING MUST NOT REPORT SUCCESS. `Attached::Many#attach` saves the record only
  # when it is persisted and not dirty, and returns quietly on a failed save -- so the in-memory proxy can
  # list an attachment that is not in the database. Read from the blob side, which is the state that cannot
  # lie, and purge before raising so a recurring failure does not leave an orphan per attempt.
  def confirm_attached!(blob)
    return if blob.attachments.exists?(record: page, name: page.marketing_images.name)

    blob.purge
    raise Error, "The image was not attached: #{page.errors.full_messages.to_sentence.presence || 'the page would not save'}."
  end
end
