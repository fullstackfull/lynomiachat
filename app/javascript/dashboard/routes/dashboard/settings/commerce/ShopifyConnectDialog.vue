<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { safeHttpsUrl } from 'dashboard/components/widgets/conversation/commerce/commerceHelper';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// Connects or re-authorizes a Shopify store through the Lynomia Commerce Shopify app
// (docs/commerce/18-shopify-oauth-and-tokens.md): the administrator names the shop's myshopify.com domain, the browser
// goes to the shop to authorize the app and comes back to Settings → Commerce. No token ever reaches the browser.
const props = defineProps({
  show: { type: Boolean, default: false },
  // The domain of a store being reconnected.
  shop: { type: String, default: '' },
  // Reconnecting for order actions: Shopify also asks the merchant for write access to orders.
  orderActions: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const { installationName } = useBranding();
const { apiErrorMessage } = useCommerceLabels();
const dialogRef = ref(null);
const shopDomain = ref('');
const errorMessage = ref('');
const isStarting = ref(false);

const connect = async () => {
  isStarting.value = true;
  errorMessage.value = '';
  try {
    const response = await CommerceAPI.createShopifyConnection(
      shopDomain.value.trim(),
      { orderActions: props.orderActions }
    );
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
      shopDomain.value = props.shop;
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
    :title="
      orderActions
        ? t('COMMERCE.SETTINGS.SHOPIFY.ACTIONS_TITLE')
        : t('COMMERCE.SETTINGS.SHOPIFY.TITLE')
    "
    :description="
      orderActions
        ? t('COMMERCE.SETTINGS.SHOPIFY.ACTIONS_DESCRIPTION', {
            installationName,
          })
        : t('COMMERCE.SETTINGS.SHOPIFY.DESCRIPTION', { installationName })
    "
    :show-confirm-button="false"
    :cancel-button-label="t('COMMERCE.SETTINGS.FORM.CANCEL')"
    width="md"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="shopDomain"
        dir="ltr"
        autocomplete="off"
        :label="t('COMMERCE.SETTINGS.SHOPIFY.SHOP_LABEL')"
        placeholder="your-store.myshopify.com"
        :message="t('COMMERCE.SETTINGS.SHOPIFY.SHOP_HINT')"
      />
      <p class="text-body-main text-n-slate-12">
        {{ t('COMMERCE.SETTINGS.SHOPIFY.STEPS', { installationName }) }}
      </p>
      <p
        v-if="errorMessage"
        class="rounded-lg bg-n-ruby-2 px-3 py-2 text-body-main text-n-ruby-11"
        data-test-id="shopify-connection-error"
      >
        {{ errorMessage }}
      </p>
      <Button
        :label="t('COMMERCE.SETTINGS.SHOPIFY.CONNECT')"
        icon="i-lucide-external-link"
        size="sm"
        :disabled="!shopDomain.trim()"
        :is-loading="isStarting"
        data-test-id="shopify-connect"
        @click="connect"
      />
    </div>
  </Dialog>
</template>
