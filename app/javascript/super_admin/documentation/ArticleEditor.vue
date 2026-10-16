<script setup>
/**
 * The Super Admin documentation editor. Markdown source on the left, the real renderer's HTML on the right.
 *
 * WHY SOURCE AND NOT WYSIWYG. Orchestrator ruling R3 point 2 gates the installed ProseMirror editor on a corpus
 * round-trip test. It fails: a parse-and-serialize of all 126 corpus files comes back changed, in five measured
 * classes (corpusRoundTrip.spec.js). So this is ruling R3 point 3 -- "increment one", the textarea upgrade --
 * built as a source editor, which cannot have a round-trip problem because the stored bytes are the bytes on
 * screen. The ProseMirror pair is still the target and the spec is the gate that opens it.
 *
 * SUPER ADMIN ONLY. This component is mounted only from the Super Admin article form. It adds no
 * tenant-reachable route, action or policy grant; tenants remain documentation readers (P0-2).
 */
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import {
  bold,
  italic,
  inlineCode,
  heading,
  bulletList,
  orderedList,
  blockquote,
  codeBlock,
  table,
  link,
  insertBlock,
} from './markdownCommands';
import {
  imagesMissingAlt,
  dataImageDestinations,
  mediaKeyOnLine,
} from './contentChecks';
import {
  uploadMedia,
  replaceMedia,
  isAcceptedImage,
  ACCEPTED_TYPES,
} from './mediaUpload';

const props = defineProps({
  componentData: {
    type: Object,
    required: true,
  },
});

// Long enough that typing a sentence is one render, short enough to feel live. The preview is a server round
// trip, so this is the only throttle between the keyboard and ChatwootMarkdownRenderer.
const PREVIEW_DEBOUNCE_MS = 400;

/**
 * The documentation corpus has exactly two locales, `en` and `ar`
 * (custom/app/services/documentation/library.rb:14), and `ar` is right-to-left.
 *
 * This list lives here because a no-exclusion search found NO server-side direction source to read it from: the
 * portal layout sets only `lang` on `<html>` (app/views/layouts/portal.html.erb:2, via
 * PortalHelper#html_lang_attribute at app/helpers/portal_helper.rb:40-42) and there is no `dir` attribute and no
 * RTL constant anywhere in app/, lib/ or custom/. That is a gap on the PUBLIC page too, reported rather than
 * fixed here because the portal layout is not this agent's file.
 */
const RTL_LOCALES = ['ar'];

const data = props.componentData;
const labels = data.labels;

const source = ref(data.content ?? '');
const initial = data.content ?? '';
const textarea = ref(null);
const fileInput = ref(null);

// The Administrate form this editor is mounted inside. Resolved on mount; read by the media and submit paths.
let form = null;

const previewHtml = ref('');
const previewing = ref(true);
const previewPending = ref(false);
const uploading = ref(false);
const errorMessage = ref('');
const altPrompt = ref(null);
const replacing = ref(false);
const replacedKey = ref(null);

const isRtl = computed(() => RTL_LOCALES.includes(data.locale));
const direction = computed(() => (isRtl.value ? 'rtl' : 'ltr'));
const isDirty = computed(() => source.value !== initial);

const missingAlt = computed(() => imagesMissingAlt(source.value));
const dataImages = computed(() => dataImageDestinations(source.value));
const blockers = computed(() => {
  const found = [];
  if (missingAlt.value.length) {
    found.push({ key: 'alt', lines: missingAlt.value.map(i => i.line) });
  }
  if (dataImages.value.length) {
    found.push({ key: 'dataImage', lines: dataImages.value.map(i => i.line) });
  }
  return found;
});

// --- applying a command ------------------------------------------------------------------------------------

/**
 * Commands are applied through `execCommand('insertText')` rather than by assigning `.value`, so a toolbar edit
 * joins the browser's own undo stack and Cmd/Ctrl+Z undoes it the way it undoes typing. That is the whole of
 * "undo/redo" here, and it is the native one rather than a second history of our own.
 *
 * `execCommand` reports failure by returning false, and the fallback uses that return value rather than assuming
 * it: without one a failed call would silently drop the operator's edit.
 */
