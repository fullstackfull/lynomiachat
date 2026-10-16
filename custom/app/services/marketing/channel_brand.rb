# The channel marks the website draws, in one place.
#
# WHY THIS EXISTS. Every channel was a grey Lucide glyph -- `i-lucide-camera` for Instagram, `i-lucide-send`
# for Telegram -- chosen when the site's rule was "name the channel in text, never draw its logo". That rule
# kept the page to one colour and needed no trademark, and it also meant the one thing a visitor scans a
# messaging product for, the logos of the apps their customers already use, was not on the page. The owner's
# instruction reverses it: show the real marks.
#
# WHAT A MARK IS HERE. Two kinds, and the difference is the point:
#
#   :third_party  an authentic brand mark -- WhatsApp's handset, Messenger's bolt, Telegram's plane -- drawn
#                 in that brand's own colour, used NOMINATIVELY to say "this product connects to that
#                 service". No endorsement is implied or claimed anywhere these are rendered.
#   :first_party  a channel Lynomia itself provides (the website widget, email, SMS, the API channel). There
#                 is no third-party brand to borrow, so these are drawn in the Lynomia ramp. Dressing them in
#                 a fake vendor logo would be the dishonest option.
#
# WHY INLINE SVG AND NOT THE SHIPPED PNGs. public/integrations/channels/badges/*.png exist and are the
# fidelity reference these paths were checked against, but they are raster: `instagram.png` under
# public/assets/images/dashboard/channels is 1.3 MB, and a marquee that draws ten marks at three sizes on a
# retina phone would ship a payload for a decoration. Inline SVG is a few hundred bytes per mark, crisp at
# any size, needs no second request (so it cannot shift the layout as it lands), and carries its own
# accessible name.
#
# WHY A RUBY CONSTANT RATHER THAN A DATABASE ROW. Same reason Marketing::Catalog is one: a logo is a product
# fact, not operator copy. An operator should not be able to edit WhatsApp's mark onto the LINE entry.
#
# THE IDS ARE Marketing::Catalog::CHANNELS IDS. `mark_for` falls back to the first-party generic rather than
# raising, so a catalogue entry added without a mark renders a neutral glyph instead of a blank hole -- and
# `missing` lists exactly which ids are in that state, which the spec asserts is empty.
module Marketing::ChannelBrand
  Mark = Struct.new(:id, :kind, :tile, :ink, :body, keyword_init: true) do
    def third_party? = kind == :third_party
  end

  # Each `body` is the glyph drawn INSIDE a 24x24 box, already coloured. `tile` is the plate it sits on and
  # `ink` the colour of the glyph on that plate, so one partial can render every mark at any size.
  MARKS = {
    whatsapp: Mark.new(
      id: :whatsapp, kind: :third_party, tile: '#25D366', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="currentColor" d="M12.04 3.5c-4.7 0-8.52 3.81-8.52 8.5 0 1.5.39 2.96 1.14 4.25L3.5 20.5l4.38-1.14a8.5 8.5 0 0 0 4.16 1.08h.01c4.69 0 8.5-3.81 8.5-8.5 0-2.27-.88-4.4-2.49-6a8.44 8.44 0 0 0-6.02-2.44Zm0 1.57c1.84 0 3.57.72 4.87 2.02a6.86 6.86 0 0 1 2.02 4.88c0 3.8-3.09 6.89-6.9 6.89a7.1 7.1 0 0 1-3.6-.99l-.26-.15-2.6.68.69-2.53-.17-.27a6.84 6.84 0 0 1-1.06-3.66c0-3.8 3.1-6.87 6.9-6.87Z"/>
        <path fill="currentColor" d="M9.43 8.1c-.16-.36-.33-.37-.48-.37h-.41c-.14 0-.37.05-.57.26-.19.21-.74.72-.74 1.76s.76 2.04.87 2.18c.1.14 1.47 2.35 3.63 3.2 1.79.71 2.16.57 2.55.53.39-.03 1.25-.51 1.43-1 .18-.5.18-.92.12-1.01-.05-.09-.19-.14-.4-.25-.21-.1-1.25-.62-1.44-.69-.2-.07-.34-.1-.48.1-.14.22-.55.7-.67.84-.13.14-.25.16-.46.05-.21-.1-.89-.32-1.69-1.04-.63-.55-1.05-1.24-1.17-1.45-.13-.2-.02-.32.09-.42.1-.1.21-.25.31-.38.11-.13.14-.22.21-.36.07-.14.04-.27-.02-.37-.05-.11-.46-1.13-.64-1.54Z"/>
      SVG
    ),

    instagram: Mark.new(
      # Instagram's mark is a gradient, not a flat colour. The tile carries the gradient (see the partial's
      # `tile_style`) and the glyph is the white outline camera.
      id: :instagram, kind: :third_party, tile: 'instagram-gradient', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="none" stroke="currentColor" stroke-width="1.7" d="M8.2 4.6h7.6a3.6 3.6 0 0 1 3.6 3.6v7.6a3.6 3.6 0 0 1-3.6 3.6H8.2a3.6 3.6 0 0 1-3.6-3.6V8.2a3.6 3.6 0 0 1 3.6-3.6Z"/>
        <circle fill="none" stroke="currentColor" stroke-width="1.7" cx="12" cy="12" r="3.3"/>
        <circle fill="currentColor" cx="16.4" cy="7.6" r="1.1"/>
      SVG
    ),

    facebook_messenger: Mark.new(
      id: :facebook_messenger, kind: :third_party, tile: 'messenger-gradient', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="currentColor" d="M12 3.6c-4.7 0-8.3 3.44-8.3 8.08 0 2.43 1 4.52 2.63 5.97.14.12.22.29.23.47l.05 1.49c.01.47.5.78.93.59l1.66-.73a.74.74 0 0 1 .5-.04c.76.21 1.57.32 2.3.32 4.7 0 8.3-3.44 8.3-8.07S16.7 3.6 12 3.6Zm4.98 6.2-2.44 3.87a1.25 1.25 0 0 1-1.8.33l-1.94-1.46a.5.5 0 0 0-.6 0l-2.62 1.99c-.35.27-.8-.15-.57-.52l2.44-3.87a1.25 1.25 0 0 1 1.8-.33l1.94 1.46a.5.5 0 0 0 .6 0l2.62-1.99c.35-.27.8.15.57.52Z"/>
      SVG
    ),

    telegram: Mark.new(
      id: :telegram, kind: :third_party, tile: 'telegram-gradient', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="currentColor" d="M18.6 6.3 16.1 18.1c-.19.83-.68 1.04-1.38.65l-3.82-2.82-1.84 1.78c-.2.2-.38.38-.78.38l.28-3.94 7.17-6.48c.31-.28-.07-.43-.48-.16l-8.86 5.58-3.81-1.19c-.83-.26-.85-.83.17-1.23l14.9-5.74c.69-.25 1.3.16 1.05 1.37Z"/>
      SVG
    ),

    line: Mark.new(
      # LINE's mark is the wordmark in a rounded square, not a pictogram. Set rather than drawn, because the
      # letterforms ARE the mark.
      id: :line, kind: :third_party, tile: '#06C755', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="currentColor" d="M20 10.75C20 7.16 16.41 4.24 12 4.24S4 7.16 4 10.75c0 3.22 2.85 5.91 6.69 6.42.26.06.62.17.71.4.08.2.05.52.03.73l-.12.69c-.03.2-.16.8.7.43.86-.36 4.62-2.72 6.3-4.66C19.47 13.49 20 12.19 20 10.75Z"/>
        <path fill="#06C755" d="M9.3 9.03h-.56a.16.16 0 0 0-.16.15v3.48c0 .09.07.16.16.16h.56c.08 0 .15-.07.15-.16V9.18a.16.16 0 0 0-.15-.15Zm3.86 0h-.56a.16.16 0 0 0-.16.15v2.07l-1.6-2.15-.01-.02h-.64a.16.16 0 0 0-.15.15v3.48c0 .09.07.16.15.16h.56c.09 0 .16-.07.16-.16v-2.07l1.6 2.16.04.04h.61c.09 0 .16-.07.16-.16V9.18a.16.16 0 0 0-.16-.15Zm-5.2 2.77H6.44V9.18a.16.16 0 0 0-.15-.15h-.56a.16.16 0 0 0-.16.15v3.48c0 .05.02.08.04.11.03.03.07.05.11.05h2.24c.09 0 .15-.07.15-.16v-.55a.16.16 0 0 0-.15-.16Zm8.3-2.77h-2.24a.16.16 0 0 0-.15.15v3.48c0 .09.07.16.15.16h2.24c.09 0 .16-.07.16-.16v-.55a.16.16 0 0 0-.16-.16h-1.52v-.59h1.52c.09 0 .16-.07.16-.16v-.55a.16.16 0 0 0-.16-.16h-1.52v-.59h1.52c.09 0 .16-.07.16-.15v-.56a.16.16 0 0 0-.16-.15Z"/>
      SVG
    ),

    tiktok: Mark.new(
      id: :tiktok, kind: :third_party, tile: '#000000', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="#25F4EE" d="M10.4 10.1v-.86a6.6 6.6 0 0 0-.9-.07 4.5 4.5 0 0 0-2.6 8.16 4.49 4.49 0 0 1 3.5-7.23Z"/>
        <path fill="currentColor" d="M14.2 4.2h1.74a3.3 3.3 0 0 0 2.9 2.92v1.8a5.06 5.06 0 0 1-2.9-.93v5.5a4.52 4.52 0 1 1-4.52-4.52c.2 0 .4.02.6.05v1.84a2.7 2.7 0 1 0 2.18 2.64V4.2Z"/>
        <path fill="#FE2C55" d="M15.94 7.12a3.3 3.3 0 0 0 2.9 2.92V8.2a3.3 3.3 0 0 1-2.9-1.08Z"/>
      SVG
    ),

    # ---- First-party channels. Lynomia's own ramp, no borrowed brand. ----

    live_chat: Mark.new(
      id: :live_chat, kind: :first_party, tile: '#5B5BF0', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="currentColor" d="M5.4 4.6h13.2c.72 0 1.3.58 1.3 1.3v8.5c0 .72-.58 1.3-1.3 1.3h-6.1l-3.64 2.96a.7.7 0 0 1-1.14-.54v-2.42H5.4c-.72 0-1.3-.58-1.3-1.3V5.9c0-.72.58-1.3 1.3-1.3Z"/>
        <circle fill="#5B5BF0" cx="8.6" cy="10.1" r="1.15"/>
        <circle fill="#5B5BF0" cx="12" cy="10.1" r="1.15"/>
        <circle fill="#5B5BF0" cx="15.4" cy="10.1" r="1.15"/>
      SVG
    ),

    email: Mark.new(
      id: :email, kind: :first_party, tile: '#1D3FA8', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="currentColor" d="M4.8 5.8h14.4c.77 0 1.4.63 1.4 1.4v9.6c0 .77-.63 1.4-1.4 1.4H4.8c-.77 0-1.4-.63-1.4-1.4V7.2c0-.77.63-1.4 1.4-1.4Z"/>
        <path fill="none" stroke="#1D3FA8" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="m4.6 8 6.6 4.6c.48.33 1.12.33 1.6 0L19.4 8"/>
      SVG
    ),

    sms: Mark.new(
      id: :sms, kind: :first_party, tile: '#0090FF', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="currentColor" d="M8.6 3.6h6.8c1.1 0 2 .9 2 2v12.8c0 1.1-.9 2-2 2H8.6c-1.1 0-2-.9-2-2V5.6c0-1.1.9-2 2-2Z"/>
        <path fill="#0090FF" d="M8.3 6.6h7.4v8.2H8.3z"/>
        <circle fill="#0090FF" cx="12" cy="17.6" r="1"/>
        <path fill="currentColor" d="M9.6 8.2h4.8v1.2H9.6zm0 2.4h4.8v1.2H9.6zm0 2.4h3v1.2h-3z"/>
      SVG
    ),

    api_channel: Mark.new(
      id: :api_channel, kind: :first_party, tile: '#0A1733', ink: '#FFFFFF',
      body: <<~SVG
        <path fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" d="m9 8-4 4 4 4m6-8 4 4-4 4"/>
      SVG
    )
  }.freeze

  # Gradients the tiles use, declared once and emitted into a single hidden <svg> on the page so every mark
  # can reference them by id. Two marks, two gradients: a `fill` cannot be a CSS gradient on an SVG shape.
  GRADIENTS = {
    'instagram-gradient' => [['0%', '#F9CE34'], ['45%', '#EE2A7B'], ['100%', '#6228D7']],
    'messenger-gradient' => [['0%', '#00B2FF'], ['100%', '#006AFF']],
    'telegram-gradient' => [['0%', '#37BBFE'], ['100%', '#007DBB']]
  }.freeze

  GENERIC = Mark.new(
    id: :generic, kind: :first_party, tile: '#2A3A5C', ink: '#FFFFFF',
    body: '<path fill="currentColor" d="M12 3.8a8.2 8.2 0 1 0 0 16.4 8.2 8.2 0 0 0 0-16.4Zm0 3.1a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6Zm1.4 9.7h-2.8v-5.4h2.8Z"/>'
  )

  class << self
    def mark_for(id) = MARKS.fetch(id.to_sym, GENERIC)

    def marked?(id) = MARKS.key?(id.to_sym)

    # The catalogue ids with no mark of their own. The spec asserts this is empty, so a channel added to
    # Marketing::Catalog without a mark fails a test rather than shipping a grey circle to the home page.
    def missing
      Marketing::Catalog::CHANNELS.map(&:id).reject { |id| marked?(id) }
    end

    # The order the home page's strip draws, which is NOT the catalogue's order: the strip leads with the
    # marks a visitor recognises fastest, and the first-party ones (which are Lynomia's own and need no
    # recognition) are spaced between them rather than clumped at the end.
    STRIP_ORDER = %i[whatsapp instagram facebook_messenger live_chat telegram email line sms tiktok
                     api_channel].freeze

    def strip_marks
      STRIP_ORDER.filter_map { |id| MARKS[id] }
    end
  end
end
