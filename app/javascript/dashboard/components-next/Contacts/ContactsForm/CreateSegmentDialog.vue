<script setup>
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const emit = defineEmits(['create']);

const FILTER_TYPE_CONTACT = 1;

const { t } = useI18n();
const { isAdmin } = useAdmin();

const uiFlags = useMapGetter('customViews/getUIFlags');
const isCreating = computed(() => uiFlags.value.isCreating);

const dialogRef = ref(null);

const state = reactive({
  name: '',
  shared: false,
});

const validationRules = {
  name: { required },
};

const v$ = useVuelidate(validationRules, state);

const handleDialogConfirm = async () => {
  const isNameValid = await v$.value.$validate();
  if (!isNameValid) return;
  emit('create', {
    name: state.name,
    filter_type: FILTER_TYPE_CONTACT,
    // Lynomia shared audiences: account-level, usable by automation rules; administrators only.
    ...(state.shared && { shared: true }),
  });
  state.name = '';
  state.shared = false;
  v$.value.$reset();
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.TITLE')"
    :confirm-button-label="
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.CONFIRM')
    "
    :is-loading="isCreating"
    :disable-confirm-button="isCreating"
    @confirm="handleDialogConfirm"
  >
    <Input
      v-model="state.name"
      :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.LABEL')"
      :placeholder="
        t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.PLACEHOLDER')
      "
      :message="
        v$.name.$error
          ? t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.ERROR')
          : ''
      "
      :message-type="v$.name.$error ? 'error' : 'info'"
    />
    <label
      v-if="isAdmin"
      class="flex items-start gap-2 mt-4 cursor-pointer"
      data-test-id="share-audience"
    >
      <Checkbox v-model="state.shared" class="mt-0.5" />
      <span class="flex flex-col gap-1">
        <span class="text-label-small text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.SHARE') }}
        </span>
        <span class="text-label-small text-n-slate-11">
          {{
            t(
              'CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.SHARE_HINT'
            )
          }}
        </span>
      </span>
    </label>
  </Dialog>
</template>