const applyCommand = command => {
  const element = textarea.value;
  if (!element) return;

  const { from, to, text, selectionStart, selectionEnd } = command(
    element.value,
    element.selectionStart,
    element.selectionEnd
  );

  element.focus();
  element.setSelectionRange(from, to);

  // `insertText` is deprecated but present in every browser, and it is the only way to put a programmatic edit
  // on a textarea's native undo stack. It reports failure by returning false, and `setRangeText` -- the standard
  // call, which does not preserve undo -- is what then applies the edit rather than losing it.
  const inserted =
    typeof document.execCommand === 'function' &&
    document.execCommand('insertText', false, text);
  if (!inserted) element.setRangeText(text, from, to, 'end');

  element.setSelectionRange(selectionStart, selectionEnd);
  source.value = element.value;
};

const onInput = event => {
  source.value = event.target.value;
};

// --- preview -----------------------------------------------------------------------------------------------

let previewTimer = null;
let previewRequest = null;

/**
 * The preview is rendered by ChatwootMarkdownRenderer#render_article on the server -- the same call the public
 * article page makes (app/controllers/public/api/v1/portals/articles_controller.rb:113). A Markdown
 * implementation in the browser would be a second renderer and would show something the published page does not.
 */
const refreshPreview = async () => {
  previewRequest?.abort();
  previewRequest = new AbortController();
  previewPending.value = true;

  try {
    const response = await fetch(data.previewEndpoint, {
      method: 'POST',
      credentials: 'same-origin',
      signal: previewRequest.signal,
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token':
          document.querySelector('meta[name="csrf-token"]')?.content ?? '',
      },
      body: JSON.stringify({
        article: { content: source.value, id: data.articleId },
      }),
    });
    previewHtml.value = response.ok ? await response.text() : '';
  } catch (error) {
    if (error.name !== 'AbortError') previewHtml.value = '';
  } finally {
    previewPending.value = false;
  }
};

watch([source, previewing], () => {
  if (!previewing.value) return;
  clearTimeout(previewTimer);
  previewTimer = setTimeout(refreshPreview, PREVIEW_DEBOUNCE_MS);
});

// --- media -------------------------------------------------------------------------------------------------

/**
 * Insertion is two steps and the alt text comes FIRST, because `Documentation::MediaUpload#create!` takes the
 * alt, refuses a blank one and returns the finished Markdown (R2-MEDIA-INTERFACE.md section 9.2). So the editor
 * never composes a `media:` string and the alt requirement cannot be skipped by a client that forgets it.
 */
const pendingFile = ref(null);

const describe = file => {
  altPrompt.value = { alt: '' };
  pendingFile.value = file;
};

/**
 * The portal is read live from the form's own select rather than passed in as a prop. The `media:` namespace is
 * per-portal (R2-MEDIA-CONTRACT.md section 0.2) and the operator chooses the portal on this same form, including
 * on a new article that has no portal yet -- so the select is the only truthful source, and an upload before one
 * is chosen is a state the operator can reach and gets told about.
 */
const selectedPortalId = () =>
  form?.querySelector(`[name="${data.portalFieldName}"]`)?.value ?? '';

const insertUploaded = async () => {
  const alt = altPrompt.value.alt.trim();
  if (alt === '') return;

  uploading.value = true;
  errorMessage.value = '';
  try {
    const result = await uploadMedia(pendingFile.value, {
      endpoint: data.mediaEndpoint,
      portalId: selectedPortalId(),
      alt,
    });
    // The server's own Markdown, inserted verbatim.
    applyCommand(insertBlock(result.markdown));
    altPrompt.value = null;
    pendingFile.value = null;
  } catch (error) {
    errorMessage.value = error.message;
  } finally {
    uploading.value = false;
  }
};

const cancelAlt = () => {
  altPrompt.value = null;
  pendingFile.value = null;
};

