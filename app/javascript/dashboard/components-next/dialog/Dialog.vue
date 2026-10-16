<script setup>
import { ref, computed, getCurrentInstance } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useScrollLock } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'edit',
    validator: value => ['alert', 'edit'].includes(value),
  },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  cancelButtonLabel: {
    type: String,
    default: '',
  },
  confirmButtonLabel: {
    type: String,
    default: '',
  },
  disableConfirmButton: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  showCancelButton: {
    type: Boolean,
    default: true,
  },
  showConfirmButton: {
    type: Boolean,
    default: true,
  },
  overflowYAuto: {
    type: Boolean,
    default: false,
  },
  // Cap the dialog and scroll only its BODY, so the title and the footer stay put. Separate from
  // `overflowYAuto`, which scrolls the whole dialog, because the two are not interchangeable: a
  // scrolling body is a second, closer clipping box, and this product's ComboBox renders its dropdown
  // as an in-flow `absolute` child with no teleport (ComboBoxDropdown.vue:69), so any dialog with a
  // combobox in it loses roughly 5.5rem of room for that dropdown -- the gap, the footer row and the
  // form's own bottom padding -- which it used to have.
  //
  // That trade is right for a dialog whose previous state was a clipped popover and wrong for one that
  // already scrolled cleanly, so it is opted into per dialog rather than inferred.
  scrollBody: {
    type: Boolean,
    default: false,
  },
  width: {
    type: String,
    default: 'lg',
    validator: value => ['3xl', '2xl', 'xl', 'lg', 'md', 'sm'].includes(value),
  },
  position: {
    type: String,
    default: 'center',
    validator: value => ['center', 'top'].includes(value),
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const dialogContentRef = ref(null);
const isOpen = ref(false);

// The page scrolled behind an open dialog; `SidePanel` already locked it and `Dialog` did not.
const isPageScrollLocked = useScrollLock(document.body);

// The native `<dialog>` has no accessible name unless something points at the title.
const { uid } = getCurrentInstance();
const titleId = `dialog-title-${uid}`;
const descriptionId = `dialog-description-${uid}`;

const maxWidthClass = computed(() => {
  const classesMap = {
    '3xl': 'max-w-3xl',
    '2xl': 'max-w-2xl',
    xl: 'max-w-xl',
    lg: 'max-w-lg',
    md: 'max-w-md',
    sm: 'max-w-sm',
  };

  return classesMap[props.width] ?? 'max-w-md';
});

// `position: top` already pushes the dialog down by up to 5rem, so a plain 85vh cap could still run off the
// bottom of a short window.
const SCROLLING_BODY_HEIGHT = 'max-h-[calc(100dvh-8rem)]';

const positionClass = computed(() =>
  props.position === 'top' ? 'dialog-position-top' : ''
);

const open = () => {
  isOpen.value = true;
  isPageScrollLocked.value = true;
  dialogRef.value?.showModal();
};

const close = () => {
  emit('close');
  dialogRef.value?.close();
  isOpen.value = false;
  isPageScrollLocked.value = false;
};

// Only close if the close event originated from this dialog,
// not from a child dialog (e.g. ProseMirror prompt) bubbling up.
const handleDialogClose = e => e.target === dialogRef.value && close();

// Only close on click-outside if this dialog is the topmost one.
// If another dialog (e.g. ProseMirror prompt) is open on top, ignore.
const handleClickOutside = () => {
  const dialogs = document.querySelectorAll('dialog[open]');
  if (dialogs[dialogs.length - 1] === dialogRef.value) close();
};

const confirm = () => {
  emit('confirm');
};

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogRef"
      :aria-labelledby="title ? titleId : undefined"
      :aria-describedby="
        description || $slots.description ? descriptionId : undefined
      "
      class="w-full transition-all duration-300 ease-in-out shadow-modal rounded-overlay"
      :class="[
        maxWidthClass,
        positionClass,
        scrollBody ? 'overflow-hidden' : '',
        overflowYAuto ? 'overflow-y-auto' : '',
        !scrollBody && !overflowYAuto ? 'overflow-visible' : '',
      ]"
      @close.prevent="handleDialogClose"
    >
      <OnClickOutside @trigger="handleClickOutside">
        <form
          ref="dialogContentRef"
          class="flex flex-col w-full h-auto gap-6 p-6 overflow-visible text-start align-middle transition-all duration-300 ease-in-out transform bg-n-alpha-3 backdrop-blur-panel shadow-modal rounded-overlay"
          :class="scrollBody ? SCROLLING_BODY_HEIGHT : ''"
          @submit.prevent="confirm"
          @click.stop
        >
          <div
            v-if="title || description || $slots.description"
            class="flex flex-col gap-2"
          >
            <h3
              :id="titleId"
              class="text-base font-medium leading-6 text-n-slate-12"
            >
              {{ title }}
            </h3>
            <!-- `aria-describedby` on the <dialog> names this wrapper, not the paragraph
              inside it. Five of the six consumers that override `#description` never bound
              the slot's `descriptionId`, so the dialog pointed at an element that did not
              exist and announced no description at all. Holding the id here makes it true
              for every consumer, overriding or not; the slot prop stays exposed for the one
              that already uses it. -->
            <div
              v-if="description || $slots.description"
              :id="descriptionId"
              class="contents"
            >
              <slot name="description" :description-id="descriptionId">
                <p v-if="description" class="mb-0 text-sm text-n-slate-11">
                  {{ description }}
                </p>
              </slot>
            </div>
          </div>
          <!-- Dialog content will be injected here. Under `scrollBody` only this part scrolls, so a long
          form stops pushing its own submit button past the bottom of the screen. `contents` leaves every
          other dialog byte-identical: the slot's children stay direct flex items of the form. -->
          <div
            v-if="isOpen"
            :class="
              scrollBody
                ? 'flex flex-col gap-6 flex-1 min-h-0 overflow-y-auto -mx-6 px-6'
                : 'contents'
            "
          >
            <slot />
          </div>
          <slot name="footer">
            <div
              v-if="showCancelButton || showConfirmButton"
              class="flex items-center justify-between w-full gap-3"
            >
              <Button
                v-if="showCancelButton"
                variant="faded"
                color="slate"
                :label="cancelButtonLabel || t('DIALOG.BUTTONS.CANCEL')"
                class="w-full"
                type="button"
                @click="close"
              />
              <Button
                v-if="showConfirmButton"
                :color="type === 'edit' ? 'blue' : 'ruby'"
                :label="confirmButtonLabel || t('DIALOG.BUTTONS.CONFIRM')"
                class="w-full"
                :is-loading="isLoading"
                :disabled="disableConfirmButton || isLoading"
                type="submit"
              />
            </div>
          </slot>
        </form>
      </OnClickOutside>
    </dialog>
  </TeleportWithDirection>
</template>

<style scoped>
dialog::backdrop {
  @apply bg-n-alpha-black1 backdrop-blur-[4px];
}

.dialog-position-top {
  margin-top: clamp(2rem, 5vh, 5rem);
  margin-bottom: auto;
}
</style>
