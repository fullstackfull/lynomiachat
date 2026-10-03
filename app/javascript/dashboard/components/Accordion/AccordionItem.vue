<script setup>
import { getCurrentInstance } from 'vue';
import EmojiOrIcon from 'shared/components/EmojiOrIcon.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  compact: {
    type: Boolean,
    default: false,
  },
  icon: {
    type: String,
    default: '',
  },
  emoji: {
    type: String,
    default: '',
  },
  isOpen: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['toggle']);

// Ties the header to the panel it opens, so a screen reader announces the state and can jump to the contents.
const panelId = `accordion-panel-${getCurrentInstance().uid}`;

const onToggle = () => {
  emit('toggle');
};
</script>

<template>
  <div class="text-sm">
    <button
      type="button"
      class="flex items-center select-none w-full rounded-surface bg-n-slate-2 outline outline-1 outline-n-weak m-0 cursor-grab justify-between py-2 px-4 accordion-drag-handle focus-ring"
      :class="{ 'rounded-bl-none rounded-br-none': isOpen }"
      :aria-expanded="isOpen"
      :aria-controls="panelId"
      @click.stop="onToggle"
    >
      <div class="flex justify-between">
        <EmojiOrIcon class="inline-block w-5" :icon="icon" :emoji="emoji" />
        <h3 class="text-heading-3 text-n-slate-12 mb-0 py-0 pe-2 ps-0">
          {{ title }}
        </h3>
      </div>
      <div class="flex flex-row">
        <slot name="button" />
        <div class="flex items-center justify-end size-4 text-n-slate-11">
          <fluent-icon v-if="isOpen" size="16" icon="subtract" type="solid" />
          <fluent-icon v-else size="16" icon="add" type="solid" />
        </div>
      </div>
    </button>
    <div
      v-if="isOpen"
      :id="panelId"
      class="outline outline-1 outline-n-weak -mt-[-1px] border-t-0 rounded-br-surface rounded-bl-surface"
      :class="compact ? 'p-0' : 'px-2 py-4'"
    >
      <slot />
    </div>
  </div>
</template>
