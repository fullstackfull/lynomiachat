<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';

const props = defineProps({
  responseContent: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isCreating = ref(false);

const shortCode = ref('');
const content = ref(props.responseContent || '');

const v$ = useVuelidate(
  {
    shortCode: { required, minLength: minLength(2) },
    content: { required },
  },
  { shortCode, content }
);

const isInvalid = computed(
  () => v$.value.shortCode.$invalid || v$.value.content.$invalid
);

// A `Dialog` held by a ref stays mounted, where the old modal built a fresh component on every open.
// So the form is cleared here rather than relying on that.
const open = () => {
  shortCode.value = '';
  content.value = props.responseContent || '';
  v$.value.$reset();
  dialogRef.value?.open();
};

const handleClose = () => emit('close');

const addCannedResponse = async () => {
  if (isInvalid.value) return;
  isCreating.value = true;
  try {
    await store.dispatch('createCannedResponse', {
      short_code: shortCode.value,
      content: content.value,
    });
    useAlert(t('CANNED_MGMT.ADD.API.SUCCESS_MESSAGE'));
    dialogRef.value?.close();
  } catch (error) {
    useAlert(error?.message || t('CANNED_MGMT.ADD.API.ERROR_MESSAGE'));
  } finally {
    isCreating.value = false;
  }
};

defineExpose({ open, dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="xl"
    :title="t('CANNED_MGMT.ADD.TITLE')"
    :description="t('CANNED_MGMT.ADD.DESC')"
    :confirm-button-label="t('CANNED_MGMT.ADD.FORM.SUBMIT')"
    :cancel-button-label="t('CANNED_MGMT.ADD.CANCEL_BUTTON_TEXT')"
    :is-loading="isCreating"
    :disable-confirm-button="isInvalid || isCreating"
    @confirm="addCannedResponse"
    @close="handleClose"
  >
    <Input
      v-model="shortCode"
      :label="t('CANNED_MGMT.ADD.FORM.SHORT_CODE.LABEL')"
      :placeholder="t('CANNED_MGMT.ADD.FORM.SHORT_CODE.PLACEHOLDER')"
      @blur="v$.shortCode.$touch"
    />

    <div class="flex flex-col gap-1">
      <label
        for="canned-add-content"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ t('CANNED_MGMT.ADD.FORM.CONTENT.LABEL') }}
      </label>
      <!-- The editor's own menubar and body height used to be set from a scoped SCSS block reaching
        in with `:deep()`. Arbitrary variants do the same job as utilities, which is what this
        codebase asks for, and they travel with the element instead of a stylesheet. -->
      <WootMessageEditor
        id="canned-add-content"
        v-model="content"
        class="message-editor [&>div]:px-1 [&_.ProseMirror-menubar]:!hidden [&_.ProseMirror-woot-style]:min-h-[12.5rem]"
        :class="{ editor_warning: v$.content.$error }"
        channel-type="Context::Default"
        enable-variables
        :enable-canned-responses="false"
        :placeholder="t('CANNED_MGMT.ADD.FORM.CONTENT.PLACEHOLDER')"
        @blur="v$.content.$touch"
      />
    </div>
  </Dialog>
</template>
