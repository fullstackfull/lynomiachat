<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import CommerceAPI from 'dashboard/api/commerce';
import StoreDialog from './StoreDialog.vue';
import ProviderPicker from './ProviderPicker.vue';
import SallaConnectDialog from './SallaConnectDialog.vue';
import ZidConnectDialog from './ZidConnectDialog.vue';
import { relativeTime } from 'dashboard/components/widgets/conversation/commerce/commerceHelper';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const { apiErrorMessage, errorMessage, providerName, storeStatus } =
  useCommerceLabels();

// Providers whose credentials are API keys an administrator enters here. Salla and Zid stores get their tokens from
// the provider's app authorization instead, so they have no keys to replace.
const KEY_PROVIDERS = ['woocommerce'];
// Providers re-authorized from here (Zid's OAuth). A Salla store is re-authorized from the Salla dashboard.
const REAUTHORIZED_HERE = ['zid'];

const STATUS_DOT = {
  active: 'bg-n-teal-9',
  disabled: 'bg-n-slate-9',
  needs_reauth: 'bg-n-amber-9',
  disconnected: 'bg-n-ruby-9',
};

const stores = ref([]);
const providers = ref([]);
const isLoading = ref(true);
const showPicker = ref(false);
const showSallaDialog = ref(false);
const showZidDialog = ref(false);
const showStoreDialog = ref(false);
const rotatingStore = ref(null);
const disconnectingStore = ref(null);
const disconnectDialogRef = ref(null);
const busyStoreId = ref(null);

const fetchStores = async () => {
  try {
    const response = await CommerceAPI.get();
    stores.value = response.data.payload;
    providers.value = response.data.providers;
  } catch (error) {
    useAlert(apiErrorMessage(error));
  } finally {
    isLoading.value = false;
  }
};

const replaceStore = store => {
  stores.value = stores.value.map(existing =>
    existing.id === store.id ? store : existing
  );
};

const usesKeys = store => KEY_PROVIDERS.includes(store.provider);

const canReconnect = store =>
  store.provider_enabled &&
  (store.status === 'disconnected' ||
    (store.status === 'needs_reauth' &&
      REAUTHORIZED_HERE.includes(store.provider)));

// Hints and texts of the app-authorized providers (COMMERCE.SETTINGS.SALLA / ZID).
const providerText = (store, key) =>
  t(`COMMERCE.SETTINGS.${store.provider.toUpperCase()}.${key}`);

const disconnectDescription = store => {
  if (usesKeys(store))
    return t('COMMERCE.SETTINGS.DISCONNECT_CONFIRM.DESCRIPTION');
  if (store.provider === 'salla')
    return t('COMMERCE.SETTINGS.DISCONNECT_CONFIRM.DESCRIPTION_APP');
  return providerText(store, 'DISCONNECT_DESCRIPTION');
};

const openKeysDialog = () => {
  rotatingStore.value = null;
  showStoreDialog.value = true;
};

const openAddStore = () => {
  if (providers.value.length > 1) {
    showPicker.value = true;
  } else {
    openKeysDialog();
  }
};

const openConnect = provider => {
  if (provider === 'salla') showSallaDialog.value = true;
  else if (provider === 'zid') showZidDialog.value = true;
  else openKeysDialog();
};

const onProviderSelected = provider => {
  showPicker.value = false;
  openConnect(provider);
};

// Zid's authorization comes back here with `zid=connected` or `zid_error=<code>`.
const showZidResult = () => {
  const { zid, zid_error: code, ...query } = route.query;
  if (!zid && !code) return;

  useAlert(code ? errorMessage(code) : t('COMMERCE.SETTINGS.CONNECTED'));
  router.replace({ query });
};

const onSallaConnected = async () => {
  showSallaDialog.value = false;
  useAlert(t('COMMERCE.SETTINGS.CONNECTED'));
  await fetchStores();
};

const openReplaceKeys = store => {
  rotatingStore.value = store;
  showStoreDialog.value = true;
};

const onStoreSaved = store => {
  showStoreDialog.value = false;
  if (stores.value.some(existing => existing.id === store.id)) {
    replaceStore(store);
    useAlert(t('COMMERCE.SETTINGS.UPDATED'));
  } else {
    stores.value = [...stores.value, store];
    useAlert(t('COMMERCE.SETTINGS.CONNECTED'));
  }
};

const setStatus = async (store, status) => {
  busyStoreId.value = store.id;
  try {
    const response = await CommerceAPI.update(store.id, { status });
    replaceStore(response.data);
    useAlert(t('COMMERCE.SETTINGS.UPDATED'));
  } catch (error) {
    useAlert(apiErrorMessage(error));
  } finally {
    busyStoreId.value = null;
  }
};

const askDisconnect = store => {
  disconnectingStore.value = store;
  disconnectDialogRef.value?.open();
};

const disconnect = async () => {
  const store = disconnectingStore.value;
  busyStoreId.value = store.id;
  try {
    await CommerceAPI.delete(store.id);
    replaceStore({ ...store, status: 'disconnected' });
    useAlert(t('COMMERCE.SETTINGS.DISCONNECTED'));
  } catch (error) {
    useAlert(apiErrorMessage(error));
  } finally {
    busyStoreId.value = null;
    disconnectDialogRef.value?.close();
  }
};

