---
agent: 019
scope: WhatsApp Cloud API media — upload vs hosted link, the supported-type/size table, captions, filenames, media ID lifetime, media send failures, and resumable-upload handles for templates
confidence: high
sources_normative: 14
sources_observational: 2
---

## 1. Source register

Every claim below cites a row ID from this table. All fetches were read-only GETs of public
documentation pages. No Graph endpoint was called, no credential was used, no form was submitted.

| Row | Source URL | Page title | Product | API / version context | Date checked | Status |
|---|---|---|---|---|---|---|
| R1 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/media` | Media | WhatsApp Cloud API | none stated on page | 2026-10-13 | normative |
| R2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/media` | Media | WhatsApp Cloud API (current docs IA) | none stated on page | 2026-10-13 | normative |
| R3 | `https://developers.facebook.com/docs/whatsapp/cloud-api/messages/image-messages/` | Image messages | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R4 | `https://developers.facebook.com/docs/whatsapp/cloud-api/messages/document-messages/` | Document messages | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R5 | `https://developers.facebook.com/docs/whatsapp/cloud-api/messages/audio-messages/` | Audio messages | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R6 | `https://developers.facebook.com/docs/whatsapp/cloud-api/messages/video-messages/` | Video Messages | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R7 | `https://developers.facebook.com/docs/whatsapp/cloud-api/messages/sticker-messages/` | Sticker messages | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R8 | `https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-messages/` | Service messages | WhatsApp Cloud API | none stated | 2026-10-13 | normative |
| R9 | `https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes` | Error codes / WhatsApp error codes | WhatsApp Cloud API + Marketing Messages API | HTTP statuses given only in the Marketing Messages API table | 2026-10-13 | normative |
| R10 | `https://developers.facebook.com/docs/graph-api/guides/upload` | Upload a File or Video — Video API | Graph API (Resumable Upload API) | examples on `v26.0` | 2026-10-13 | normative |
| R11 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/overview` | Template fundamentals | WhatsApp Business Management API | none stated | 2026-10-13 | normative |
| R12 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/marketing-templates/media-card-carousel-templates/` | Media card carousel templates | WhatsApp Business Management API | none stated | 2026-10-13 | normative |
| R13 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages/` | Messages (Cloud API reference) | WhatsApp Cloud API | none stated | 2026-10-13 | normative, but the per-type field tables did not render — see §6 |
| R14 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-phone-number/message-api` | WhatsApp Cloud API — Message API | WhatsApp Cloud API | none stated | 2026-10-13 | normative, but the per-type field tables did not render — see §6 |
| O1 | search-engine summary attributed to R14 | — | — | — | 2026-10-13 | **observational, unconfirmed** — claim that a media `link` "must use HTTP or HTTPS". Not found in any page body I read. |
| O2 | search-engine summary attributed to R13 / On-Premises API notes | — | — | — | 2026-10-13 | **observational, unconfirmed** — claim that "captions are currently not supported for document media". Directly contradicted by R4. |

R1 and R2 are the same content under the old and new documentation information architectures. They
agree on every row of the media table; where one states something the other does not, both rows are
cited.

## 2. The rules

### 2.1 The two ways to attach media, and the trade-offs Meta states

There are exactly two. A media object in a send request "A media object. Either `id` or `link` is
required." (R13, R14).

**Path A — upload first, send a media ID.** `POST /PHONE_NUMBER_ID/media` returns an `id`; that `id`
goes in the message's media object.

**Path B — point at a public URL.** The media object carries `link` instead, "URL of the media asset
hosted on your public server" (R5), and no prior upload happens.

Meta's stated trade-offs are narrow, and they all point the same direction:

- Every per-type page recommends the ID. Image, audio and sticker pages all use the same sentence:
  "For better performance, we recommend using `id` and an uploaded media asset ID instead."
  (R3, R5, R7). The document page says "For better performance, we recommend using `id`" and labels
  the `link` field "(not recommended)" (R4). The video page marks `id` "Required if using an uploaded
  media asset (recommended)" and `link` "Required if linking to your media asset (not recommended)",
  with "For better performance, upload your media asset instead." (R6).
- The only mechanism Meta gives for the performance difference is caching of the link path: "the
  Cloud API internally caches the asset for 10 minutes" (R8). The cached asset "is reused in
  subsequent send message requests" when the link matches the original request, and to defeat that
  reuse the guidance is to "append a random query string to the asset link in the new send message
  request payload" (R8).

