<script setup>
import { computed, inject } from 'vue';

const props = defineProps({
  index: {
    type: Number,
    default: 0,
  },
  name: {
    type: String,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  count: {
    type: Number,
    default: 0,
  },
  showBadge: {
    type: Boolean,
    default: true,
  },
  isCompact: {
    type: Boolean,
    default: false,
  },
});

const activeIndex = inject('activeIndex');
const updateActiveIndex = inject('updateActiveIndex');

const active = computed(() => props.index === activeIndex.value);
const getItemCount = computed(() => props.count);

const onTabClick = event => {
  event.preventDefault();
  if (!props.disabled) {
    updateActiveIndex(props.index);
  }
};
</script>

<template>
  <li
    class="flex-shrink-0 my-0 mx-2 ltr:first:ml-0 rtl:first:mr-0 ltr:last:mr-0 rtl:last:ml-0"
  >
    <!-- A bare `<a>` with no `href` is not in the tab order and does not answer Enter, so the one control
    that chooses between All, Mine and Unattended -- and between the tabs on the inbox settings page --
    could only be reached with a mouse. A `<button>` costs nothing visually and is focusable and operable
    by keyboard by definition. -->
    <button
      type="button"
      class="flex items-center flex-row select-none relative after:absolute after:bottom-px after:left-0 after:right-0 after:h-[2px] after:rounded-full after:transition-all after:duration-200 text-button rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-50 disabled:cursor-not-allowed"
      :class="[
        active
          ? 'text-n-iris-11 after:bg-n-brand after:opacity-100'
          : 'text-n-slate-11 after:bg-transparent after:opacity-0 enabled:hover:text-n-slate-12',
        isCompact ? 'py-2.5' : '!text-base py-3',
        disabled ? '' : 'cursor-pointer',
      ]"
      :disabled="disabled"
      :aria-current="active ? 'true' : undefined"
      @click="onTabClick"
    >
      {{ name }}
      <div
        v-if="showBadge"
        class="rounded-full h-5 flex items-center justify-center text-xs font-medium my-0 ltr:ml-1 rtl:mr-1 px-1.5 py-0 min-w-[20px] tabular-nums"
        :class="[
          active
            ? 'bg-n-iris-3 text-n-iris-11'
            : 'bg-n-alpha-1 text-n-slate-11',
        ]"
      >
        <span>
          {{ getItemCount }}
        </span>
      </div>
    </button>
  </li>
</template>
