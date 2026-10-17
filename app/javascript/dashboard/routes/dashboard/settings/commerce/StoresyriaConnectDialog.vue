<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DocsLink from 'dashboard/components-next/docs-link/DocsLink.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// Connects a Store Syria store, or replaces the integration token of `store`. The token is issued per store in Store
// Syria and names the store it was issued for, so nothing entered here says which store will be read; the connection is
// refused unless the store answers with the identity this connection claims. There is no access choice because the
// contract is read-only. Tokens are write-only: they are sent once and the field is cleared whenever the dialog closes.
const props = defineProps({
  show: { type: Boolean, default: false },
  store: { type: Object, default: null },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();
const { installationName } = useBranding();
const { apiErrorMessage } = useCommerceLabels();
const dialogRef = ref(null);
const baseUrl = ref('');
const name = ref('');
const token = ref('');
const errorMessage = ref('');
const isSaving = ref(false);

const isRotation = computed(() => !!props.store);
const canSave = computed(
  () => token.value.trim() && (isRotation.value || baseUrl.value.trim())
);

const save = async () => {
  isSaving.value = true;
  errorMessage.value = '';
  const credentials = { commerce_token: token.value.trim() };
  try {
    const response = isRotation.value
      ? await CommerceAPI.update(props.store.id, credentials)
      : await CommerceAPI.create({
          provider: 'storesyria',
          base_url: baseUrl.value.trim(),
          name: name.value.trim(),
          ...credentials,
        });
    emit('saved', response.data);
  } catch (error) {
    errorMessage.value = apiErrorMessage(error);
  } finally {
    isSaving.value = false;
  }
};

watch(
  () => props.show,
  show => {
    if (show) {
      dialogRef.value?.open();
      return;
    }
    dialogRef.value?.close();
    baseUrl.value = '';
    name.value = '';
    token.value = '';
    errorMessage.value = '';
  }
);
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isRotation
        ? t('COMMERCE.SETTINGS.STORESYRIA.ROTATE_TITLE')
        : t('COMMERCE.SETTINGS.STORESYRIA.TITLE')
    "
    :description="
      t('COMMERCE.SETTINGS.STORESYRIA.DESCRIPTION', { installationName })
    "
    :confirm-button-label="
      isRotation
        ? t('COMMERCE.SETTINGS.STORESYRIA.SAVE')
        : t('COMMERCE.SETTINGS.STORESYRIA.CONNECT')
    "
    :cancel-button-label="t('COMMERCE.SETTINGS.FORM.CANCEL')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    width="md"
    overflow-y-auto
    @confirm="save"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <div
        class="flex flex-col gap-1 rounded-xl bg-n-alpha-2 px-3 py-2"
        data-test-id="storesyria-steps"
      >
        <span class="text-body-main font-medium text-n-slate-12">
          {{ t('COMMERCE.SETTINGS.STORESYRIA.STEPS') }}
        </span>
        <ol class="ms-4 list-decimal text-body-main text-n-slate-11">
          <li>{{ t('COMMERCE.SETTINGS.STORESYRIA.STEP_1') }}</li>
          <li>{{ t('COMMERCE.SETTINGS.STORESYRIA.STEP_2') }}</li>
          <li>{{ t('COMMERCE.SETTINGS.STORESYRIA.STEP_3') }}</li>
        </ol>
      </div>
      <template v-if="!isRotation">
        <Input
          v-model="baseUrl"
          dir="ltr"
          autocomplete="off"
          :label="t('COMMERCE.SETTINGS.FORM.STORE_URL')"
          :placeholder="t('COMMERCE.SETTINGS.FORM.STORE_URL_PLACEHOLDER')"
        />
        <Input
          v-model="name"
          :label="t('COMMERCE.SETTINGS.FORM.NAME')"
          :placeholder="t('COMMERCE.SETTINGS.FORM.NAME_PLACEHOLDER')"
        />
      </template>
      <Input
        v-model="token"
        type="password"
        dir="ltr"
        autocomplete="off"
        :label="t('COMMERCE.SETTINGS.STORESYRIA.TOKEN')"
        placeholder="lsc_…"
        :message="t('COMMERCE.SETTINGS.STORESYRIA.TOKEN_HINT')"
      />
      <p
        v-if="errorMessage"
        class="rounded-lg bg-n-ruby-2 px-3 py-2 text-body-main text-n-ruby-11"
        data-test-id="storesyria-connection-error"
      >
        {{ errorMessage }}
      </p>
    </div>
    <!-- The set-up guide for this platform, at the step where the merchant is doing the set-up. -->
    <DocsLink
      article-key="commerceStoresyria"
      :label="t('COMMERCE.SETTINGS.STORESYRIA.DOCS')"
    />
  </Dialog>
</template>
