# Lynomia documentation media: resolves a `media:` key to the blob it names, for ONE portal, at render time.
#
# The contract is docs/documentation-v2/R2-MEDIA-CONTRACT.md and the code-level half is R2-MEDIA-INTERFACE.md.
# Two properties this class exists to hold:
#
# 1. The grammar lives here and nowhere else (interface section 1.5). The seeder, the upload service, the
#    renderer and the delivery route all ask `valid_key?` rather than carrying a copy. A `constraints:` clause in
#    config/routes.rb would be a second copy of the grammar in a file this agent does not own.
# 2. Resolution is per render, per call -- never by setting config.active_storage.resolve_model_to_route, which
#    is unset today so the framework default :rails_storage_redirect applies. Flipping it would move avatars,
#    portal logos, chat attachments, macro and automation files and exports to the proxy route all at once.
class Documentation::MediaResolver
  include Rails.application.routes.url_helpers

  SCHEME = 'media:'.freeze

  # The reserved first segment for operator uploads (owner correction F1, interface section 9.1). A corpus file
  # may not live under it and an operator upload may not live outside it, so the two namespaces are disjoint sets
  # and an operator key can never collide with -- or be mistaken for -- a seeded one.
  OPERATOR_SEGMENT = 'uploads'.freeze

  # Lowercase only, and case-sensitive. Not cosmetic: production storage is DiskService on a case-sensitive Linux
  # filesystem (config/storage.yml:5-7) while the corpus is reviewed on developer machines that may not be, so a
  # key differing only in case would seed on one machine and 404 on the other. Lowercase-only also rejects base64
  # by construction, which is the second-order reason an ActiveStorage signed id can never be a key.
  SEGMENT = '[a-z0-9](?:[a-z0-9-]*[a-z0-9])?'.freeze
  KEY = %r{\A#{SEGMENT}(?:/#{SEGMENT}){1,4}\.(?:png|jpe?g|gif|webp)\z}
  MAX_KEY_LENGTH = 200

  # The key and the provenance both live in blob metadata rather than in `filename`, because
  # ActiveStorage::Filename#to_s is `sanitized` and replaces `/` and `:` with `-`
  # (activestorage-7.2.3.2/app/models/active_storage/filename.rb:59-66), so a slash-bearing name would read back
  # lossily. A field whose reader lies is not a key. `blob.analyze` merges rather than replaces
  # (blob/analyzable.rb:29-31), so analysis cannot clobber either value.
  KEY_METADATA = 'documentation_key'.freeze

  # One vocabulary with Agent 5's row provenance (P2-SOURCE-OF-TRUTH-CONTRACT.md D2): the corpus file that owns
  # this attachment, relative to Rails.root. ABSENT means no file owns it, which is exactly an operator upload.
  # Deliberately not an origin enum -- D2 rejected a stored flag for rows because it would be a second source of
  # truth for a derivable fact, and origin here derives the same way.
  SOURCE_PATH_METADATA = 'content_source_path'.freeze

  Image = Struct.new(:key, :blob, :path, :content_type, :byte_size, :width, :height, keyword_init: true)

  class << self
    def valid_key?(key)
      key = key.to_s
      key.length <= MAX_KEY_LENGTH && key.match?(KEY)
    end

    def operator_key?(key)
      key.to_s.start_with?("#{OPERATOR_SEGMENT}/")
    end
  end

  # portal is the LOOKUP scope -- keys are per-portal. article is only the URL scope: it is what lets the
  # delivery route apply the published-or-signed-in-super-admin predicate, and it is not needed to resolve a key.
  # If a future surface ever needs a key resolved without an article, that is a new method rather than a
  # nil-tolerant `article:`.
  def initialize(portal:, article:)
    @portal = portal
    @article = article
  end

  def resolve(key)
    key = key.to_s
    return unless self.class.valid_key?(key)

    attachment = index[key]
    return if attachment.nil?

    image_for(key, attachment.blob)
  end

  # This portal's attached keys, for the seeder's orphan pass.
  def keys
    index.keys.compact
  end

  private

  attr_reader :portal, :article

  # In memory, not in SQL, and that is the only indexed design rather than a compromise.
  # active_storage_blobs.metadata is a `text` column with a JSON coder (db/schema.rb:103, blob.rb:31), so there
  # is no `metadata->>'...'` operator to query with, and the only blob index is on `key` (db/schema.rb:108). The
  # one indexed path to this portal's media is the attachments uniqueness index on
  # (record_type, record_id, name, blob_id) (db/schema.rb:96).
  #
  # So the N+1 answer for an article with twenty images is that there is none: one index_by costs TWO queries --
  # attachments by that index, then blobs by id -- whether the article has one image or twenty, and twenty
  # resolve calls are twenty hash lookups. Memoized per instance, and the instance lives for one render. Nothing
  # is cached across requests: no Rails.cache, no class-level memo.
  def index
    @index ||= portal.documentation_media.includes(:blob).index_by { |attachment| attachment.blob.metadata[KEY_METADATA] }
  end

  # The path is ROOT-RELATIVE, never host-qualified. The article page is reachable on a tenant custom domain
  # (app/controllers/public_controller.rb:9-20, applied to `show` at articles_controller.rb:2), so a host-
  # qualified URL would leave the origin -- and with no img-src in the enforcing CSP, same-origin is the only
  # protection there is. Measured: Journey formats a glob segment with escape_path, whose unsafe set excludes `/`
  # and `.` (actionpack-7.2.3.2/lib/action_dispatch/journey/router/utils.rb:43,50,56-58), so the key's slashes
  # and dot survive helper generation unescaped.
  def image_for(key, blob)
    Image.new(key: key, blob: blob,
              path: public_portal_article_media_path(portal.slug, article.slug, key),
              content_type: blob.content_type, byte_size: blob.byte_size,
              width: blob.metadata['width'], height: blob.metadata['height'])
  end
end