onMounted(() => {
  showZidResult();
  fetchStores();
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('COMMERCE.SETTINGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('COMMERCE.SETTINGS.HEADER')"
        :description="t('COMMERCE.SETTINGS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="t('COMMERCE.SETTINGS.ADD_STORE')"
            @click="openAddStore"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div
        v-if="!stores.length"
        class="flex min-h-60 flex-col items-center justify-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 px-6 py-16 text-center"
      >
        <span
          class="flex size-12 items-center justify-center rounded-full bg-n-alpha-2"
        >
          <Icon icon="i-lucide-store" class="size-5 text-n-slate-11" />
        </span>
        <p class="text-body-main text-n-slate-11">
          {{ t('COMMERCE.SETTINGS.EMPTY') }}
        </p>
      </div>

      <div v-else class="divide-y divide-n-weak border-t border-n-weak">
        <div
          v-for="store in stores"
          :key="store.id"
          class="flex flex-wrap items-center justify-between gap-4 py-4"
          data-test-id="commerce-store-row"
        >
          <div class="flex min-w-0 items-center gap-3">
            <span
              class="grid size-10 shrink-0 place-items-center rounded-xl border border-n-strong bg-n-alpha-3"
            >
              <Icon icon="i-lucide-shopping-bag" class="size-4" />
            </span>
            <div class="flex min-w-0 flex-col gap-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="truncate text-heading-3 text-n-slate-12">
                  {{ store.name }}
                </span>
                <span
                  class="flex items-center gap-1.5 text-label-small text-n-slate-11"
                >
                  <span
                    class="size-2 rounded-full"
                    :class="STATUS_DOT[store.status]"
                  />
                  {{ storeStatus(store.status) }}
                </span>
              </div>
              <span
                class="flex min-w-0 gap-2 text-body-main text-n-slate-11"
                dir="ltr"
              >
                <span>{{ providerName(store.provider) }}</span>
                <span class="truncate">{{ store.base_url }}</span>
              </span>
              <span
                v-if="store.verified_at"
                class="text-label-small text-n-slate-11"
              >
                {{
                  t('COMMERCE.SETTINGS.VERIFIED', {
                    time: relativeTime(store.verified_at, locale),
                  })
                }}
              </span>
              <span
                v-if="!store.provider_enabled"
                class="text-label-small text-n-amber-11"
                data-test-id="commerce-store-hint"
              >
                {{ providerText(store, 'PROVIDER_OFF') }}
              </span>
              <span
                v-else-if="!usesKeys(store) && store.status === 'needs_reauth'"
                class="text-label-small text-n-amber-11"
                data-test-id="commerce-store-hint"
              >
                {{ providerText(store, 'REAUTH_HINT') }}
              </span>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button
              v-if="store.status === 'active'"
              :label="t('COMMERCE.SETTINGS.ACTIONS.DISABLE')"
              variant="faded"
              color="slate"
              size="sm"
              :is-loading="busyStoreId === store.id"
              @click="setStatus(store, 'disabled')"
            />
            <Button
              v-if="store.status === 'disabled' && store.provider_enabled"
              :label="t('COMMERCE.SETTINGS.ACTIONS.ENABLE')"
              variant="faded"
              size="sm"
              :is-loading="busyStoreId === store.id"
              @click="setStatus(store, 'active')"
            />
            <Button
              v-if="usesKeys(store)"
              :label="
                store.status === 'disconnected'
                  ? t('COMMERCE.SETTINGS.ACTIONS.RECONNECT')
                  : t('COMMERCE.SETTINGS.ACTIONS.REPLACE_KEYS')
              "
              variant="faded"
              color="slate"
              size="sm"
              @click="openReplaceKeys(store)"
            />
            <Button
              v-else-if="canReconnect(store)"
              :label="t('COMMERCE.SETTINGS.ACTIONS.RECONNECT')"
              variant="faded"
              color="slate"
              size="sm"
              @click="openConnect(store.provider)"
            />
            <Button
              v-if="store.status !== 'disconnected'"
              :label="t('COMMERCE.SETTINGS.ACTIONS.DISCONNECT')"
              variant="faded"
              color="ruby"
              size="sm"
              @click="askDisconnect(store)"
            />
          </div>
        </div>
      </div>

      <ProviderPicker
        :show="showPicker"
        :providers="providers"
        @close="showPicker = false"
        @select="onProviderSelected"
      />
      <SallaConnectDialog
        :show="showSallaDialog"
        @close="showSallaDialog = false"
        @connected="onSallaConnected"
      />
      <ZidConnectDialog :show="showZidDialog" @close="showZidDialog = false" />
      <StoreDialog
        :show="showStoreDialog"
        :store="rotatingStore"
        @close="showStoreDialog = false"
        @saved="onStoreSaved"
      />
      <Dialog
        ref="disconnectDialogRef"
        type="alert"
        :title="
          t('COMMERCE.SETTINGS.DISCONNECT_CONFIRM.TITLE', {
            name: disconnectingStore?.name,
          })
        "
        :description="
          disconnectingStore ? disconnectDescription(disconnectingStore) : ''
        "
        :confirm-button-label="
          t('COMMERCE.SETTINGS.DISCONNECT_CONFIRM.CONFIRM')
        "
        :is-loading="!!busyStoreId"
        @confirm="disconnect"
      />
    </template>
  </SettingsLayout>
</template>
