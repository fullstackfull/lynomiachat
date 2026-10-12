<script setup>
/**
 * One contextual documentation link, at the moment somebody needs it.
 *
 * WHY A COMPONENT. The rule every documentation link in this product follows is "render NOTHING when this
 * installation has no article for that key" -- a branded installation with no DOCUMENTATION_URL configured
 * gets '' from `brandLink`, and a dangling "Learn more" that goes nowhere is worse than no link
 * (shared/composables/useBranding.js). That rule was being re-implemented at every call site with a `v-if`,
 * which is how one of them ends up without it. Here it is once.
 *
 * The key is a registry key, never a URL: `dashboard/helper/documentationLinks.js` owns the slug, so an
 * article can be renamed or reseeded without touching a Vue file.
 */
import { computed } from 'vue';
import { useBranding } from 'shared/composables/useBranding';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  // A key of DOC_ARTICLES. An unknown key resolves to '' and renders nothing, same as a missing article.
  articleKey: { type: String, required: true },
  label: { type: String, required: true },
});

const { docsLink } = useBranding();

const href = computed(() => docsLink(props.articleKey));
</script>

<template>
  <a
    v-if="href"
    :href="href"
    target="_blank"
    rel="noopener noreferrer"
    class="inline-flex items-center gap-1 text-link-small text-n-slate-11 hover:text-n-slate-12"
  >
    <Icon icon="i-lucide-book-open" class="size-3.5 shrink-0" />
    <span>{{ label }}</span>
  </a>
</template>
