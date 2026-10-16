<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { getRandomColor } from 'dashboard/helper/labelColor';

import validations, { getLabelTitleErrorMessage } from './validations';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';

const props = defineProps({
  prefillTitle: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);

const title = ref('');
const description = ref('');
const color = ref('#000');
const showOnSidebar = ref(true);

const state = { title, description, color, showOnSidebar };
const v$ = useVuelidate(validations, state);

const uiFlags = useMapGetter('labels/getUIFlags');
const isCreating = computed(() => uiFlags.value.isCreating);

const titleError = computed(() => {
  const key = getLabelTitleErrorMessage(v$.value);
  return key ? t(key) : '';
});

// The dialog is mounted once now and reused, where the old modal built a fresh component on every
// open. So the form is cleared here instead of in `mounted`: without it, the next open would still
// hold the last label's text, and its colour would never change again.
const open = () => {
  title.value = props.prefillTitle.toLowerCase();
  description.value = '';
  color.value = getRandomColor();
  showOnSidebar.value = true;
  v$.value.$reset();
  dialogRef.value?.open();
};

const handleClose = () => emit('close');

const addLabel = async () => {
  const isValid = await v$.value.$validate();
  if (!isValid) return;

  try {
    await store.dispatch('labels/create', {
      color: color.value,
      description: description.value,
      // The API takes lowercase only; the field shows it that way as you type, and this is the
      // guarantee behind it.
      title: title.value.toLowerCase(),
      show_on_sidebar: showOnSidebar.value,
    });
    useAlert(t('LABEL_MGMT.ADD.API.SUCCESS_MESSAGE'));
    dialogRef.value?.close();
  } catch (error) {
    useAlert(error?.message || t('LABEL_MGMT.ADD.API.ERROR_MESSAGE'));
  }
};

defineExpose({ open, dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    :title="t('LABEL_MGMT.ADD.TITLE')"
    :description="t('LABEL_MGMT.ADD.DESC')"
    :confirm-button-label="t('LABEL_MGMT.FORM.CREATE')"
    :cancel-button-label="t('LABEL_MGMT.FORM.CANCEL')"
    :is-loading="isCreating"
    :disable-confirm-button="v$.title.$invalid || isCreating"
    @confirm="addLabel"
    @close="handleClose"
  >
    <Input
      v-model="title"
      :label="t('LABEL_MGMT.FORM.NAME.LABEL')"
      :placeholder="t('LABEL_MGMT.FORM.NAME.PLACEHOLDER')"
      :message="titleError"
      :message-type="titleError ? 'error' : 'info'"
      custom-input-class="lowercase"
      data-testid="label-title"
      @input="v$.title.$touch"
      @blur="v$.title.$touch"
    />

    <Input
      v-model="description"
      :label="t('LABEL_MGMT.FORM.DESCRIPTION.LABEL')"
      :placeholder="t('LABEL_MGMT.FORM.DESCRIPTION.PLACEHOLDER')"
      data-testid="label-description"
    />

    <!-- A group rather than a `label for`: the picker's root is a div, so an id put on it would not
      associate, and `for` only binds to a labelable element. -->
    <div
      role="group"
      aria-labelledby="label-color-label"
      class="flex flex-col gap-1"
    >
      <span id="label-color-label" class="text-sm font-medium text-n-slate-12">
        {{ t('LABEL_MGMT.FORM.COLOR.LABEL') }}
      </span>
      <!-- The picker panel is an in-flow `absolute` child, so this dialog must keep its default
        `overflow-visible` -- `scroll-body` would give the panel a second, closer clipping box and
        cut the bottom off it. The form is four fields; it does not need to scroll. -->
      <ColorPicker v-model="color" />
    </div>

    <!-- The label used to point `for` at an id that exists nowhere in this codebase, so the text did
      not toggle the box and a screen reader announced an unnamed checkbox. -->
    <div class="flex items-center gap-2">
      <Checkbox id="label-show-on-sidebar" v-model="showOnSidebar" />
      <label
        for="label-show-on-sidebar"
        class="text-sm cursor-pointer text-n-slate-12"
      >
        {{ t('LABEL_MGMT.FORM.SHOW_ON_SIDEBAR.LABEL') }}
      </label>
    </div>
  </Dialog>
</template>
