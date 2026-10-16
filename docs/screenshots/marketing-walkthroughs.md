# Putting a product screenshot on a marketing page

The `walkthrough` section renders one genuine screenshot of the running product beside — or above —
the numbered points it illustrates. This is how an operator adds one, and why it has to be an
operator rather than a deploy.

## Why this is a manual step on an existing install

`Marketing::ContentSeeder` **never overwrites a page that already exists**
(`custom/app/services/marketing/content_seeder.rb:5-7`). That is the rule that stops a deploy
discarding an operator's edits, and it is the right rule. It also means a section added to
`Marketing::ContentBlueprint` reaches a fresh install and *no existing one*.

A walkthrough also needs an `attachment_id`, which is the id of an ActiveStorage attachment on that
page's own row. There is no id to write into a blueprint, because the attachment does not exist
until somebody uploads the file to that page. So a shipped walkthrough is not possible even in
principle: the picture is per-row data.

Both facts point the same way. The section type, the renderer, the validation and the images ship in
the repository; putting one on a live page is three minutes in Super Admin, per page, and the copy
below is ready to paste.

## The steps

1. **Super Admin → Site Pages**, and open the row for the page and locale you want. English and
   Arabic are separate rows; each needs its own upload and its own section.
2. In the **Images** panel, upload the screenshot from `docs/screenshots/sources/`. PNG, JPEG, GIF or
   WebP, 2 MB maximum, no SVG. The page lists the attachment and its **id** after the upload.
3. In **Sections**, add a row, choose **walkthrough**, and fill it in:
   - **heading**, **lede** — the section's own title and one sentence under it.
   - **attachment_id** — the id from step 2.
   - **alt** — what the screenshot *shows*. Not the steps: those are already on the page as text, and
     a screen reader would otherwise read them twice.
   - **media_position** — `top` for a screenshot of a whole screen, which is the only position it
     stays readable in; `start` or `end` for a detail beside the text. Never left or right: the page
     renders in both directions.
   - **items** — one per marker, `title` and `body`.
4. Set the row's **position** so the section lands where you want it, and save. The page validates on
   save: an unknown `media_position`, a missing attachment or a bad field is refused with the reason.
5. **Preview** the page, in both locales, and look at it.

## The copy that is already written

The `unified-inbox` row — the page served at `/features/unified-inbox`, and at `/en/features/…` for
its English twin — has been built and photographed in **both locales**; the finished pages are in
`docs/redesign/evidence/final/marketing-walkthrough/`. Each row carries its own locale's screenshot:
the English page shows the dashboard in English, the Arabic page shows it in Arabic, right-to-left.
Reuse the copy verbatim or edit it in the form — it is operator content from the moment it is saved.

## Two rules worth keeping

- **The words live in `items`, not in the picture.** The markers on an annotated screenshot are
  numbers; the sentences are rows the template renders as a real ordered list. A sentence burnt into
  a PNG cannot be read aloud, translated, indexed or enlarged.
- **Re-photograph, don't retouch.** When a screen changes, re-run the capture
  (`docs/screenshots/README.md`) and upload the new file. Editing pixels to match a claim is the one
  thing this whole pipeline exists to prevent.