That caching note is the one place Meta describes a behavioural (not merely performance) difference:
with Path B, replacing the file at a stable URL does not necessarily change what recipients receive
for up to 10 minutes. Path A has no such effect — a media ID is bound to the bytes uploaded.

Meta does **not** state, on any page I read: an HTTPS requirement for `link` (see O1 and §6), a
content-type-header matching requirement for the fetched URL, a timeout for the fetch, a maximum
redirect count, or what happens if both `id` and `link` are supplied.

### 2.2 The upload endpoint

`POST /PHONE_NUMBER_ID/media` (R1, R2). Three parameters, all required (R1, R2):

| Parameter | Meta's description |
|---|---|
| `file` | path to the file in your local directory, e.g. `@/local/path/file.jpg` |
| `type` | the media type being uploaded |
| `messaging_product` | use `whatsapp` |

No optional parameters are listed. A successful response contains `id`, the media ID (R1).

R1 states that uploaded files are encrypted and persist for 30 days unless deleted earlier, and warns
that a mismatched MIME type (error `131053`) is a common error, with the suggested check being to
inspect the file's MIME type and confirm the file extension matches it.

The companion endpoints, for completeness (Agent 020 owns retrieval in depth):

| Operation | Endpoint | Notes (R1) |
|---|---|---|
| Retrieve media URL | `GET /MEDIA_ID` | returns `url` (valid 5 minutes), `mime_type`, `sha256`, `file_size`, `id`; optional `phone_number_id` query parameter limits processing to the phone number the media was uploaded on |
| Download media | `GET /MEDIA_URL` | access token required in the `Authorization` header; omitting it causes the request to fail; `404 Not Found` means request a new media URL and retry |
| Delete media | `DELETE /MEDIA_ID` | same optional `phone_number_id`; returns `"success": true` |

### 2.3 Media ID lifetime

Three different clocks, all from R1 and R2:

- **Media IDs returned by the API expire after 30 days.** (R1, R2)
- **Media IDs in webhooks expire after 7 days.** R2's wording: "Media IDs in webhooks expire after 7
  days." R1 words it "Media IDs in incoming webhooks expire after 7 days."
- **Media URLs expire after 5 minutes.** (R1) — the `url` from `GET /MEDIA_ID`, not the media ID.

R1 additionally frames the first clock as storage: uploaded files "persist for 30 days unless deleted
earlier".

### 2.4 Captions, per type

| Type | Caption field present | Meta's stated limit | Row |
|---|---|---|---|
| image | yes, optional | "Maximum 1024 characters." | R3 |
| video | yes, optional | "Maximum 1024 characters." | R6 |
| document | yes, optional | "Maximum 1024 characters." | R4 |
| audio | **no** — the audio object's fields are `id`, `link`, `voice` only; no caption field is described | n/a | R5 |
| sticker | **no** — the sticker object's fields are `id` and `link` only; the page does not state whether stickers support captions | not stated | R7 |

The document row carries a contradiction with an older note; see §6.1. Treat R4 as current.

### 2.5 Filename handling for documents

`filename` is optional on the document object: "the document filename, with extension" (R4). Meta's
only stated effect is display: "The WhatsApp client will use an appropriate file type icon based on
the extension." (R4).

R4 does **not** state what the WhatsApp client shows when `filename` is omitted, and does not state
whether the extension in `filename` must agree with the uploaded file's actual MIME type. R4 does say
that only the PDF, Word, Excel, PowerPoint and text formats on its list are supported and guaranteed
to display correctly.

### 2.6 Type-specific constraints beyond MIME and size

- **Images** must be "8-bit, RGB or RGBA" (R1, R2, R3).
- **WebP is sticker-only.** "WebP images can only be sent in sticker messages." (R2); R1 words it
  "WebP files may only be sent in sticker messages."
- **Video codecs**: "Only H.264 video codec and AAC audio codec supported. Single audio stream or no
  audio stream only." R6 also warns that "videos encoded with the H.264 'High' profile and B-frames
  are not supported by Android WhatsApp clients."
- **Audio OGG**: the MIME cell itself carries the constraint — "audio/ogg (OPUS codecs only; base
  audio/ogg not supported; mono input only)" (R1, R2, R5).
