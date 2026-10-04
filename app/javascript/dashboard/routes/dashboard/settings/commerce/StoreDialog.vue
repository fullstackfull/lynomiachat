<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// Connects a WooCommerce store, or replaces the API keys of `store`. The administrator first chooses what Lynomia may do
// (Read, or Read/Write for live updates and order actions) and gets the steps to create a key with that permission. The
// choice only guides: what the key can really do is what WooCommerce answers once it is saved (settings show it per
// store). Keys are write-only: they are sent once and the fields are cleared whenever the dialog closes.
const props = defineProps({
  show: { type: Boolean, default: false },
  store: { type: Object, default: null },
});

const emit = defineEmits(['close', 'saved']);

const ACCESS = {
  READ: 'read',
  READ_WRITE: 'read_write',
};

const { t } = useI18n();
const { installationName } = useBranding();
const { apiErrorMessage } = useCommerceLabels();
const dialogRef = ref(null);
const baseUrl = ref('');
const name = ref('');
const consumerKey = ref('');
const consumerSecret = ref('');
const errorMessage = ref('');
const isSaving = ref(false);
const access = ref(ACCESS.READ_WRITE);

const accessOptions = computed(() => [
  {
    value: ACCESS.READ_WRITE,
    label: t('COMMERCE.SETTINGS.FORM.ACCESS_READ_WRITE'),
    hint: t('COMMERCE.SETTINGS.FORM.ACCESS_READ_WRITE_HINT', {
      installationName: installationName.value,
    }),
  },
  {
    value: ACCESS.READ,
    label: t('COMMERCE.SETTINGS.FORM.ACCESS_READ'),
    hint: t('COMMERCE.SETTINGS.FORM.ACCESS_READ_HINT'),
  },
]);
// WooCommerce's own name for the permission, as its key form shows it.
const permission = computed(() =>
  access.value === ACCESS.READ
    ? t('COMMERCE.SETTINGS.FORM.PERMISSION_READ')
    : t('COMMERCE.SETTINGS.FORM.PERMISSION_READ_WRITE')
);

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
    access.value = ACCESS.READ_WRITE;
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
    :description="t('COMMERCE.SETTINGS.FORM.DESCRIPTION', { installationName })"
    :confirm-button-label="
      isRotation
        ? t('COMMERCE.SETTINGS.FORM.SAVE')
        : t('COMMERCE.SETTINGS.FORM.CONNECT')
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
      <fieldset class="flex flex-col gap-2">
        <legend class="mb-2 text-heading-3 text-n-slate-12">
          {{ t('COMMERCE.SETTINGS.FORM.ACCESS', { installationName }) }}
        </legend>
        <button
          v-for="option in accessOptions"
          :key="option.value"
          type="button"
          class="flex flex-col gap-0.5 rounded-xl border border-solid p-3 text-start"
          :class="
            access === option.value
              ? 'border-n-brand bg-n-alpha-2'
              : 'border-n-weak hover:border-n-strong'
          "
          :aria-pressed="access === option.value"
          :data-test-id="`commerce-store-access-${option.value}`"
          @click="access = option.value"
        >
          <span class="text-body-main font-medium text-n-slate-12">
            {{ option.label }}
          </span>
          <span class="text-label-small text-n-slate-11">
            {{ option.hint }}
          </span>
        </button>
      </fieldset>
      <div
        class="flex flex-col gap-1 rounded-xl bg-n-alpha-2 px-3 py-2"
        data-test-id="commerce-store-steps"
      >
        <span class="text-body-main font-medium text-n-slate-12">
          {{ t('COMMERCE.SETTINGS.FORM.STEPS') }}
        </span>
        <ol class="ms-4 list-decimal text-body-main text-n-slate-11">
          <li>{{ t('COMMERCE.SETTINGS.FORM.STEP_1') }}</li>
          <li>{{ t('COMMERCE.SETTINGS.FORM.STEP_2', { permission }) }}</li>
          <li>{{ t('COMMERCE.SETTINGS.FORM.STEP_3') }}</li>
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
