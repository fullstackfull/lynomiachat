<script setup>
// One surface at a time, chosen by ?surface=. The frame reproduces just enough of the dashboard chrome for the
// surface to sit where it really sits: settings pages get the settings column, the sidebar gets the app shell.
// Surfaces are kept alive because several real pages fetch in `onActivated` — a hook that never fires outside
// `<KeepAlive>`, which would leave those pages permanently empty here and understate their control surface.
import { computed, markRaw, onMounted, nextTick, ref, shallowRef, watch } from 'vue';
import { SURFACES } from './surfaces';

const params = new URLSearchParams(window.location.search);
const slug = params.get('surface') || 'flows-list';
const entry = computed(() => SURFACES[slug]);
const surface = shallowRef(null);
// Toggled once before capture so the kept-alive page is deactivated and reactivated. Vue registers a child's
// `activated` hook during its first render, which is after the keep-alive root has already mounted, so a page that
// fetches in `onActivated` (WhatsApp templates, for one) only fetches from the second activation onwards — the
// same thing that happens the first time a user navigates back to it.
const shown = ref(true);

const settle = async () => {
  shown.value = false;
  await nextTick();
  shown.value = true;
  await nextTick();
  await new Promise(resolve => {
    setTimeout(resolve, 150);
  });
  for (const selector of entry.value?.interactions || []) {
    // `text:Add label` finds a control by the words on it, for the buttons that carry no test id.
    const node = selector.startsWith('text:')
      ? [...document.querySelectorAll('button, a[href], [role="button"]')].find(
          candidate =>
            candidate.innerText.trim().toLowerCase() ===
            selector.slice(5).trim().toLowerCase()
        )
      : document.querySelector(selector);
    if (node) {
      node.click();
      // eslint-disable-next-line no-await-in-loop
      await nextTick();
    }
  }
  await nextTick();
  document.body.setAttribute('data-harness-ready', '1');
};

// The module is awaited rather than wrapped in `defineAsyncComponent`: an async wrapper is what `<KeepAlive>`
// would cache, and Vue reads `activated` hooks off the cached instance at mount time — before the real component
// exists. Pages that fetch in `onActivated` would then never fetch. Resolving first makes the page itself the
// keep-alive child, so its hooks run.
onMounted(async () => {
  if (!entry.value) {
    document.body.setAttribute('data-harness-ready', 'unknown-surface');
    return;
  }
  try {
    const module = await entry.value.load();
    surface.value = markRaw(module.default || module);
  } catch (error) {
    document.body.setAttribute('data-harness-ready', 'load-error');
    document.body.insertAdjacentHTML(
      'beforeend',
      `<pre style="padding:16px;font:12px monospace;white-space:pre-wrap">${slug}: ${error?.stack || error}</pre>`
    );
  }
});

watch(surface, value => value && setTimeout(settle, 400));
</script>

<template>
  <div v-if="!entry" class="p-6 text-sm">Unknown surface: {{ slug }}</div>

  <div v-else-if="entry.frame === 'sidebar'" class="flex h-screen bg-n-background">
    <KeepAlive>
      <component :is="surface" v-if="surface && shown" v-bind="entry.props || {}" />
    </KeepAlive>
    <div class="flex-1 bg-n-solid-1" />
  </div>

  <div
    v-else-if="entry.frame === 'settings'"
    class="flex flex-col w-full h-screen m-0 px-6 pt-4 pb-8 overflow-auto bg-n-surface-1"
  >
    <div class="flex items-start w-full max-w-5xl mx-auto">
      <KeepAlive>
        <component :is="surface" v-if="surface && shown" v-bind="entry.props || {}" />
      </KeepAlive>
    </div>
  </div>

  <div v-else class="w-full min-h-screen bg-n-background">
    <KeepAlive>
      <component :is="surface" v-if="surface && shown" v-bind="entry.props || {}" />
    </KeepAlive>
  </div>
</template>
