<script setup>
import { computed } from 'vue';

const props = defineProps({
  isChecked: {
    type: Boolean,
    default: false,
  },
  value: {
    type: String,
    default: null,
  },
  // Without this the accessible name falls back to the `id`, which is the storage key — a screen reader
  // read out "email_conversation_creation" for a box whose column heading is the only thing that says
  // "Email".
  label: { type: String, default: '' },
});

const emit = defineEmits(['update']);

const checked = computed({
  get: () => props.isChecked,
  set: value => emit('update', props.value, value),
});
</script>

<template>
  <input
    :id="value"
    v-model="checked"
    type="checkbox"
    :value="value"
    :aria-label="label || undefined"
    class="flex-shrink-0 mt-0.5 border-n-strong border bg-n-slate-2 checked:border-none checked:bg-n-brand shadow-sm appearance-none rounded-[4px] w-4 h-4 focus:ring-1 after:content-[''] after:text-white checked:after:content-['✓'] after:flex after:items-center after:justify-center after:text-center after:text-xs after:font-bold after:relative"
  />
</template>