// Checked before the alt is asked for, so the operator is not made to describe an image that cannot be stored.
const accept = file => {
  if (!isAcceptedImage(file)) {
    errorMessage.value = labels.unsupportedType;
    return false;
  }
  if (selectedPortalId() === '') {
    errorMessage.value = labels.choosePortalFirst;
    return false;
  }
  return true;
};

const offer = file => {
  if (accept(file)) describe(file);
};

/**
 * Replacement (F1): same key, new bytes, so the reference already in the article and its alt stay as they are.
 * The key comes from the image on the caret's line, and the server refuses a key the SEEDER owns -- the corpus
 * is the source of truth for corpus content, so that edit could not survive the next seed.
 */
const replaceAtCaret = async file => {
  if (!accept(file)) return;

  const key = mediaKeyOnLine(source.value, textarea.value?.selectionStart ?? 0);
  if (key === null) {
    errorMessage.value = labels.noImageAtCaret;
    return;
  }

  uploading.value = true;
  errorMessage.value = '';
  try {
    await replaceMedia(file, {
      endpoint: data.mediaEndpoint,
      portalId: selectedPortalId(),
      key,
    });
    errorMessage.value = '';
    replacedKey.value = key;
  } catch (error) {
    errorMessage.value = error.message;
  } finally {
    uploading.value = false;
  }
};

const onFilePicked = event => {
  const [file] = event.target.files ?? [];
  if (file) {
    if (replacing.value) replaceAtCaret(file);
    else offer(file);
  }
  event.target.value = '';
  replacing.value = false;
};

const pickFile = forReplacement => {
  replacing.value = forReplacement;
  fileInput.value.click();
};

const onDrop = event => {
  event.preventDefault();
  const [file] = event.dataTransfer?.files ?? [];
  if (file) offer(file);
};

/**
 * A pasted image file becomes an upload. A pasted `data:image/*` STRING is refused rather than inserted:
 * R2-MEDIA-INTERFACE.md section 8.2 puts writing one into `content` out of bounds, and the pattern to follow is
 * the existing editorHelper.js:43-54.
 */
const onPaste = event => {
  const [file] = [...(event.clipboardData?.files ?? [])];
  if (file) {
    event.preventDefault();
    offer(file);
    return;
  }
  const text = event.clipboardData?.getData('text/plain') ?? '';
  if (/data:image\//i.test(text)) {
    event.preventDefault();
    errorMessage.value = labels.dataImageRefused;
  }
};

// --- form integration --------------------------------------------------------------------------------------

/**
 * Publication is blocked at submit, not by hiding the submit button: an operator needs to be told why. The
 * server-side enforcement is the seed boundary and the renderer's sanitizer; this is the readable message.
 */
const onSubmit = event => {
  if (blockers.value.length === 0) return;
  event.preventDefault();
  errorMessage.value = labels.blockedSubmit;
};

const onBeforeUnload = event => {
  if (!isDirty.value) return;
  event.preventDefault();
  event.returnValue = '';
};

onMounted(() => {
  form = textarea.value?.closest('form');
  form?.addEventListener('submit', onSubmit);
  window.addEventListener('beforeunload', onBeforeUnload);
  if (previewing.value) refreshPreview();
});

onBeforeUnmount(() => {
  clearTimeout(previewTimer);
  previewRequest?.abort();
  form?.removeEventListener('submit', onSubmit);
  window.removeEventListener('beforeunload', onBeforeUnload);
});

const toolbar = computed(() => [
  { key: 'h2', label: labels.heading2, command: heading(2) },
  { key: 'h3', label: labels.heading3, command: heading(3) },
  { key: 'bold', label: labels.bold, command: bold },
  { key: 'italic', label: labels.italic, command: italic },
  { key: 'inlineCode', label: labels.inlineCode, command: inlineCode },
  { key: 'bulletList', label: labels.bulletList, command: bulletList },
  { key: 'orderedList', label: labels.orderedList, command: orderedList },
  { key: 'blockquote', label: labels.blockquote, command: blockquote },
  { key: 'codeBlock', label: labels.codeBlock, command: codeBlock() },
  { key: 'table', label: labels.table, command: table() },
  { key: 'link', label: labels.link, command: link('') },
]);

