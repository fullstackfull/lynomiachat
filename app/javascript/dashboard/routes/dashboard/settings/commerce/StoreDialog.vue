<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// Connects a WooCommerce store, or replaces the API keys of `store`. Keys are write-only: they are sent once and the
// fields are cleared whenever the dialog closes.
const props = defineProps({
  show: { type: Boolean, default: false },
  store: { type: Object, default: null },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();
const { apiErrorMessage } = useCommerceLabels();
const dialogRef = ref(null);
const baseUrl = ref('');
const name = ref('');
const consumerKey = ref('');
const consumerSecret = ref('');
const errorMessage = ref('');
const isSaving = ref(false);

const isRotation = computed(() => !!props.store);
const canSave = computed(
  () =>
    consumerKey.value.trim() &&
    consumerSecret.value.trim() &&
    (isRotation.value || baseUrl.value.trim())
);

const save = async () => {
  isSaving.value = true;
  errorMessage.value = '';
  const keys = {
    consumer_key: consumerKey.value.trim(),
    consumer_secret: consumerSecret.value.trim(),
  };
  try {
    const response = isRotation.value
      ? await CommerceAPI.update(props.store.id, keys)
      : await CommerceAPI.create({
          provider: 'woocommerce',
          base_url: baseUrl.value.trim(),
          name: name.value.trim(),
          ...keys,
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
    consumerKey.value = '';
    consumerSecret.value = '';
    errorMessage.value = '';
  }
);
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isRotation
        ? t('COMMERCE.SETTINGS.FORM.ROTATE_TITLE')
        : t('COMMERCE.SETTINGS.FORM.TITLE')
    "
    :description="t('COMMERCE.SETTINGS.FORM.READ_ONLY_HINT')"
    :confirm-button-label="
      isRotation
        ? t('COMMERCE.SETTINGS.FORM.SAVE')
        : t('COMMERCE.SETTINGS.FORM.CONNECT')
    "
    :cancel-button-label="t('COMMERCE.SETTINGS.FORM.CANCEL')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    width="md"
    @confirm="save"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
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
        v-model="consumerKey"
        type="password"
        dir="ltr"
        autocomplete="off"
        :label="t('COMMERCE.SETTINGS.FORM.CONSUMER_KEY')"
        placeholder="ck_…"
      />
      <Input
        v-model="consumerSecret"
        type="password"
        dir="ltr"
        autocomplete="off"
        :label="t('COMMERCE.SETTINGS.FORM.CONSUMER_SECRET')"
        placeholder="cs_…"
        :message="t('COMMERCE.SETTINGS.FORM.KEYS_HINT')"
      />
      <p
        v-if="errorMessage"
        class="rounded-lg bg-n-ruby-2 px-3 py-2 text-body-main text-n-ruby-11"
        data-test-id="commerce-store-error"
      >
        {{ errorMessage }}
      </p>
    </div>
  </Dialog>
</template>
