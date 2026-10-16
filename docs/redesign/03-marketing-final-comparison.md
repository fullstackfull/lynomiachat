# The marketing site, before and after

A last look at the home page against the one it replaces, and against what the category expects of a
page like this.

**The two shots:** `evidence/before/marketing/en/desktop/home.png` and
`evidence/marketing/en/desktop/home-bands.png`. Both are real screenshots of real pages from the real
server at 1440px, taken by `tools/visual/capture.mjs`, which does not stitch or edit.

## What changed, measured off the two images

| | before | after |
|---|---|---|
| Page height at 1440px | 3,406px | 4,724px |
| Surfaces used down the page | one (white), until a blue CTA at 2,900px | ink → paper → mist → paper → gradient → mist |
| Brand colour above the fold | none | the hero band, the panel's send button, the underline |
| A picture of the product | none anywhere | in the hero, upright and lit against the ink |
| Channels | nine equal cards in a 3-up grid | a two-column index, each channel with its own glyph |
| The closing call | a blue rounded box inside the column | a full-bleed royal→indigo band |

The page is taller because the sections now have room and a field of their own, not because anything
was added: the section list is the same, in the same order, with the same copy.

## The three things that were actually wrong before

1. **It was one column of hairline-separated blocks.** Nine sections at one scale on one surface. A
   visitor scrolling had no way to tell they had moved from one subject to another, because nothing
   changed except the words. Sections are now full-bleed bands and the boundary is a change of
   surface.
2. **The product was invisible.** A page selling a shared inbox showed no inbox. The hero now carries
   a panel of the real thing — three conversations arriving from three channels, the composer, the
   assignment chip — against a dark field that makes it read as an object rather than as more page.
3. **The brand appeared once, 2,900px down.** On a page about a company whose colour is indigo, the
   first indigo a visitor met was a button near the bottom. It is now the hero's field.

## Against the category

What a serious product page in this category does, and whether this one does it:

| | |
|---|---|
| Opens on the product, not on a slogan alone | ✅ the hero panel |
| States what it connects to, scannably | ✅ the two-column channel index with glyphs |
| Says what the buyer must supply | ✅ every channel row carries its "You supply:" line |
| Marks what is not turned on by default | ✅ `setup needed` and `beta` chips, unchanged from before |
| Social proof — logos, numbers, quotes | ❌ **absent, deliberately** |
| One clear action, repeated | ✅ "Create your account" in the header, the hero and the closing band |
| Works at phone width and in Arabic | ✅ shot at 390px and in `ar` |

**On the missing social proof.** Every reference page in this category carries customer logos, a
headline number, or a quote. This page carries none, and that is a decision rather than an oversight:
there is no verified list of customers to name here, and inventing one — a logo wall, "trusted by
2,000 teams", a testimonial — would be a lie printed on the front door. The three figures the page
does show (9 channels, 50+ languages, API) are counts of things in this codebase, checkable by
reading it.

If the business has customers who would agree to be named, that is the single biggest improvement
left for this page, and it needs their permission, not a design change.

## What is not borrowed

No layout, asset, copy or colour here is taken from another company's site. The bands, the ink field,
the glyph index and the gradient close are ordinary compositional moves; the palette is Lynomia's own
(`tailwind.marketing.config.js`), and the copy is written from this codebase's own feature set.

## Verdict

The after is the more premium page by every measure above except social proof, and the gap on that
one is a fact about the business, not about the design. The page is ready for review.
