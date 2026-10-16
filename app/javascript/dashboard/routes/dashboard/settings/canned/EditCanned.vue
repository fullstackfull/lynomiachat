<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';

const props = defineProps({
  id: { type: Number, default: null },
  edcontent: { type: String, default: '' },
  edshortCode: { type: String, default: '' },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isUpdating = ref(false);

const shortCode = ref('');
const content = ref('');

const v$ = useVuelidate(
  {
    shortCode: { required, minLength: minLength(2) },
    content: { required },
  },
  { shortCode, content }
);

// `$touch` on its own changes nothing a user can see. `Input` draws the red outline and the
// message from `message` + `message-type`, so the touched state has to reach it.
const shortCodeError = computed(() =>
  v$.value.shortCode.$error ? t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.ERROR') : ''
);

const isInvalid = computed(
  () => v$.value.shortCode.$invalid || v$.value.content.$invalid
);

const dialogTitle = computed(
  () => `${t('CANNED_MGMT.EDIT.TITLE')} - ${props.edshortCode}`
);

// The dialog is reused between openings now, so the fill follows the props and runs again on open:
// picking a different response refills it, and re-opening the same one after abandoning an edit
// does not keep the abandoned edit.
const fillFromProps = () => {
  shortCode.value = props.edshortCode;
  content.value = props.edcontent;
  v$.value.$reset();
};

watch(() => [props.id, props.edshortCode, props.edcontent], fillFromProps, {
  immediate: true,
});

const open = () => {
  fillFromProps();
  dialogRef.value?.open();
};

const handleClose = () => emit('close');

const editCannedResponse = async () => {
  if (isInvalid.value) return;
  isUpdating.value = true;
  try {
    await store.dispatch('updateCannedResponse', {
      id: props.id,
      short_code: shortCode.value,
      content: content.value,
    });
    useAlert(t('CANNED_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    dialogRef.value?.close();
  } catch (error) {
    useAlert(error?.message || t('CANNED_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isUpdating.value = false;
  }
};

defineExpose({ open, dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="xl"
    :title="dialogTitle"
    :confirm-button-label="t('CANNED_MGMT.EDIT.FORM.SUBMIT')"
    :cancel-button-label="t('CANNED_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
    :is-loading="isUpdating"
    :disable-confirm-button="isInvalid || isUpdating"
    @confirm="editCannedResponse"
    @close="handleClose"
  >
    <Input
      v-model="shortCode"
      :label="t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.LABEL')"
      :placeholder="t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.PLACEHOLDER')"
      :message="shortCodeError"
      :message-type="shortCodeError ? 'error' : 'info'"
      @input="v$.shortCode.$touch"
    />

    <!-- A group, not a `label for`: `WootMessageEditor`'s root is a div, and `for` binds only to a
      labelable element, so an id on it associates with nothing. Same shape as the colour row in the
      label dialogs. -->
    <div
      role="group"
      aria-labelledby="canned-edit-content-label"
      class="flex flex-col gap-1"
    >
      <span
        id="canned-edit-content-label"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ t('CANNED_MGMT.EDIT.FORM.CONTENT.LABEL') }}
      </span>
      <!-- Arbitrary variants in place of the scoped SCSS `:deep()` block this file used to carry. -->
      <WootMessageEditor
        v-model="content"
        class="message-editor [&>div]:px-1 [&_.ProseMirror-menubar]:!hidden [&_.ProseMirror-woot-style]:min-h-[12.5rem]"
        :class="{ editor_warning: v$.content.$error }"
        channel-type="Context::Default"
        enable-variables
        :enable-canned-responses="false"
        :placeholder="t('CANNED_MGMT.EDIT.FORM.CONTENT.PLACEHOLDER')"
        @blur="v$.content.$touch"
      />
    </div>
  </Dialog>
</template>
