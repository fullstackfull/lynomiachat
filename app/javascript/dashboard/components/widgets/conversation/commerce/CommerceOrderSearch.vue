<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CommerceAPI from 'dashboard/api/commerce';
import CommerceOrderItem from './CommerceOrderItem.vue';
import { useCommerceLabels } from './useCommerceLabels';

// Order search by the number a customer quotes (docs/commerce/25-customer-360.md §order search), in one store or, without
// a store, in every store. A found order can belong to any customer of the store, so it is shown without sending actions.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  storeId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const { apiErrorMessage } = useCommerceLabels();

const DEFAULT_RETRY_SECONDS = 60;

const isOpen = ref(false);
const number = ref('');
const result = ref(null);
const error = ref('');
const isSearching = ref(false);

const notices = computed(() =>
  (result.value?.stores || [])
    .filter(entry => entry.state !== 'searched')
    .map(entry =>
      entry.state === 'unsupported'
        ? t('COMMERCE.ORDER_SEARCH.UNSUPPORTED', { store: entry.store.name })
        : t('COMMERCE.ORDER_SEARCH.UNAVAILABLE', { store: entry.store.name })
    )
);

const search = async () => {
  const value = number.value.trim();
  if (!value) return;
  isSearching.value = true;
  error.value = '';
  result.value = null;
  try {
    const response = await CommerceAPI.searchOrders(
      props.conversationId,
      value,
      props.storeId
    );
    result.value = response.data;
  } catch (e) {
    const status = e?.response?.status;
    if (status === 422) {
      error.value = t('COMMERCE.ORDER_SEARCH.INVALID');
    } else if (status === 429) {
      error.value = t('COMMERCE.ORDER_SEARCH.RATE_LIMITED', {
        seconds: e.response.data?.error?.retry_after ?? DEFAULT_RETRY_SECONDS,
      });
    } else {
      error.value = apiErrorMessage(e);
    }
  } finally {
    isSearching.value = false;
  }
};
</script>

<template>
  <section class="flex flex-col gap-2" data-test-id="commerce-order-search">
    <button
      type="button"
      class="flex items-center justify-between py-1 text-start text-label-small text-n-slate-11"
      :aria-expanded="isOpen"
      data-test-id="commerce-order-search-toggle"
      @click="isOpen = !isOpen"
    >
      <span>{{ t('COMMERCE.ORDER_SEARCH.TOGGLE') }}</span>
      <span
        :class="
          isOpen ? 'i-lucide-chevron-up size-4' : 'i-lucide-chevron-down size-4'
        "
      />
    </button>
    <template v-if="isOpen">
      <div class="flex gap-2">
        <Input
          v-model="number"
          class="flex-1"
          size="sm"
          inputmode="numeric"
          :placeholder="t('COMMERCE.ORDER_SEARCH.PLACEHOLDER')"
          data-test-id="commerce-order-search-input"
          @enter="search"
        />
        <Button
          :label="t('COMMERCE.ORDER_SEARCH.SEARCH')"
          size="sm"
          :is-loading="isSearching"
          :disabled="!number.trim()"
          data-test-id="commerce-order-search-submit"
          @click="search"
        />
      </div>
      <span class="text-label-small text-n-slate-11">
        {{ t('COMMERCE.ORDER_SEARCH.HINT') }}
      </span>
      <p v-if="error" class="text-body-main text-n-ruby-11">{{ error }}</p>
      <template v-if="result">
        <p
          v-for="notice in notices"
          :key="notice"
          class="text-label-small text-n-amber-11"
          data-test-id="commerce-order-search-notice"
        >
          {{ notice }}
        </p>
        <p
          v-if="!result.orders.length"
          class="text-body-main text-n-slate-11"
          data-test-id="commerce-order-search-empty"
        >
          {{ t('COMMERCE.ORDER_SEARCH.NO_RESULTS') }}
        </p>
        <CommerceOrderItem
          v-for="order in result.orders"
          :key="`${order.store.id}-${order.external_order_id}`"
          :order="order"
          :store="order.store"
          :can-send="false"
        />
      </template>
    </template>
  </section>
</template>
