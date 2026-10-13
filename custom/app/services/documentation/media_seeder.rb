# Lynomia documentation media: seeds the images the corpus references from source control into the portal.
#
# Operator-run alongside Documentation::ContentSeeder and idempotent in the same way: the files are the source,
# are reviewed the way code is reviewed, and a re-run updates rather than duplicates. Contract and interface:
# docs/documentation-v2/R2-MEDIA-CONTRACT.md, R2-MEDIA-INTERFACE.md section 3.
#
# It does its own corpus walk rather than being handed keys by ContentSeeder, so Agent 5's integration is one
# line and the two agents' files are not coupled per article -- and so this is independently runnable.
class Documentation::MediaSeeder
  # A corpus defect, raised rather than counted. ContentSeeder does not rescue it and the rake task does not
  # either, so `rake` prints the message and exits 1, and no partial corpus is written because the media pass
  # runs first. CLAUDE.md: a misconfigured state that indicates a setup bug fails loudly.
  class Error < StandardError; end

  MEDIA_DIR = 'media'.freeze

  # The ONE case a parser cannot see. CommonMark requires `<...>` around a destination containing a space, so
  # `![alt](media:step 2.png)` is not an image node at all -- the Markdown source is published verbatim and no
  # renderer, resolver or AST walk is ever reached (interface section 0.3). The seed boundary reads the raw bytes,
  # so it is the only place this can be caught, and a regex is the right tool for exactly this one case.
  SPACED_IMAGE_REFERENCE = /!\[[^\]]*\]\(\s*media:[^)<>]*\s[^)]*\)/

  Result = Struct.new(:uploaded, :replaced, :unchanged, :purged, :unmeasured, :unreferenced, keyword_init: true)

  # Deliberately the same keyword shape as ContentSeeder#initialize(portal:, author:, publish:, root:), so the
  # one line Agent 5 writes reads like the code around it.
  def initialize(portal:, root: Documentation::ContentSeeder::DOCS_ROOT)
    @portal = portal
    @root = root
    @result = Result.new(uploaded: 0, replaced: 0, unchanged: 0, purged: 0, unmeasured: 0, unreferenced: 0)
  end

  def perform!
    references = scan_corpus
    references.each { |key, reference| seed(key, reference) }
    purge_orphans(references.keys)
    @result.unreferenced = unreferenced_files(references.keys).count
    @result
  end

  private

  attr_reader :portal, :root

  def media_dir
    @media_dir ||= root.join(MEDIA_DIR)
  end

  def upload
    @upload ||= Documentation::MediaUpload.new(portal: portal)
  end

  # One entry per distinct key, carrying the first file and line that referenced it, so an error names a place an
  # operator can open. The same screenshot referenced from the EN and the AR translation of a page is one entry
  # and one blob, which is why the media tree is a SIBLING of the locale trees rather than inside them.
  #
  # Parsed with CommonMarker rather than scanned with a regex, because the parser is what the renderer itself
  # uses: it reports the alt and the destination exactly as `CustomMarkdownRenderer#image` will see them, escapes
  # included, so the seed boundary and the render path cannot disagree about what an image reference is.
  def scan_corpus
    references = {}
    Dir.glob(root.join('*', '*', '*.md')).each do |path|
      body = File.read(path)
      reject_spaced_reference(path, body)
      collect_references(references, path, body)
    end
    references
  end

  def reject_spaced_reference(path, body)
    body.each_line.with_index do |line, index|
      next unless line.match?(SPACED_IMAGE_REFERENCE)

      raise Error, "#{where(path, index + 1)}: a media reference contains a space, so CommonMark does not read " \
                   'it as an image at all and the Markdown source itself would be published. Rename the file.'
    end
  end

  def collect_references(references, path, body)
    CommonMarker.render_doc(body, :DEFAULT, [:table]).walk do |node|
      next unless media_reference?(node)

      key = node.url.to_s.delete_prefix(Documentation::MediaResolver::SCHEME)
      line = node.sourcepos[:start_line]
      # A `media:` key in a LINK position is a dead href in every browser, because the shared module emits the
      # destination verbatim. Only the image node is resolved, so this too has to be caught here.
      if node.type == :link
        raise Error, "#{where(path, line)}: media:#{key} is used as a link destination. Only an image reference " \
                     'is resolved; a link would render as a dead href.'
      end

      validate!(key, alt_of(node), path, line)
      references[key] ||= { path: path, line: line }
    end
  end

  def media_reference?(node)
    %i[image link].include?(node.type) && node.url.to_s.start_with?(Documentation::MediaResolver::SCHEME)
  end

  # The alt is the image node's own text children, which is exactly what the renderer emits into `alt=""`.
  def alt_of(node)
    node.each_with_object(+'') do |child, alt|
      child.walk { |leaf| alt << leaf.string_content.to_s if leaf.type == :text }
    end
  end

  def validate!(key, alt, path, line_number)
    unless Documentation::MediaResolver.valid_key?(key)
      raise Error, "#{where(path, line_number)}: #{key.inspect} is not a valid media key. The form is " \
                   '`media:<section>/<name>.png`, lowercase, with no spaces, query string or fragment.'
    end
    if Documentation::MediaResolver.operator_key?(key)
      segment = Documentation::MediaResolver::OPERATOR_SEGMENT
      raise Error, "#{where(path, line_number)}: media:#{key} is in the reserved `#{segment}/` namespace, " \
                   'which belongs to operator uploads. A corpus file cannot live there.'
    end
    return if alt.to_s.strip.present?

    raise Error, "#{where(path, line_number)}: media:#{key} has empty alt text. Alt is required: it is the " \
                 'public search snippet as well as the accessible name.'
  end

  # Idempotent by checksum against THIS PORTAL'S OWN attachments, never a global
  # ActiveStorage::Blob.find_by(checksum:) -- `checksum` is unindexed (db/schema.rb:105), so a global lookup is a
  # sequential scan of every attachment the product has ever stored, and it would also let one portal silently
  # adopt another portal's blob because two files happen to share bytes.
  def seed(key, reference)
    file = media_dir.join(key)
    unless file.file?
      raise Error, "#{where(reference[:path], reference[:line])}: media:#{key} has no file at " \
                   "#{file.relative_path_from(Rails.root)}."
    end

    existing = index[key]
    candidate = checksum_of(file)
    return @result.unchanged += 1 if existing && existing.blob.checksum == candidate

    attach(key, file, existing)
  end

  def attach(key, file, existing)
    blob = file.open('rb') do |io|
      upload.attach!(key: key, io: io, filename: file.basename.to_s,
                     content_source_path: file.relative_path_from(Rails.root).to_s)
    end
    # Non-zero on a healthy corpus means libvips is missing on this host, which is the one thing an operator
    # cannot otherwise see: ActiveStorage swallows the LoadError with a single info log line.
    @result.unmeasured += 1 if blob.metadata['width'].blank?
    existing ? @result.replaced += 1 : @result.uploaded += 1
  rescue Documentation::MediaUpload::Error => e
    raise Error, "media:#{key} (#{file.relative_path_from(Rails.root)}): #{e.message}"
  end

  # The same computation ActiveStorage performs when it creates a blob, so a match really means identical bytes.
  # `unfurl` is the public entry point to it (activestorage-7.2.3.2/app/models/active_storage/blob.rb:270-275);
  # `compute_checksum_in_chunks` itself is private (`:353-365`) and is not reached for with `send`. Nothing is
  # saved and nothing is uploaded -- the blob is built and thrown away.
  def checksum_of(file)
    file.open('rb') do |io|
      ActiveStorage::Blob.new(filename: file.basename.to_s).tap { |blob| blob.unfurl(io) }.checksum
    end
  end

  # Contract item 9 as amended by owner correction F1.1: scoped to attachments the SEEDER created. An operator
  # upload has no corpus file by construction, so the unamended sweep would delete every one of them on the next
  # seed, silently, with the article still referencing it. Both conditions are checked -- the attachment carries a
  # content_source_path, and its key is unreferenced.
  #
  # Scope discipline from contract section 0.2: `portal.documentation_media` only. It never touches the other
  # platform portal's media, never Portal#logo (a different attachment name, so outside this set by
  # construction) and never anything on an Article.
  def purge_orphans(referenced_keys)
    index.each do |key, attachment|
      next if referenced_keys.include?(key)
      next if attachment.blob.metadata[Documentation::MediaResolver::SOURCE_PATH_METADATA].blank?

      attachment.purge_later
      @result.purged += 1
    end
  end

  # Not a failure: these files are committed to git and reviewed in diffs, so they are harmless. Reported so the
  # number does not drift silently.
  def unreferenced_files(referenced_keys)
    return [] unless media_dir.directory?

    Dir.glob(media_dir.join('**', '*')).reject { |path| File.directory?(path) }
       .reject { |path| referenced_keys.include?(Pathname.new(path).relative_path_from(media_dir).to_s) }
  end

  def index
    @index ||= portal.documentation_media.includes(:blob).index_by do |attachment|
      attachment.blob.metadata[Documentation::MediaResolver::KEY_METADATA]
    end
  end

  # Never a storage path (contract section 3.2): the corpus file, relative to the repository root.
  def where(path, line_number)
    "#{Pathname.new(path).relative_path_from(Rails.root)}:#{line_number}"
  end
end
