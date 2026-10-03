<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

// The designed empty state the data-imports page already had, extracted so the rest of Settings can stop
// answering "nothing here yet" with one centred sentence and no way to fix it. The action is a slot: an
// empty list is the one moment a page should offer the thing that fills it.
defineProps({
  icon: {
    type: String,
    default: 'i-lucide-inbox',
  },
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div
    class="flex min-h-80 flex-col items-center justify-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 px-6 py-16 text-center"
  >
    <span
      class="flex size-12 items-center justify-center rounded-full bg-n-alpha-2"
      aria-hidden="true"
    >
      <Icon :icon="icon" class="size-5 text-n-slate-11" />
    </span>
    <div class="flex flex-col gap-1">
      <h3 class="text-heading-2 text-n-slate-12">{{ title }}</h3>
      <p v-if="description" class="max-w-sm text-body-main text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <slot name="action" />
  </div>
</template>
