<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CommerceAPI from 'dashboard/api/commerce';
import {
  formatAmount,
  relativeTime,
} from 'dashboard/components/widgets/conversation/commerce/commerceHelper';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// The recovery queue for administrators (docs/commerce/31-sales-recovery.md §queue): recent abandoned carts across the
// account's stores, linked contacts first. A list to act from: recovery messages are prepared in the contact's
// conversation, never sent from here.
const props = defineProps({
  stores: { type: Array, required: true },
});

const { t, locale } = useI18n();
const route = useRoute();
const { apiErrorMessage, providerName } = useCommerceLabels();

const filters = reactive({
  store_id: '',
  age: '7d',
  status: 'abandoned',
  linked: '',
});
const rows = ref([]);
const isLoading = ref(false);
const loadError = ref('');

const storeOptions = computed(() => [
  { value: '', label: t('COMMERCE.SETTINGS.CART_QUEUE.ALL_STORES') },
  ...props.stores.map(store => ({
    value: String(store.id),
    label: store.name,
  })),
]);
const ageOptions = computed(() => [
  { value: '24h', label: t('COMMERCE.SETTINGS.CART_QUEUE.AGE_24H') },
  { value: '7d', label: t('COMMERCE.SETTINGS.CART_QUEUE.AGE_7D') },
  { value: '30d', label: t('COMMERCE.SETTINGS.CART_QUEUE.AGE_30D') },
  { value: '', label: t('COMMERCE.SETTINGS.CART_QUEUE.ALL_AGES') },
]);
const statusOptions = computed(() => [
  {
    value: 'abandoned',
    label: t('COMMERCE.SETTINGS.CART_QUEUE.STATUS_ABANDONED'),
  },
  {
    value: 'recovered',
    label: t('COMMERCE.SETTINGS.CART_QUEUE.STATUS_RECOVERED'),
  },
  { value: '', label: t('COMMERCE.SETTINGS.CART_QUEUE.ALL_STATUSES') },
]);
const linkedOptions = computed(() => [
  { value: '', label: t('COMMERCE.SETTINGS.CART_QUEUE.ALL_CONTACTS') },
  { value: 'true', label: t('COMMERCE.SETTINGS.CART_QUEUE.LINKED') },
  { value: 'false', label: t('COMMERCE.SETTINGS.CART_QUEUE.UNLINKED') },
]);

const contactPath = contact =>
  `/app/accounts/${route.params.accountId}/contacts/${contact.id}`;

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const params = Object.fromEntries(
      Object.entries(filters).filter(([, value]) => value !== '')
    );
    const response = await CommerceAPI.getCartQueue(params);
    rows.value = response.data.payload;
  } catch (error) {
    loadError.value = apiErrorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

watch(filters, load);
onMounted(load);
</script>

<template>
  <section class="flex flex-col gap-3" data-test-id="commerce-cart-queue">
    <div class="flex flex-col gap-1">
      <h3 class="text-heading-2 text-n-slate-12">
        {{ t('COMMERCE.SETTINGS.CART_QUEUE.TITLE') }}
      </h3>
      <p class="text-body-main text-n-slate-11">
        {{ t('COMMERCE.SETTINGS.CART_QUEUE.DESCRIPTION') }}
      </p>
    </div>
    <div class="flex flex-wrap gap-2">
      <Select v-model="filters.store_id" :options="storeOptions" />
      <Select v-model="filters.age" :options="ageOptions" />
      <Select v-model="filters.status" :options="statusOptions" />
      <Select v-model="filters.linked" :options="linkedOptions" />
    </div>
    <div v-if="isLoading" class="flex items-center gap-2 text-n-slate-11">
      <Spinner class="text-n-brand" />
      <span class="text-body-main">
        {{ t('COMMERCE.SETTINGS.CART_QUEUE.LOADING') }}
      </span>
    </div>
    <p v-else-if="loadError" class="text-body-main text-n-ruby-11">
      {{ loadError }}
    </p>
    <p v-else-if="!rows.length" class="text-body-main text-n-slate-11">
      {{ t('COMMERCE.SETTINGS.CART_QUEUE.EMPTY') }}
    </p>
    <ul v-else class="divide-y divide-n-weak border-y border-n-weak">
      <li
        v-for="row in rows"
        :key="`${row.store.id}-${row.external_cart_id}`"
        class="flex flex-wrap items-center justify-between gap-3 py-3"
        data-test-id="commerce-cart-queue-row"
      >
        <div class="flex min-w-0 flex-col gap-0.5">
          <span class="text-body-main text-n-slate-12">
            {{
              t('COMMERCE.CARTS.TOTAL_AND_ITEMS', {
                total: formatAmount(row.total, row.currency, locale),
                items: t(
                  'COMMERCE.CARTS.ITEMS',
                  { count: row.items_count },
                  row.items_count
                ),
              })
            }}
          </span>
          <span class="text-label-small text-n-slate-11">
            {{
              t('COMMERCE.CARTS.STORE_AND_AGE', {
                store: row.store.name,
                provider: providerName(row.store.provider),
                time: relativeTime(row.updated_at || row.created_at, locale),
              })
            }}
          </span>
          <span
            v-if="row.recovery?.sent_at"
            class="text-label-small text-n-teal-11"
          >
            {{
              t('COMMERCE.CARTS.SENT', {
                time: relativeTime(
                  new Date(row.recovery.sent_at * 1000).toISOString(),
                  locale
                ),
              })
            }}
          </span>
        </div>
        <router-link
          v-if="row.contact"
          :to="contactPath(row.contact)"
          class="text-label-small text-n-blue-11 hover:underline"
        >
          {{
            row.contact.name || t('COMMERCE.SETTINGS.CART_QUEUE.OPEN_CONTACT')
          }}
        </router-link>
        <span v-else class="text-label-small text-n-slate-11">
          {{ t('COMMERCE.SETTINGS.CART_QUEUE.UNLINKED') }}
        </span>
      </li>
    </ul>
  </section>
</template>
