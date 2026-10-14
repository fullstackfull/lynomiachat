# Lynomia documentation media: seeds the images the corpus references from source control into the portal.
#
# Operator-run alongside Documentation::ContentSeeder and idempotent in the same way: the files are the source,
# are reviewed the way code is reviewed, and a re-run updates rather than duplicates. Contract and interface:
# docs/documentation-v2/R2-MEDIA-CONTRACT.md, R2-MEDIA-INTERFACE.md section 3.
#
# It does its own corpus walk rather than being handed keys by ContentSeeder, so Agent 5's integration is one
# line and the two agents' files are not coupled per article -- and so this is independently runnable.
class Documentation::MediaSeeder
  # A corpus defect, raised rather than counted. CLAUDE.md: a misconfigured state that indicates a setup bug
  # fails loudly.
  #
  # Where it surfaces changed when the A5'-O1 wiring landed, and R2-MEDIA-INTERFACE.md section 3.6 still
  # describes the old path ("ContentSeeder#perform! does not rescue ... rake prints the message and backtrace").
  # It does now: `ContentSeeder#preflight!` converts an Error raised by the PREFLIGHT half into its own
  # PreflightError, in that method's own `rescue`, so the operator reads the one refusal message every
  # other preflight refusal prints -- that nothing was written -- instead of a Ruby backtrace. An Error raised
  # by the APPLY half becomes an ApplyFailure naming `the corpus media pass`, with the counts that completed.
  # Either way: a clear message, a non-zero exit, and a run that is safe to repeat.
  class Error < StandardError; end

  MEDIA_DIR = 'media'.freeze

  # The ONE case a parser cannot see. CommonMark requires `<...>` around a destination containing a space, so
  # `![alt](media:step 2.png)` is not an image node at all -- the Markdown source is published verbatim and no
  # renderer, resolver or AST walk is ever reached (interface section 0.3). The seed boundary reads the raw bytes,
  # so it is the only place this can be caught, and a regex is the right tool for exactly this one case.
  SPACED_IMAGE_REFERENCE = /!\[[^\]]*\]\(\s*media:[^)<>]*\s[^)]*\)/

  Result = Struct.new(:uploaded, :replaced, :unchanged, :purged, :unmeasured, :unreferenced, keyword_init: true)

  # THE LIVE COUNTER, readable before `perform!` returns. `ContentSeeder` holds this exact object, so an
  # ApplyFailure carries what the media pass completed before it failed: `Result` is a mutable Struct and this
  # service counts into it as it goes. That is owner ruling 3's "report exactly what completed and what failed"
  # one level down, and it is why the reader exists rather than only the return value.
  attr_reader :result

  # Deliberately the same keyword shape as ContentSeeder#initialize(portal:, author:, publish:, root:), so the
  # one line Agent 5 writes reads like the code around it.
  #
  # `locales` is the set of locale trees to walk, and `nil` means ALL of them -- which is what a standalone run
  # wants and what every caller before the A5'-O1 wiring got. `ContentSeeder` passes the locales it is actually
  # seeding, and that is a correctness requirement rather than an optimisation: a corpus legitimately carries a
  # locale tree the portal does not serve (content_seeder.rb `parity_problems` says so in terms, because
  # narrowing `allowed_locales` has to keep working), and MEASURED on the first cut of the wiring, a `media:`
  # reference in such a tree refused the whole seed -- `PreflightError` at `ar/getting-started/welcome.md:9`,
  # zero articles written, for an image only an unseeded locale needed.
  def initialize(portal:, root: Documentation::ContentSeeder::DOCS_ROOT, locales: nil)
    @portal = portal
    @root = root
    @locales = locales
    # `purged` and `unreferenced` start NIL, not zero: the orphan sweep is the last thing the apply does, so on
    # any earlier failure a zero there would claim the sweep ran and found nothing. The report prints them only
    # once they are set (lib/tasks/documentation.rake).
    @result = Result.new(uploaded: 0, replaced: 0, unchanged: 0, purged: nil, unmeasured: 0, unreferenced: nil)
  end

  # `perform!` is unchanged for every caller: both phases, in order. What the A5'-O1 wiring needed was the
  # PREFLIGHT separately, so `ContentSeeder` can run it inside its own preflight where nothing has been written
  # yet, and then call `perform!` first inside its apply (R2-MEDIA-INTERFACE.md section 3.2 plus owner ruling 3).
  # `apply!` is deliberately NOT public: nothing outside calls it, and a public entry taking a caller-supplied
  # reference hash would reach the attach boundary without `validate!`'s namespace guard -- the only place the
  # `uploads/` invariant is enforced.
  def perform!
    apply!(preflight!)
  end

  # PHASE 1 -- every corpus defect, with no write of any kind: the grammar checks `scan_corpus` already makes,
  # plus the file each referenced key names. Owner ruling 3 applied to this seeder for the same reason it applies
  # to the content one -- an upload is outside any database transaction, so the only honest atomicity is to decide
  # everything decidable before the first write. The missing-file check used to live inside the write loop, so a
  # corpus whose tenth key had no file uploaded nine blobs and then raised.
  #
  # MEMOIZED, because `ContentSeeder` calls this from its own preflight and then `perform!` calls it again from
  # the apply. One scan of the corpus per run either way. `Hash#each` returns the hash, so the memo is the
  # reference index and not the block's value.
  def preflight!
    @preflight ||= scan_corpus.each { |key, reference| require_file!(key, reference) }
  end

  # PHASE 2 -- the writes, all of them idempotent: a key whose checksum already matches is counted and skipped, a
  # key whose bytes changed is replaced through the one attach boundary, and the orphan sweep only ever considers
  # attachments a seed created.
  def apply!(references)
    references.each_key { |key| seed(key) }
    @result.purged = 0
    purge_orphans(references.keys)
    @result.unreferenced = unreferenced_files(references.keys).count
    @result
  end

  private

  attr_reader :portal, :root

  # One entry per tree to walk. `['*']` is the glob that matches every locale directory, so a standalone run
  # behaves exactly as it did before `locales:` existed; an explicit empty list walks nothing, which is the right
  # answer for a portal that allows no locale this product ships.
  def locale_trees
    @locales || ['*']
  end

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
    locale_trees.each do |locale|
      Dir.glob(root.join(locale, '*', '*.md')).each do |path|
        body = body_of(path)
        document = CommonMarker.render_doc(body, :DEFAULT, [:table])
        reject_spaced_reference(path, body, code_block_lines(document))
        collect_references(references, path, document)
      end
    end
    references
  end

  # THE BODY, not the raw file. `ContentSeeder::Corpus` parses only what follows the front matter, so a `media:`
  # image written inside a front-matter VALUE is an image node to this scanner and invisible to that one --
  # seeded by one and unknown to the other, and able to refuse the whole run over a key no page renders. The
  # front matter is replaced by as many blank lines as it occupied rather than removed, so every line number in
  # an error message still points at the line an operator opens.
  def body_of(path)
    source = File.read(path)
    front = source[Documentation::ContentSeeder::Corpus::FRONT_MATTER]
    body = front.nil? ? source : ("\n" * front.count("\n")) + source.delete_prefix(front)
    # `Corpus#split` ends in `.strip`, and that is not cosmetic: it decides the BLOCK TYPE of the first content
    # line. A body whose first line is indented four spaces is a paragraph to the stripped text the article will
    # publish, and an indented CODE BLOCK to text that keeps the indentation -- so one scanner would see an image
    # reference where the other saw prose, which is the A5'-O1 shape over again. The leading indentation goes and
    # the newlines before it stay, so the two scanners agree on structure and the line numbers still point at the
    # line an operator opens.
    body.sub(/\A(\n*)[ \t]+/) { Regexp.last_match(1) }
  end

  # The lines a fenced or indented code block occupies, which is where prose about this grammar lives: the
  # corpus documents this product, so `![alt](media:step 2.png)` is exactly the example a troubleshooting
  # article shows as the thing NOT to write. `Corpus#media_problems` is PARSED precisely so a key in a fence is
  # not a reference, and the spaced-reference scan below has to be a raw regex because CommonMark builds no
  # image node for a spaced destination -- so the parse is what tells the regex where the prose ends.
  #
  # Code blocks only. An example inside INLINE backticks on a prose line still refuses, because an inline span's
  # sourcepos does not separate it from the prose around it on that line; a fence is the documented way to show
  # the example, and the refusal names the file and line either way.
  def code_block_lines(document)
    document.walk.filter_map do |node|
      next unless node.type == :code_block

      (node.sourcepos[:start_line]..node.sourcepos[:end_line]).to_a
    end.flatten
  end

  def reject_spaced_reference(path, body, fenced_lines)
    body.each_line.with_index do |line, index|
      next if fenced_lines.include?(index + 1)
      next unless line.match?(SPACED_IMAGE_REFERENCE)

      raise Error, "#{where(path, index + 1)}: a media reference contains a space, so CommonMark does not read " \
                   'it as an image at all and the Markdown source itself would be published. Rename the file.'
    end
  end

  def collect_references(references, path, document)
    document.walk do |node|
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

  # EVERYTHING DECIDABLE ABOUT THE FILE, with no write: that it exists, that its BYTES are a permitted raster
  # type, and that there are not too many of them. The last two used to be decided inside the write loop by
  # `MediaUpload#attach!`, which is the same defect shape as the missing-file check that used to live there --
  # measured consequence, a corpus whose second image was over the 2 MB cap attached the first and then raised.
  # `MediaUpload#validate_bytes!` is the one implementation of both, which the attach boundary also calls, so
  # this cannot drift from what the write will accept.
  #
  # The rescue is what gives the message its location: `MediaUpload` knows the key and the bytes, and only the
  # reference index here knows which corpus FILE and LINE referred to them, which is the thing an operator has
  # to open (contract section 3.2: never a storage path).
  def require_file!(key, reference)
    file = media_dir.join(key)
    unless file.file?
      raise Error, "#{where(reference[:path], reference[:line])}: media:#{key} has no file at " \
                   "#{file.relative_path_from(Rails.root)}."
    end

    file.open('rb') { |io| upload.validate_bytes!(key: "media:#{key}", io: io) }
  rescue Documentation::MediaUpload::Error => e
    raise Error, "#{where(reference[:path], reference[:line])}: #{e.message} " \
                 "(#{file.relative_path_from(Rails.root)})"
  end

  # Idempotent by checksum against THIS PORTAL'S OWN attachments, never a global
  # ActiveStorage::Blob.find_by(checksum:) -- `checksum` is unindexed (db/schema.rb:105), so a global lookup is a
  # sequential scan of every attachment the product has ever stored, and it would also let one portal silently
  # adopt another portal's blob because two files happen to share bytes.
  def seed(key)
    file = media_dir.join(key)
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
