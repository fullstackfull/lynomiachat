<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import validations, { getLabelTitleErrorMessage } from './validations';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';

const props = defineProps({
  selectedResponse: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);

const title = ref('');
const description = ref('');
const color = ref('');
const showOnSidebar = ref(true);

const state = { title, description, color, showOnSidebar };
const v$ = useVuelidate(validations, state);

const uiFlags = useMapGetter('labels/getUIFlags');
const isUpdating = computed(() => uiFlags.value.isUpdating);

const dialogTitle = computed(
  () => `${t('LABEL_MGMT.EDIT.TITLE')} - ${props.selectedResponse?.title ?? ''}`
);

const titleError = computed(() => {
  const key = getLabelTitleErrorMessage(v$.value);
  return key ? t(key) : '';
});

// The dialog stays mounted between openings now, where the old modal built a fresh component each
// time and filled it in `mounted`. Two things follow. The prop is watched, so picking a different
// label refills the form; and the fill runs again on open, because re-opening the SAME label after
// typing into it leaves the prop identical and would otherwise keep the abandoned edit.
const fillFromProp = () => {
  const label = props.selectedResponse;
  title.value = label?.title ?? '';
  description.value = label?.description ?? '';
  color.value = label?.color ?? '';
  showOnSidebar.value = label?.show_on_sidebar ?? true;
  v$.value.$reset();
};

watch(() => props.selectedResponse, fillFromProp, {
  immediate: true,
  deep: true,
});

const open = () => {
  fillFromProp();
  dialogRef.value?.open();
};

const handleClose = () => emit('close');

const editLabel = async () => {
  const isValid = await v$.value.$validate();
  if (!isValid) return;

  try {
    await store.dispatch('labels/update', {
      id: props.selectedResponse.id,
      color: color.value,
      description: description.value,
      title: title.value.toLowerCase(),
      show_on_sidebar: showOnSidebar.value,
    });
    useAlert(t('LABEL_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    dialogRef.value?.close();
  } catch (error) {
    useAlert(error?.message || t('LABEL_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

defineExpose({ open, dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    :title="dialogTitle"
    :confirm-button-label="t('LABEL_MGMT.FORM.EDIT')"
    :cancel-button-label="t('LABEL_MGMT.FORM.CANCEL')"
    :is-loading="isUpdating"
    :disable-confirm-button="v$.title.$invalid || isUpdating"
    @confirm="editLabel"
    @close="handleClose"
  >
    <Input
      v-model="title"
      :label="t('LABEL_MGMT.FORM.NAME.LABEL')"
      :placeholder="t('LABEL_MGMT.FORM.NAME.PLACEHOLDER')"
      :message="titleError"
      :message-type="titleError ? 'error' : 'info'"
      custom-input-class="lowercase"
      @input="v$.title.$touch"
      @blur="v$.title.$touch"
    />

    <Input
      v-model="description"
      :label="t('LABEL_MGMT.FORM.DESCRIPTION.LABEL')"
      :placeholder="t('LABEL_MGMT.FORM.DESCRIPTION.PLACEHOLDER')"
    />

    <!-- A group rather than a `label for`: the picker's root is a div, so an id put on it would not
      associate, and `for` only binds to a labelable element. -->
    <div
      role="group"
      aria-labelledby="edit-label-color-label"
      class="flex flex-col gap-1"
    >
      <span
        id="edit-label-color-label"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ t('LABEL_MGMT.FORM.COLOR.LABEL') }}
      </span>
      <!-- Default overflow, not `scroll-body`: the picker panel is an in-flow `absolute` child, and
        a scrolling body would clip it. -->
      <ColorPicker v-model="color" />
    </div>

    <!-- The label used to point `for` at an id that exists nowhere in this codebase, so the text did
      not toggle the box and a screen reader announced an unnamed checkbox. -->
    <div class="flex items-center gap-2">
      <Checkbox id="edit-label-show-on-sidebar" v-model="showOnSidebar" />
      <label
        for="edit-label-show-on-sidebar"
        class="text-sm cursor-pointer text-n-slate-12"
      >
        {{ t('LABEL_MGMT.FORM.SHOW_ON_SIDEBAR.LABEL') }}
      </label>
    </div>
  </Dialog>
</template>