const acceptAttribute = ACCEPTED_TYPES.join(',');
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <button
        v-for="item in toolbar"
        :key="item.key"
        type="button"
        class="px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-slate-3"
        @click="applyCommand(item.command)"
      >
        {{ item.label }}
      </button>

      <button
        type="button"
        class="px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-slate-3"
        :disabled="uploading"
        @click="pickFile(false)"
      >
        {{ uploading ? labels.uploading : labels.insertImage }}
      </button>

      <button
        type="button"
        class="px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-slate-3"
        :disabled="uploading"
        @click="pickFile(true)"
      >
        {{ labels.replaceImage }}
      </button>
      <input
        ref="fileInput"
        type="file"
        class="hidden"
        :accept="acceptAttribute"
        @change="onFilePicked"
      />

      <button
        type="button"
        class="px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-slate-3 ms-auto"
        @click="previewing = !previewing"
      >
        {{ previewing ? labels.hidePreview : labels.showPreview }}
      </button>
    </div>

    <p v-if="errorMessage" class="m-0 text-sm text-n-ruby-11">
      {{ errorMessage }}
    </p>

    <p v-if="replacedKey" class="m-0 text-sm text-n-teal-11">
      {{ labels.replacedImage }} {{ replacedKey }}
    </p>

    <ul v-if="blockers.length" class="m-0 ps-5 text-sm text-n-amber-11">
      <li v-for="blocker in blockers" :key="blocker.key">
        {{ labels[blocker.key === 'alt' ? 'missingAlt' : 'dataImageFound'] }}
        {{ blocker.lines.join(', ') }}
      </li>
    </ul>

    <div
      class="grid gap-4"
      :class="previewing ? 'lg:grid-cols-2' : 'grid-cols-1'"
    >
      <textarea
        :id="data.fieldId"
        ref="textarea"
        :name="data.fieldName"
        :dir="direction"
        :value="source"
        rows="28"
        class="w-full p-3 font-mono text-sm leading-6 rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12"
        @input="onInput"
        @paste="onPaste"
        @drop="onDrop"
        @dragover.prevent
      />

      <section v-if="previewing" :dir="direction" class="min-w-0">
        <p class="m-0 mb-2 text-xs uppercase tracking-wide text-n-slate-11">
          {{ previewPending ? labels.previewUpdating : labels.previewTitle }}
        </p>
        <!--
          `v-html`, not the harness's `v-dompurify-html`, and deliberately: this HTML comes from
          ChatwootMarkdownRenderer#render_article, which already escapes and sanitizes
          (lib/markdown_renderer_url_sanitizer.rb, lib/markdown_renderer_fence_info_escaping.rb) and which
          intentionally emits <iframe> for the video embeds in config/markdown_embeds.yml. Sanitizing again here
          would strip those and make the preview differ from the page that publishes -- the drift this endpoint
          exists to prevent.
        -->
        <!-- eslint-disable-next-line vue/no-v-html -->
        <div class="min-w-0" v-html="previewHtml" />
      </section>
    </div>

    <div
      v-if="altPrompt"
      class="flex flex-col gap-2 p-3 rounded-md border border-solid border-n-weak bg-n-solid-2"
    >
      <p class="m-0 text-sm text-n-slate-12">{{ labels.altRequired }}</p>
      <p class="m-0 text-xs text-n-slate-11">{{ labels.altHint }}</p>
      <input
        v-model="altPrompt.alt"
        data-testid="alt-input"
        type="text"
        class="w-full px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12"
        @keydown.enter.prevent="insertUploaded"
      />
      <div class="flex gap-2">
        <button
          type="button"
          class="px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12"
          data-testid="alt-confirm"
          :disabled="altPrompt.alt.trim() === '' || uploading"
          @click="insertUploaded"
        >
          {{ labels.altConfirm }}
        </button>
        <button
          type="button"
          class="px-2 py-1 text-sm rounded-md border border-solid border-n-weak bg-n-solid-1 text-n-slate-12"
          @click="cancelAlt"
        >
          {{ labels.altCancel }}
        </button>
      </div>
    </div>
  </div>
</template>
