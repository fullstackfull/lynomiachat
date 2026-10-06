<script setup>
// What a shared audience is, said where someone needs to know it
// (docs/product-enablement/13-audience-ux-implementation.md).
//
// The campaign picker used to answer "you have no audiences" with one sentence inside a dropdown the user had no
// reason to open, naming a destination it could not take them to. The missing part was never the sentence: it was
// that nobody had said what an audience IS, or why it is not the same thing as a label. Both explanations belong
// next to the choice, not in documentation, so this is a component rather than a string.
//
// `action` is a slot because the useful button differs by surface: the campaign offers "create one and come back",
// the audiences page offers "create" and "browse presets".
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  // Show the label-versus-audience rule. On by default: the distinction is the thing people get wrong.
  showLabelRule: { type: Boolean, default: true },
  // A quieter inline form for sitting inside a form section, rather than a standalone card.
  compact: { type: Boolean, default: false },
});

const { tm, t } = useI18n();

// `tm` returns the translated array itself, so the examples stay in the locale file where a translator can edit
// them, rather than being assembled from numbered keys.
const examples = computed(() => {
  const list = tm('CONTACTS_FILTER.AUDIENCE.EXPLAINER.EXAMPLES');
  return Array.isArray(list) ? list.map(item => item.loc?.source ?? item) : [];
});

const containerClass = computed(() =>
  props.compact
    ? 'flex flex-col gap-2 rounded-lg bg-n-alpha-1 p-3'
    : 'flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4'
);
</script>

<template>
  <div :class="containerClass" data-test-id="audience-explainer">
    <div class="flex items-start gap-2">
      <Icon
        icon="i-lucide-users-round"
        class="mt-0.5 size-4 shrink-0 text-n-slate-11"
        aria-hidden="true"
      />
      <div class="flex flex-col gap-1">
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CONTACTS_FILTER.AUDIENCE.EXPLAINER.TITLE') }}
        </p>
        <p class="mb-0 text-label-small text-n-slate-11">
          {{ t('CONTACTS_FILTER.AUDIENCE.EXPLAINER.BODY') }}
        </p>
      </div>
    </div>

    <div v-if="examples.length" class="flex flex-col gap-1.5">
      <p class="mb-0 text-label-small text-n-slate-11">
        {{ t('CONTACTS_FILTER.AUDIENCE.EXPLAINER.EXAMPLES_TITLE') }}
      </p>
      <ul class="flex flex-wrap gap-1.5 p-0 m-0 list-none">
        <li
          v-for="example in examples"
          :key="example"
          class="rounded-md bg-n-alpha-2 px-2 py-1 text-label-small text-n-slate-11"
        >
          {{ example }}
        </li>
      </ul>
    </div>

    <div
      v-if="showLabelRule"
      class="flex flex-col gap-1 border-t border-n-weak pt-3"
    >
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('CONTACTS_FILTER.AUDIENCE.VS_LABEL.TITLE') }}
      </p>
      <p class="mb-0 text-label-small text-n-slate-11">
        {{ t('CONTACTS_FILTER.AUDIENCE.VS_LABEL.LABEL') }}
      </p>
      <p class="mb-0 text-label-small text-n-slate-11">
        {{ t('CONTACTS_FILTER.AUDIENCE.VS_LABEL.AUDIENCE') }}
      </p>
      <p class="mb-0 text-label-small font-medium text-n-slate-12">
        {{ t('CONTACTS_FILTER.AUDIENCE.VS_LABEL.RULE') }}
      </p>
    </div>

    <div v-if="$slots.action" class="flex flex-wrap items-center gap-2">
      <slot name="action" />
    </div>
  </div>
</template>
