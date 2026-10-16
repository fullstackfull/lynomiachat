# Final visual comparison: the marketing site, old against new

Written against the committed before/after screenshots and against the running site, measured rather
than eyeballed. Where a measurement contradicted what a screenshot looked like, the measurement won —
twice, and both times it changed the answer.

The artifacts: `docs/redesign/evidence/{before,after}/marketing/{en,ar}/{desktop,mobile}/home.png`,
all shot by `tools/visual/capture.mjs` at `deviceScaleFactor: 1`, so their pixel heights are CSS
pixels and the two sets are directly comparable.

---

## 1. The correction this comparison had to make first

The baseline document and the pull request both carried this claim:

> Arabic mobile went from 11,828px of identical cards to 6,556px.

**It does not hold.** `before/marketing/ar/mobile/home.png` is 390×**5,918**, not 11,828 — and
`00-visual-baseline.md` line 47 cites the Arabic *desktop* page at 3,067px, which matches its own
file exactly. So the tool reports CSS pixels, one figure was read correctly and the other was not.

Measured live at the same settings, the redesigned Arabic mobile home is **6,503px**. Every page is
taller than the one it replaces:

| | before | after | |
|---|---|---|---|
| Arabic mobile | 5,918px | 6,503px | **+10%** |
| English mobile | 6,769px | 7,323px | +8% |
| Arabic desktop | 3,067px | 3,872px | +26% |
| English desktop | 3,406px | 4,155px | +22% |

The complaint in the baseline was never really about length — it was that the page was
undifferentiated and had nothing to orient against. The redesign answers that by *adding* a hero, a
product illustration and section-by-section differentiation, and it spends height doing so. That is
a defensible trade, but it is the opposite of what the claim said, so the claim is corrected in
`00-visual-baseline.md` and in the pull request body rather than restated.

---

## 2. What is genuinely better

**The hero exists now.** The old page rendered the `h1` from the page wrapper and the `hero` section
rendered only a kicker and two buttons — so the eyebrow printed *below* the standfirst, and the right
half of a 1440px viewport was empty down to the fold. The new hero carries the heading, the lede, the
actions and a shared-inbox illustration drawn in HTML, in the page's own language.

**The type finally has a display size.** The old `h1` was `text-3xl/4xl` — smaller than a heading
inside the dashboard. Nothing on a landing page should be set smaller than the product's own chrome.

**The stats stopped floating.** Three numbers sat loose under the buttons with nothing separating
them from the section below. They are a rule-separated specification row now, which is also what puts
them at the fold rather than past it.

**Arabic is set in an Arabic typeface.** `fontFamily.sans` was the system stack ending in
`Tahoma, Arial`, applied to the primary market's own language. IBM Plex Sans Arabic is self-hosted
now, and — the part worth checking rather than assuming — the asset actually resolves: an earlier
revision of this branch had a URL that 404'd, and the page still *looked* different because the size
and leading had changed with it.

**One identity across three surfaces.** The site was blue-on-white, the dashboard sidebar navy with a
pink nobody else used, the phone app indigo. The primary action is `lyn-indigo` everywhere now — the
colour the Flutter app already had.

**The Arabic page mirrors completely**, illustration included: brand right, nav right-to-left, hero
art on the left, stats reversed, and the order number inside the mock localized to ٤٨٢١.

---

## 3. Two things I checked because they looked wrong, and were not

Recorded because a reviewer will look at the same frames and see the same two things.

**The message text in the hero illustration looks skewed relative to its row dividers.** It is not a
rendering fault: the card carries `rotate-[-1.5deg]` and its backing plate `rotate-[2deg]`
(`sections/_hero.html.erb:92-93`). The dividers are rotated by the same amount; they read as level
because they are thin and low-contrast. Magnifying the crop exaggerates the text's anti-aliasing.

**The em-dash in the Arabic heading looks like it has drifted to the end of the line.** It has not.
Measured in the browser, line 3 runs `القناة@849  كانت@977  مهما@1096  —@1216` — the dash is at
x=1216, the **rightmost** position, which in RTL is where the line *begins*. It correctly continues
from the highlighted phrase on the line above. An `inline-block` highlight next to a bidi-neutral
character is a real hazard; here it resolved correctly.

---

## 4. Against professional SaaS convention

The page now does the things a current B2B SaaS landing page does: an eyebrow, a display heading with
one accent, a lede under 75 characters a line, a primary and a secondary action, a product
illustration opposite the copy, a proof row at the fold, then differentiated sections rather than one
repeating card grid. The closing CTA is the single dark field on the page instead of a flat blue
rectangle.

**The one risky choice is the magenta highlight.** Accenting a single phrase in a headline is on
every list of visual clichés, including the design guidance this project works from, which names it
first among the tells of a generated page. It is kept because this product's palette assigns
`lyn-magenta` exactly one job — one bold note per page — and because the `-1.2deg` rotation makes it
read as a marker stroke rather than a flat box. It is still the first thing a sceptical reviewer will
point at, and the honest position is that it is a deliberate bet, not an oversight.

**What is still missing against the best references:** there is no photography and no motion. The
`image` section type exists and is used on none of the 96 pages, and `entrypoints/marketing.js` loads
no JavaScript, so nothing on the page responds to scroll. Both were out of scope here; neither is
hidden by this document.

---

## 5. Verdict

Noticeably more premium than the original: **yes**, and the before/after frames carry that on their
own without needing a number attached.

Not because of the palette — because the old page had no hero, no display type, no image, half a
viewport of white space and an eyebrow printed in the wrong place, and the new one has a product on
screen above the fold in both languages.

The page is taller than it was, the magenta highlight is a bet, and photography and motion are still
absent. Those are the three things to put in front of a reviewer alongside the frames.
