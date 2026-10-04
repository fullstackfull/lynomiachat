<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import {
  useWindowSize,
  useElementBounding,
  onClickOutside,
} from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';

defineProps({
  option: {
    type: Object,
    default: () => {},
  },
  subMenuAvailable: {
    type: Boolean,
    default: true,
  },
});

const menuRef = useTemplateRef('menuRef');
const isRTL = useMapGetter('accounts/isRTL');
const { width: windowWidth, height: windowHeight } = useWindowSize();
const { bottom, right, left } = useElementBounding(menuRef);

// Hover alone used to be the only thing that opened the submenu, which left priority, label, agent and team
// assignment with no keyboard or touch path at all. A click or Enter now latches it open as well.
const isOpen = ref(false);
onClickOutside(menuRef, () => {
  isOpen.value = false;
});

// Vertical position
const verticalPosition = computed(() => {
  const SUBMENU_HEIGHT = 240; // 15rem in pixels
  const spaceBelow = windowHeight.value - bottom.value;
  return spaceBelow < SUBMENU_HEIGHT ? 'bottom-0' : 'top-0';
});

// Horizontal position. The submenu opens along the reading direction and flips only when that side is out of
// room; measuring `windowWidth - right` in both directions sent every Arabic submenu the wrong way.
const horizontalPosition = computed(() => {
  const SUBMENU_WIDTH = 240;
  const spaceAhead = isRTL.value ? left.value : windowWidth.value - right.value;
  return spaceAhead < SUBMENU_WIDTH ? 'end-full' : 'start-full';
});

const submenuPosition = computed(() => [
  verticalPosition.value,
  horizontalPosition.value,
]);
</script>

<template>
  <div
    ref="menuRef"
    role="menuitem"
    :tabindex="subMenuAvailable ? 0 : -1"
    :aria-haspopup="subMenuAvailable ? 'true' : undefined"
    :aria-expanded="subMenuAvailable ? isOpen : undefined"
    class="text-n-slate-12 group focus-ring min-w-[12.5rem] max-w-[18rem] w-full p-1 flex items-center h-7 rounded-md relative bg-n-alpha-3/50 backdrop-blur-panel justify-between hover:bg-n-brand/10 cursor-pointer dark:hover:bg-n-solid-3"
    :class="!subMenuAvailable ? 'opacity-50 cursor-not-allowed' : ''"
    @click="subMenuAvailable && (isOpen = !isOpen)"
    @keydown.enter.prevent="subMenuAvailable && (isOpen = !isOpen)"
    @keydown.space.prevent="subMenuAvailable && (isOpen = !isOpen)"
    @keydown.esc="isOpen = false"
  >
    <div class="flex items-center h-4 min-w-0">
      <fluent-icon :icon="option.icon" size="14" />
      <p :title="option.label" class="my-0 mx-2 text-xs truncate">
        {{ option.label }}
      </p>
    </div>
    <fluent-icon icon="chevron-right" size="12" class="rtl:rotate-180" />
    <div
      v-if="subMenuAvailable"
      class="submenu bg-n-alpha-3 backdrop-blur-panel p-1 shadow-overlay rounded-md absolute max-h-[15rem] overflow-y-auto overflow-x-hidden cursor-pointer group-hover:block group-focus-within:block"
      :class="[submenuPosition, isOpen ? 'block' : 'hidden']"
    >
      <slot />
    </div>
  </div>
</template>