- **Voice messages**: the audio object has an optional boolean `voice`; set `true` for a voice
  message, and "Voice messages must be Ogg files encoded with the OPUS codec"; for a basic audio
  message set it `false` or omit it (R5).
- **Sticker dimensions**: not specified. R7 only says a request fails if "the sticker isn't a
  supported WebP type".

## 3. Error codes and failures

Meta's own words, from R9 unless another row is cited. R9's Cloud API table has no HTTP-status
column; HTTP statuses appear only in R9's Marketing Messages API table, and are marked as such.

| Code | Subcode | Title / `details` as Meta words it | What it means | What the business can do | What the end user sees | Row |
|---|---|---|---|---|---|---|
| 131053 | not stated | "Unable to upload the media used in the message." | The media the business tried to send could not be uploaded. Meta's own expansion: "The media could not be uploaded for one or more reasons, such as an unsupported media type." R1 and R2 both name a mismatched MIME type as the common cause. | "Inspect any media files that are causing errors and confirm that they are in fact supported." Check `error.error_data.details` in the messages webhook triggered when the message fails to send. R1/R2 add: inspect the file's MIME type and make sure the file extension matches it. | not stated | R9, R1, R2 |
| 131052 | not stated | R9 `details`: "Unable to download the media sent by the user." R2 states the title as "Media file size too big. Max file size we currently support: 100MB." | Meta uses this one code for two framings — a failed download of inbound user media (R9) and an inbound file over the 100 MB ceiling (R1, R2). See §6.2. | "Ask the WhatsApp user to send you the media file using a non-WhatsApp method." Check `error.error_data.details` in messages webhooks. R1/R2: warn the customer when this webhook fires. | The user's send appears to succeed on their side; the business never receives the file | R9, R1, R2 |
| 131051 | not stated | "Unsupported message type." | The `type` on the message is not a supported message type. | "See Messages for supported message types before trying again with a supported message type." | not stated | R9 |
| 131009 | not stated | "One or more parameter values are invalid." | A supplied value is not accepted — the generic landing place for a bad `type` value or malformed media object. | "See the endpoint's reference to determine which values are supported for each parameter." | not stated | R9 |
| 131008 | not stated | "The request is missing a required parameter." | A required field is absent — e.g. neither `id` nor `link` on the media object, or a missing `messaging_product` on upload. | "See the endpoint's reference to determine which parameters are required." | not stated | R9 |
| 100 | not stated | "The request included one or more unsupported or misspelled parameters." | Unknown or misspelled parameter; R9 also ties a length violation to this code. | "Ensure your parameter is under any length restriction for the type." | not stated | R9 (400 Bad Request in R9's Marketing Messages API table) |
| — | — | **unsupported media type** | No dedicated code. Meta routes it through 131053, naming "an unsupported media type" as a cause of that code. | — | — | R9 |
| — | — | **outbound media too large** | **No code is published.** R9 has no row for an outbound file exceeding a per-type limit. R1 states only that "Media messages on Cloud API have a maximum supported file size of 100MB" and ties the 100 MB case to inbound 131052. | — | — | R1, R9 |
| — | — | **link unreachable** | **No code is published.** R9 contains no row mentioning a link, a URL, or a fetch failure. 131053 is the nearest documented code but Meta does not name this cause under it. | — | — | R9 |
| — | — | **link not HTTPS** | **No code is published**, and no normative page I read states a protocol requirement at all (see O1, §6.3). | — | — | R9 |
| — | — | **upload endpoint failure** | R2 states plainly that it "does not list a specific error code for upload failures". | — | — | R2 |
| — | — | **media download by business fails** | Not a numbered code: `GET /MEDIA_URL` returns `404 Not Found`, and the instruction is to request a new media URL and retry; if that fails, renew the access token. | — | — | R1, R2 |

Two structural facts matter more than the individual rows for a troubleshooting article:

1. **Media send failures are reported asynchronously.** For both 131052 and 131053, R9's instruction
   is to read `error.error_data.details` in the **messages webhook** — for 131053, specifically the
   webhook "triggered when this message fails to send". R9 does not say these codes are returned in
   the immediate send response. A Lynomia user whose file "would not send" therefore sees the send
   accepted and the failure arrive later as a status change.
2. **The authoritative detail is in `error.error_data.details`, not the code.** Both media codes are
   coarse; Meta's own guidance is to read the free-text `details`. Any Lynomia troubleshooting
   article should surface that string, not just the numeric code.

Codes I saw only in a search-engine summary and could not confirm in a page body (e.g. `133004` for a
temporarily unavailable server) are **not** recorded as media errors here.

## 4. Limits and numbers

Every number below is quoted from a Meta table. Nothing in this section is inferred.

### 4.1 The complete supported-media table

Rows exactly as R1 and R2 publish them. R1 and R2 are identical on every row.

**Audio** — max size 16 MB for every format.

| Audio Type | Extension | MIME Type | Max Size |
|---|---|---|---|
| AAC | .aac | audio/aac | 16 MB |
| AMR | .amr | audio/amr | 16 MB |
| MP3 | .mp3 | audio/mpeg | 16 MB |
| MP4 Audio | .m4a | audio/mp4 | 16 MB |
| OGG Audio | .ogg | audio/ogg (OPUS codecs only; base audio/ogg not supported; mono input only) | 16 MB |

**Document** — max size 100 MB for every format.

| Document Type | Extension | MIME Type | Max Size |
|---|---|---|---|
| Text | .txt | text/plain | 100 MB |
| Microsoft Excel | .xls | application/vnd.ms-excel | 100 MB |
| Microsoft Excel | .xlsx | application/vnd.openxmlformats-officedocument.spreadsheetml.sheet | 100 MB |
| Microsoft Word | .doc | application/msword | 100 MB |
| Microsoft Word | .docx | application/vnd.openxmlformats-officedocument.wordprocessingml.document | 100 MB |
| Microsoft PowerPoint | .ppt | application/vnd.ms-powerpoint | 100 MB |
| Microsoft PowerPoint | .pptx | application/vnd.openxmlformats-officedocument.presentationml.presentation | 100 MB |
| PDF | .pdf | application/pdf | 100 MB |

**Image** — Meta's heading carries the constraint: "Image (8-bit, RGB or RGBA)".

| Image Type | Extension | MIME Type | Max Size |
|---|---|---|---|
| JPEG | .jpeg | image/jpeg | 5 MB |
| PNG | .png | image/png | 5 MB |

**Sticker** — the only type whose limit splits by variant.

| Sticker Type | Extension | MIME Type | Max Size |
|---|---|---|---|
| Animated sticker | .webp | image/webp | 500 KB |
| Static sticker | .webp | image/webp | 100 KB |

**Video**

| Video Type | Extension | MIME Type | Max Size |
|---|---|---|---|
| 3GPP | .3gp | video/3gpp | 16 MB |
| MP4 Video | .mp4 | video/mp4 | 16 MB |

### 4.2 Other published numbers

| Number | What it governs | Row |
|---|---|---|
| 100 MB | "Media messages on Cloud API have a maximum supported file size of 100MB" — the platform ceiling, above any per-type limit; exceeded by an inbound file, it produces 131052 | R1 |
| 1024 characters | caption maximum for image, video and document | R3, R6, R4 |
| 30 days | media IDs returned by the API expire; uploaded files persist unless deleted earlier | R1, R2 |
| 7 days | media IDs in webhooks expire | R1, R2 |
| 5 minutes | validity of the `url` returned by `GET /MEDIA_ID` | R1 |
| 10 minutes | Cloud API's internal cache of an asset fetched from a `link` | R8 |

No number appears in this report that is not in one of these rows. In particular: there is **no**
published maximum for the number of media IDs an account may hold, no published upload rate limit on
`POST /PHONE_NUMBER_ID/media`, no published sticker pixel dimensions, and no published maximum size
for template header media (§5).

## 5. Resumable upload and media handles for template creation

This is a **separate upload path with a separate output**, and conflating the two is the single most
likely authoring error in a Lynomia template article.

### 5.1 How the two paths differ

| | Message media | Template header media |
|---|---|---|
| Endpoint | `POST /PHONE_NUMBER_ID/media` (R1, R2) | Resumable Upload API: `POST /<APP_ID>/uploads`, then `POST /upload:<UPLOAD_SESSION_ID>` (R10) |
| Scoped to | a business phone number | an app |
| Output | a media **ID**, returned as `id` (R1) | a file **handle**, returned as `h` (R10) |
| Consumed by | the media object of a send request (`image.id`, `document.id`, …) | the template creation request, at `example.header_handle` (R12) |
| Lifetime | 30 days for API-returned IDs (R1, R2) | not stated on R10, R11 or R12 |
| Reviewed by Meta | no | yes — "The example asset will be reviewed as part of template review." (R11) |

R11 states the requirement directly: "Template header components can display media assets", and for
them "you must use the Resumable Upload API to obtain an asset handle" and "include this asset handle
in your template creation request."

### 5.2 The Resumable Upload API itself (R10)

Examples on the page run against `v26.0` of `https://graph.facebook.com/`.

1. **Start a session.** `POST /<APP_ID>/uploads` with query parameters `file_name` (the file's name),
   `file_length` (file size in bytes), `file_type` (MIME type) and `access_token`. Returns
   `"id": "upload:<UPLOAD_SESSION_ID>"`.
2. **Transfer.** `POST /upload:<UPLOAD_SESSION_ID>` with headers `Authorization: OAuth <USER_ACCESS_TOKEN>`
   and `file_offset: 0`, body sent as binary. Returns `"h": "<UPLOADED_FILE_HANDLE>"`. R10 states:
   "You must include the access token in the header or the call will fail."
3. **Resume after interruption.** `GET /upload:<UPLOAD_SESSION_ID>` with the `Authorization: OAuth`
   header returns `"file_offset": "<FILE_OFFSET>"`; re-`POST` with `file_offset` set to that value.
   R10 describes the API's purpose as resuming "interrupted upload sessions without having to start
   over".

**Accepted types for resumable upload (R10)** — a much shorter list than the message media table:

| Format | `file_type` value |
|---|---|
| pdf | application/pdf |
| jpeg | image/jpeg |
| jpg | image/jpg |
| png | image/png |
| mp4 | video/mp4 |

R10 states no maximum file size; it only describes the API as being for "large files". R10 also notes
that endpoint references indicate whether they accept handles from the Resumable Upload API.

### 5.3 Where the handle goes in a template

From R12, for a media card carousel template, the handle sits at
`components[] → cards[] → components[] → example.header_handle`, an array holding the handle string,
on a component of `"type": "header"` with a `"format"` whose "Value can be `image` or `video`."
R12's instruction: "Use the Resumable Upload API to generate an asset handle." R12 also notes that
"Media assets are automatically cropped to a wide ratio based on the WhatsApp user's device."

R11 and R12 state **no** file size limit and **no** MIME type list for template header media. The
only type constraint found is R12's `image` or `video` format values for carousel card headers, and
R10's accepted-format list for the upload itself. A Lynomia article must not assert that the message
media table (§4.1) applies to template headers — Meta does not say that.

## 6. Ambiguities and gaps

### 6.1 Document captions — two Meta positions

R4 (Document messages, Cloud API) documents `caption` as optional on the document object with
"Maximum 1024 characters." A search-engine summary attributed to R13 and to On-Premises API notes
claims the opposite — that captions are "currently not supported for document media" and that
`filename` should be used instead (O2). I could not reproduce that statement from any page body I
read; R13's and R14's per-type field tables rendered as empty headings. **Recorded as an ambiguity,
not resolved.** For a Lynomia composer article, R4 is the current Cloud API page and should be
followed, with the behaviour verified against the live product before being published as fact.

R4 also has a rendering defect worth noting so a future reader does not read significance into it:
its request template lists `caption` twice, while its example request includes it once.

### 6.2 Error 131052 carries two different titles

R9's `details` for 131052 is "Unable to download the media sent by the user." R2 gives 131052 the
title "Media file size too big. Max file size we currently support: 100MB." These are not the same
failure — one is a download failure of any cause, the other is specifically a size ceiling. Meta
publishes both under the same code. A Lynomia error article must present 131052 as covering both, and
must direct the reader to `error.error_data.details` to distinguish them.

### 6.3 No published rule for the `link` path's protocol or reachability

Nothing I read states that a media `link` must be HTTPS, must be publicly reachable without
authentication, must return a matching `Content-Type`, or how long Meta will wait for the fetch. O1
records the HTTPS claim as observational and unconfirmed. There is likewise **no published error code**
for a link that cannot be fetched. This is the largest gap for a "my file would not send"
troubleshooting article: the most common real-world cause of a link-path failure has no documented
code and no documented rule.

### 6.4 Sticker captions are unstated, not forbidden

R7 lists only `id` and `link` on the sticker object and is silent on captions. Absence of the field
from the table is strong evidence, but R7 does not say "captions are not supported for stickers". The
report records this as *not stated* rather than asserting a prohibition.

### 6.5 The two handle formats do not match

R10's sample uploaded-file handle begins `2:c2FtcGxl…`. R12's sample template header handle begins
`4::anBlZw==:ARa525ZJ1g0J-8egeiRvb4Z4…`. Both are labelled example values. Meta does not publish a
handle grammar, and these two shapes differ. No Lynomia article should assert a handle format; it
should only say the handle is an opaque string returned by the Resumable Upload API.

### 6.6 The current reference pages are hollow

R13 and R14 are the canonical "Messages" references, and on 2026-10-13 their `AudioMessage`,
`VideoMessage`, `DocumentMessage`, `ImageMessage` and `StickerMessage` sections rendered as headings
with no property tables; `MediaObject` resolved to one sentence, "A media object. Either `id` or
`link` is required." Every field-level fact in this report therefore comes from the per-type guide
pages (R3–R7), not from the reference. If Meta repopulates those references, the per-type pages
should be re-checked against them before a Lynomia article is frozen.

### 6.7 Other unanswered questions

- What happens if both `id` and `link` are set on one media object — not stated anywhere.
- Whether a `filename` extension that disagrees with the file's real MIME type is rejected or merely
  mislabelled — not stated (R4).
- Whether an outbound file over a per-type limit fails at upload, at send, or at delivery, and under
  which code — not stated.
- Sticker pixel dimensions — not stated (R7).
- Template header media size and MIME limits — not stated (R10, R11, R12).

## 7. What Lynomia users would ask

These are the questions this area produces for the Platform Support desk, in the order they are most
likely to arrive.

1. **"Why won't my file send?"** The answer needs the §4.1 table and the asynchronous-failure fact
   from §3: the send is accepted, the failure arrives as a message status with 131053 and a
   `details` string. A troubleshooting article that only lists codes will not help; it must tell the
   agent where to find `error.error_data.details`.
2. **"My image is only 6 MB, that's tiny."** The image limit is 5 MB, not the 100 MB platform
   ceiling, and not the 16 MB that applies to audio and video. The per-type split is the single most
   surprising part of the table and deserves to lead the composer article.
3. **"I uploaded a WebP and it failed."** WebP is sticker-only (R1, R2), and the sticker limits are
   100 KB static / 500 KB animated — three orders of magnitude below the image limit.
4. **"My MP4 plays fine on my laptop but not in WhatsApp."** H.264 and AAC only, single or no audio
   stream, and the Android warning about H.264 High profile with B-frames (R6).
5. **"My voice note sends as a file."** The `voice` boolean, and the Ogg/OPUS requirement for voice
   messages (R5); plus the OGG MIME constraint — OPUS only, mono input only (R1, R2, R5).
6. **"Why is there no caption on my audio message?"** Audio and sticker have no caption field
   (R5, R7). Image, video and document do, at 1024 characters (R3, R6, R4 — with §6.1's caveat for
   document).
7. **"The customer sees a strange filename."** `filename` is optional and drives the file-type icon
   (R4); Meta does not state the fallback when it is omitted.
8. **"I replaced the file on our server but customers still get the old one."** The 10-minute link
   cache, and the random-query-string workaround (R8).
9. **"A media link in an old conversation is dead."** Three clocks, easily confused: 30 days for an
   API-returned media ID, 7 days for a webhook media ID, 5 minutes for a retrieved media URL
   (R1, R2). Agent 020 owns the retrieval side.
10. **"My template was rejected / the header image won't attach."** Template header media is a
    different upload path producing a handle, not a media ID, and the example asset is reviewed as
    part of template review (R10, R11, R12). Agents 009 and 012 own the template surface; this report
    owns the upload mechanics.
11. **"A customer sent a 200 MB video and we never got it."** 100 MB platform ceiling, inbound
    failure surfaces as 131052, and Meta's own guidance is to warn the customer (R1, R2).
12. **"Should we upload or link?"** Meta recommends the ID on every per-type page (R3–R7). The
    composer article should say so, and say why: the cache, and Meta's stated performance preference.
