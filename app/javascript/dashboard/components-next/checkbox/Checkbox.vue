<script setup>
import { computed, useAttrs } from 'vue';

defineProps({
  indeterminate: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['change']);

// Attributes belong on the input, not the wrapper — without this a caller's `aria-label` lands on a
// `div` and the checkbox has no accessible name. `class` is the exception: call sites use it to
// position the whole control, so it stays on the wrapper.
defineOptions({ inheritAttrs: false });

const modelValue = defineModel('modelValue', {
  type: Boolean,
  default: false,
});

const handleChange = event => {
  modelValue.value = event.target.checked;
  emit('change', event);
};

const attrs = useAttrs();
const inputAttrs = computed(() => {
  const { class: _wrapperClass, ...rest } = attrs;
  return rest;
});
</script>

<template>
  <div class="relative w-4 h-4" :class="attrs.class">
    <input
      v-bind="inputAttrs"
      :checked="modelValue"
      :indeterminate="indeterminate"
      type="checkbox"
      :disabled="disabled"
      class="focus-ring peer absolute inset-0 z-10 h-4 w-4 disabled:opacity-50 appearance-none rounded border border-n-slate-6 transition-all duration-200 checked:border-n-brand checked:bg-n-brand dark:border-n-slate-7 dark:checked:border-n-brand indeterminate:border-n-brand indeterminate:bg-n-brand hover:enabled:bg-n-blue-border cursor-pointer"
      @change="handleChange"
    />
    <!-- Checkmark SVG -->
    <svg
      viewBox="0 0 14 14"
      fill="none"
      class="pointer-events-none absolute w-3.5 h-3.5 z-20 stroke-white opacity-0 peer-checked:opacity-100 transition-opacity duration-200 left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2"
    >
      <path
        d="M3 8L6 11L11 3.5"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    <!-- Minus/Indeterminate SVG -->
    <svg
      viewBox="0 0 14 14"
      fill="none"
      class="pointer-events-none absolute w-3.5 h-3.5 z-20 stroke-white opacity-0 peer-indeterminate:opacity-100 transition-opacity duration-200 left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2"
    >
      <path
        d="M3 7L11 7"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  </div>
</template>
