<script setup>
import { useI18n } from 'vue-i18n';

import EmojiIcon from 'dashboard/components-next/emoji-icon-picker/EmojiIcon.vue';

defineProps({
  items: {
    type: Array,
    required: true,
  },
});

const emit = defineEmits(['click']);

const { t } = useI18n();

const onClick = (item, index) => {
  emit('click', item, index);
};
</script>

<template>
  <nav
    :aria-label="t('BREADCRUMB.ARIA_LABEL')"
    class="flex items-center h-8 min-w-0"
  >
    <ol class="flex items-center mb-0 min-w-0">
      <li
        v-for="(item, index) in items"
        :key="index"
        class="flex items-center"
        :class="{ 'min-w-0 flex-1': index === items.length - 1 }"
      >
        <!-- A separator that does not mirror points back up the trail in Arabic. It is also
          decoration the <ol> already expresses, so it stays out of the reading order -- which needs a
          bare span: `Icon` renders `h('span', { class })` and forwards no other attribute, so
          `aria-hidden` on it would never reach the DOM. Same shape as Sidebar.vue:1106. -->
        <span
          v-if="index > 0"
          aria-hidden="true"
          class="i-lucide-chevron-right flex-shrink-0 mx-2 size-4 text-n-slate-11 dark:text-n-slate-11 rtl:rotate-180"
        />

        <!-- Render as button for all except the last item -->
        <button
          v-if="index !== items.length - 1"
          class="inline-flex items-center justify-center min-w-0 gap-2 p-0 text-sm font-medium transition-all duration-200 ease-in-out border-0 rounded-lg text-n-slate-11 hover:text-n-slate-12 outline-transparent max-w-56"
          @click="onClick(item, index)"
        >
          <span class="min-w-0 truncate">{{ item.label }}</span>
        </button>

        <!-- The last breadcrumb item is plain text -->
        <span
          v-else
          class="inline-flex items-center gap-1 text-sm truncate min-w-0"
        >
          <EmojiIcon
            v-if="item.emoji"
            :value="item.emoji"
            :color="item.iconColor"
            class="flex-shrink-0 size-4"
          />
          <span class="truncate text-n-slate-12">{{ item.label }}</span>
        </span>
      </li>
    </ol>
  </nav>
</template>
