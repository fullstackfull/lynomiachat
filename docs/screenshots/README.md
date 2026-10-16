# The Lynomia screenshot library

Every product image on the marketing site and in the documentation comes from here, and every one of
them is a **real screenshot of the running application**. Nothing in this directory is a mockup, a
theme preview or a drawing of what a screen might look like.

## The three stages

```
sources/<key>.png      a genuine capture of the whole screen   <- the source of truth
specs/<key>.json       what the annotations say, where, and which part of the frame to show
<consumer>/<key>.png   the annotated output                    <- generated, never edited by hand
```

A source is never edited. When a screen is redesigned you re-capture the source, run the build, and
every annotated output that uses it is regenerated with its markers still in place. That is the whole
reason the annotations live in a spec rather than being painted into the PNG once.

**A crop is in the spec, not in the file.** `crop: {x, y, w, h}`, in source pixels, says which part of
the capture the published figure shows; the markers and rings are then percentages of that cropped
frame. The source stays the whole screen that was photographed, because that is what was photographed
— and a 1440-wide screenshot published whole is 358px on a phone, which is where documentation is
read and where its annotations stop being legible.

## Measured geometry, and the one thing that is covered

Two numbers in a spec used to be eyeballed off the PNG: where a ring goes, and where a marker's dot
sits. They are now read off the live page instead. A page in `tools/visual/capture.mjs` may declare

```js
measure: { 'status-filter': 'button:has(.i-lucide-filter)' }
```

and the capture writes `<name>.boxes.json` beside the shot, holding each named control's bounding box
in the shot's own pixels. A spec then says `"box": "status-filter"` instead of a coordinate, and
`"crop": { "around": ["header", "kpis"], "pad": 16 }` instead of a rectangle. The payoff is not
tidiness: it is that **one spec crops the same thing in both reading directions**, because under
`dir=rtl` the sidebar moves to the other side and every x in the screenshot shifts by the sidebar's
width.

`extendBottom` carries the frame past anything measured, for the chart under a header that has no
stable handle to measure.

**A redaction covers a credential without editing the capture.** The widget's install snippet contains
a real website token, which belongs in the screenshot's composition and must not be published. A spec
may carry `"redact": [{ "box": "token", "label": "your website token" }]`, drawn into the annotation
layer over the capture — so the source keeps the pixels that were photographed, the figure never
carries the secret, and nobody has to retouch an image. It is a solid block rather than a blur,
because a blurred credential still looks like something a reader should go and find.

## Where the outputs go

They go wherever that consumer's own pipeline requires, because the two systems are different:

| Consumer | Output path | How it reaches a reader |
| --- | --- | --- |
| Documentation / Help Center | `custom/db/documentation/media/<key>.png` | `Documentation::MediaSeeder` attaches it to the portal, an article references it as `![alt](media:<key>)`, and it is served from `/hc/:slug/articles/:article_slug/media/*key`. **`bundle exec rails documentation:content` must run** — a file on disk is not published. |
| Marketing site | uploaded as a `SitePage` attachment | Super Admin → Site Pages → the row's **Images** panel, then an `image` or `walkthrough` section referencing the attachment id. The CMS owns it from then on; nothing is hardcoded in a template. |

## The keys

A documentation media key is lowercase, slash-separated, two to five segments, and ends in a real
image extension — `conversations/assign-agent-en.png`. That shape is enforced by
`Documentation::MediaResolver::KEY`, and it is case-sensitive on purpose: production storage is a
case-sensitive filesystem while a reviewer's laptop may not be, so a key differing only in case would
seed on one machine and 404 on the other.

## Rebuilding

```
node tools/visual/build-annotations.mjs            # regenerate every annotated output
node tools/visual/build-annotations.mjs --key conversations/assign-agent
```

`library.json` is the index. Each entry carries the metadata that makes an image replaceable a year
from now: what it shows, which application and screen it came from, the locale, the theme, the
viewport, the revision it was captured at, whether it is annotated, and which pages use it.

## The rule about words

An annotated image carries numbers, not sentences. The sentences live in the spec's `steps`, and the
consumer renders them as real text beside the picture — an `<ol>` in a marketing `walkthrough`
section, a numbered list in a documentation article. A number burnt into a PNG cannot be read by a
screen reader, translated, indexed, or enlarged by a reader who needs larger type. The picture shows
*where*; the text says *what*.

## When a run stops signing in

Each capture signs in through the real form, and the product caps concurrent sessions per user
(`DeviseOverrides::SessionsController#enforce_session_limit_for_password_login`). Once a few runs
have accumulated, the next sign-in answers **409** with a session picker rather than a token, and the
harness waits for a navigation that never happens. That is the product working; the fix is to clear
the container's own stale capture sessions first:

```
bundle exec rails runner 'u = User.find(1); u.tokens = {}; u.save!; u.user_sessions.destroy_all'
```

## Privacy

Every capture is taken against the local seeded database (`rails db:seed`, the `acme.inc` demo
account). There is no real customer conversation, contact, phone number or address in any of them.
Before a source is committed it is looked at. A screenshot that would need blurring is re-captured
with different data instead.

**One exception, and it is deliberate: a source can hold a website token.** The install-snippet
captures (`sources/app/{en,ar}/website-script.png`) show the seeded website channel's token in clear
text, because that is the screen -- the whole point of the figure is the snippet an administrator
copies. It is a value `rails db:seed` generated for an inbox whose `BASE_URL` is
`http://localhost:3000`; it authorises nothing anywhere else, and it is replaced the next time the
seed is rebuilt. The PUBLISHED figure covers it: the spec carries a `redact` box over the token, and
that is what the article shows. Treat the uncropped source as dev-only, and never point a `redact`
at a capture taken against anything but a local seed.
