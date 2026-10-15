<script setup>
import { computed, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
import { REPLY_EDITOR_MODES } from './constants';

const props = defineProps({
  mode: {
    type: String,
    default: REPLY_EDITOR_MODES.REPLY,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  isReplyRestricted: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggleMode']);

const wootEditorReplyMode = useTemplateRef('wootEditorReplyMode');
const wootEditorPrivateMode = useTemplateRef('wootEditorPrivateMode');

const replyModeSize = useElementSize(wootEditorReplyMode);
const privateModeSize = useElementSize(wootEditorPrivateMode);

/**
 * Computed boolean indicating if the editor is in private note mode
 * When isReplyRestricted is true, force switch to private note
 * Otherwise, respect the current mode prop
 * @type {ComputedRef<boolean>}
 */
const isPrivate = computed(() => {
  if (props.isReplyRestricted) {
    // Force switch to private note when replies are restricted
    return true;
  }
  // Otherwise respect the current mode
  return props.mode === REPLY_EDITOR_MODES.NOTE;
});

const isDisabled = computed(() => props.disabled || props.isReplyRestricted);

// The parent toggles rather than sets (`handleModeToggle` flips `mode`), so each segment emits only
// when it is not already the active one. Selecting the mode you are already in is a no-op here; before
// this it flipped you to the other one, which on a composer that chooses between a public reply and an
// internal note is the difference between answering the customer and talking about them.
const select = isNote => {
  if (isDisabled.value || isNote === isPrivate.value) return;
  emit('toggleMode');
};

/**
 * Computes the width of the sliding background chip in pixels
 * Includes 16px of padding in the calculation
 * @type {ComputedRef<string>}
 */
const width = computed(() => {
  const widthToUse = isPrivate.value
    ? privateModeSize.width.value
    : replyModeSize.width.value;

  const widthWithPadding = widthToUse + 16;
  return `${widthWithPadding}px`;
});

/**
 * Computes the X translation value for the sliding background chip
 * Translates by the width of reply mode + padding when in private mode
 * @type {ComputedRef<string>}
 */
const translateValue = computed(() => {
  const xTranslate = isPrivate.value ? replyModeSize.width.value + 16 : 0;

  return `${xTranslate}px`;
});

// Each segment reaches a 44px tall hit area through a transparent pseudo-element, so the control stays
// visually 32px tall inside the composer header without being a 32px tap target on touch.
const SEGMENT =
  "relative z-20 flex items-center gap-1 px-2 h-6 rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand before:content-[''] before:absolute before:-inset-y-2.5 before:inset-x-0";
</script>

<template>
  <div
    role="group"
    :aria-label="$t('CONVERSATION.REPLYBOX.MODE_SWITCHER')"
    class="relative z-0 flex items-center w-auto h-8 p-1 text-sm transition-all duration-300 ease-in-out rounded-full bg-n-slate-3"
  >
    <button
      ref="wootEditorReplyMode"
      type="button"
      :class="[
        SEGMENT,
        isPrivate ? 'text-n-slate-11' : 'text-n-slate-12 font-medium',
        isDisabled ? 'cursor-not-allowed' : 'cursor-pointer active:scale-95',
      ]"
      :disabled="isDisabled"
      :aria-pressed="!isPrivate"
      @click="select(false)"
    >
      {{ $t('CONVERSATION.REPLYBOX.REPLY') }}
    </button>
    <button
      ref="wootEditorPrivateMode"
      type="button"
      :class="[
        SEGMENT,
        isPrivate ? 'text-n-amber-12 font-medium' : 'text-n-slate-11',
        isDisabled ? 'cursor-not-allowed' : 'cursor-pointer active:scale-95',
      ]"
      :disabled="isDisabled"
      :aria-pressed="isPrivate"
      @click="select(true)"
    >
      {{ $t('CONVERSATION.REPLYBOX.PRIVATE_NOTE') }}
    </button>
    <div
      aria-hidden="true"
      class="absolute shadow-sm rounded-full h-6 w-[var(--chip-width)] ease-in-out translate-x-[var(--translate-x)] rtl:translate-x-[var(--rtl-translate-x)] ring-1 ring-inset"
      :class="[
        isPrivate
          ? 'bg-n-solid-amber ring-n-amber-12/20'
          : 'bg-n-background ring-n-weak',
        { 'transition-all duration-300': !isDisabled },
      ]"
      :style="{
        '--chip-width': width,
        '--translate-x': translateValue,
        '--rtl-translate-x': `calc(-1 * var(--translate-x))`,
      }"
    />
  </div>
</template>
