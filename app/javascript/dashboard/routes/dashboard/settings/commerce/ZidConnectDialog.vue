<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { safeHttpsUrl } from 'dashboard/components/widgets/conversation/commerce/commerceHelper';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// Connects or re-authorizes a Zid store (docs/commerce/14-zid-oauth-and-tokens.md): the browser goes to Zid to authorize
// the Lynomia app and comes back to Settings → Commerce. No token ever reaches the browser.
const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const { apiErrorMessage } = useCommerceLabels();
const dialogRef = ref(null);
const errorMessage = ref('');
const isStarting = ref(false);

const connect = async () => {
  isStarting.value = true;
  errorMessage.value = '';
  try {
    const response = await CommerceAPI.createZidConnection();
    const url = safeHttpsUrl(response.data.authorize_url);
    if (url) window.location.assign(url);
  } catch (error) {
    errorMessage.value = apiErrorMessage(error);
    isStarting.value = false;
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
    errorMessage.value = '';
    isStarting.value = false;
  }
);
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('COMMERCE.SETTINGS.ZID.TITLE')"
    :description="t('COMMERCE.SETTINGS.ZID.DESCRIPTION')"
    :show-confirm-button="false"
    :cancel-button-label="t('COMMERCE.SETTINGS.FORM.CANCEL')"
    width="md"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <p class="text-body-main text-n-slate-12">
        {{ t('COMMERCE.SETTINGS.ZID.STEPS') }}
      </p>
      <p
        v-if="errorMessage"
        class="rounded-lg bg-n-ruby-2 px-3 py-2 text-body-main text-n-ruby-11"
        data-test-id="zid-connection-error"
      >
        {{ errorMessage }}
      </p>
      <Button
        :label="t('COMMERCE.SETTINGS.ZID.CONNECT')"
        icon="i-lucide-external-link"
        size="sm"
        :is-loading="isStarting"
        data-test-id="zid-connect"
        @click="connect"
      />
    </div>
  </Dialog>
</template>
