<script setup>
// `item` is passed straight back out through the slot; the row itself never reads it. It stays in the
// API because every call site already binds it and the slot prop is what the row's cells destructure.
defineProps({
  item: {
    type: Object,
    default: null,
  },
  // Row feedback while scanning across a wide row. Opt out on rows that are purely decorative.
  hoverable: {
    type: Boolean,
    default: true,
  },
  selected: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <tr
    class="group/row transition-colors"
    :class="{
      'hover:bg-n-slate-2 dark:hover:bg-n-solid-3': hoverable && !selected,
      'bg-n-slate-2 dark:bg-n-solid-3': selected,
    }"
    :aria-selected="selected || null"
  >
    <slot :item="item" />
  </tr>
</template>
