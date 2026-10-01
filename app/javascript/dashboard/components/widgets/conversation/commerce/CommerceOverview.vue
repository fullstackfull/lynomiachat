<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CommerceOrderItem from './CommerceOrderItem.vue';
import { formatAmount, relativeTime } from './commerceHelper';
import { useCommerceLabels } from './useCommerceLabels';

// Customer 360 (docs/commerce/25-customer-360.md): the backend's aggregate of every store's view of the contact. Figures
// cover the orders the stores returned, so they are labelled as visible, not lifetime. Nothing here is provider-specific.
const props = defineProps({
  overview: { type: Object, required: true },
});
const emit = defineEmits(['openStore']);

const { t, locale } = useI18n();
const { providerName, matchSource, overviewState } = useCommerceLabels();

const showOrders = ref(true);
const showStores = ref(true);

const spend = computed(() =>
  props.overview.total_spend_visible.map(({ amount, currency }) =>
    formatAmount(amount, currency, locale.value)
  )
);
const lastPurchase = computed(() =>
  props.overview.last_order_at
    ? relativeTime(props.overview.last_order_at, locale.value)
    : t('COMMERCE.OVERVIEW.NO_ORDERS')
);
const isLinked = computed(() => props.overview.linked_stores_count > 0);

const ATTENTION_STATES = [
  'needs_reauth',
  'provider_unavailable',
  'unavailable',
];
const NOT_OPENABLE_STATES = ['needs_reauth', 'provider_unavailable'];

const identity = entry =>
  entry.link
    ? [
        entry.link.customer_type === 'guest'
          ? t('COMMERCE.PANEL.GUEST')
          : t('COMMERCE.PANEL.REGISTERED'),
        matchSource(entry.link.match_source),
      ].join(' · ')
    : '';

// Each store's own freshness: when its data was fetched, and whether it is an older copy kept during an outage.
const freshness = entry => {
  if (!entry.fetched_at) return '';
  const time = relativeTime(entry.fetched_at, locale.value);
  return entry.stale
    ? t('COMMERCE.OVERVIEW.STALE', { time })
    : t('COMMERCE.OVERVIEW.UPDATED', { time });
};
</script>

<template>
  <div class="flex flex-col gap-3" data-test-id="commerce-overview">
    <p
      v-if="overview.partial"
      class="rounded-lg bg-n-amber-2 px-3 py-2 text-body-main text-n-amber-11"
      data-test-id="commerce-overview-partial"
    >
      {{ t('COMMERCE.OVERVIEW.PARTIAL') }}
    </p>

    <dl class="grid grid-cols-2 gap-2">
      <div class="flex flex-col rounded-lg bg-n-alpha-1 px-3 py-2">
        <dt class="text-label-small text-n-slate-11">
          {{ t('COMMERCE.OVERVIEW.STORES') }}
        </dt>
        <dd class="text-body-main text-n-slate-12">
          {{
            t(
              'COMMERCE.OVERVIEW.STORES_VALUE',
              { count: overview.stores_count },
              overview.stores_count
            )
          }}
        </dd>
        <dd class="text-label-small text-n-slate-11">
          {{
            t(
              'COMMERCE.OVERVIEW.LINKED_VALUE',
              { count: overview.linked_stores_count },
              overview.linked_stores_count
            )
          }}
        </dd>
      </div>
      <div
        class="flex flex-col rounded-lg bg-n-alpha-1 px-3 py-2"
        :title="t('COMMERCE.OVERVIEW.ORDERS_HINT')"
      >
        <dt class="text-label-small text-n-slate-11">
          {{ t('COMMERCE.OVERVIEW.ORDERS') }}
        </dt>
        <dd
          class="text-body-main text-n-slate-12"
          data-test-id="commerce-overview-orders"
        >
          {{
            t(
              'COMMERCE.OVERVIEW.ORDERS_VALUE',
              { count: overview.orders_count_visible },
              overview.orders_count_visible
            )
          }}
        </dd>
        <dd class="text-label-small text-n-slate-11">
          {{
            t('COMMERCE.OVERVIEW.ACTIVITY', {
              active: overview.active_orders_count,
              shipped: overview.shipped_orders_count,
            })
          }}
        </dd>
      </div>
      <div class="flex flex-col rounded-lg bg-n-alpha-1 px-3 py-2">
        <dt class="text-label-small text-n-slate-11">
          {{ t('COMMERCE.OVERVIEW.LAST_PURCHASE') }}
        </dt>
        <dd
          class="text-body-main text-n-slate-12"
          data-test-id="commerce-overview-last-purchase"
        >
          {{ lastPurchase }}
        </dd>
      </div>
      <div
        class="flex flex-col rounded-lg bg-n-alpha-1 px-3 py-2"
        :title="t('COMMERCE.OVERVIEW.SPEND_HINT')"
      >
        <dt class="text-label-small text-n-slate-11">
          {{ t('COMMERCE.OVERVIEW.SPEND') }}
        </dt>
        <dd
          v-for="amount in spend"
          :key="amount"
          class="text-body-main text-n-slate-12"
          data-test-id="commerce-overview-spend"
        >
          {{ amount }}
        </dd>
        <dd v-if="!spend.length" class="text-body-main text-n-slate-11">
          {{ t('COMMERCE.OVERVIEW.NO_SPEND') }}
        </dd>
      </div>
    </dl>

    <div
      v-if="!isLinked"
      class="flex flex-col gap-1 text-body-main text-n-slate-11"
      data-test-id="commerce-overview-not-linked"
    >
      <span class="text-n-slate-12">{{
        t('COMMERCE.OVERVIEW.NOT_LINKED')
      }}</span>
      <span>{{ t('COMMERCE.OVERVIEW.NOT_LINKED_HINT') }}</span>
    </div>

    <section v-else class="flex flex-col">
      <button
        type="button"
        class="flex items-center justify-between py-1 text-start text-label-small text-n-slate-11"
        :aria-expanded="showOrders"
        @click="showOrders = !showOrders"
      >
        <span>{{ t('COMMERCE.OVERVIEW.RECENT_ORDERS') }}</span>
        <span
          :class="
            showOrders
              ? 'i-lucide-chevron-up size-4'
              : 'i-lucide-chevron-down size-4'
          "
        />
      </button>
      <template v-if="showOrders">
        <p
          v-if="!overview.latest_orders.length"
          class="text-body-main text-n-slate-11"
        >
          {{ t('COMMERCE.OVERVIEW.NO_ORDERS') }}
        </p>
        <CommerceOrderItem
          v-for="order in overview.latest_orders"
          :key="`${order.store.id}-${order.external_order_id}`"
          :order="order"
          :store="order.store"
        />
      </template>
    </section>

    <section class="flex flex-col">
      <button
        type="button"
        class="flex items-center justify-between py-1 text-start text-label-small text-n-slate-11"
        :aria-expanded="showStores"
        @click="showStores = !showStores"
      >
        <span>{{ t('COMMERCE.OVERVIEW.STORES_SECTION') }}</span>
        <span
          :class="
            showStores
              ? 'i-lucide-chevron-up size-4'
              : 'i-lucide-chevron-down size-4'
          "
        />
      </button>
      <ul v-if="showStores" class="flex flex-col gap-2">
        <li
          v-for="entry in overview.stores"
          :key="entry.store.id"
          class="flex items-start justify-between gap-2 rounded-lg border border-n-weak px-3 py-2"
          data-test-id="commerce-overview-store"
        >
          <div class="flex min-w-0 flex-col">
            <span class="truncate text-body-main text-n-slate-12">
              {{
                t('COMMERCE.OVERVIEW.ORDER_STORE', {
                  store: entry.store.name,
                  provider: providerName(entry.store.provider),
                })
              }}
            </span>
            <span
              class="text-label-small"
              :class="
                ATTENTION_STATES.includes(entry.state) || entry.error
                  ? 'text-n-amber-11'
                  : 'text-n-slate-11'
              "
            >
              {{ overviewState(entry.state) }}
            </span>
            <span
              v-if="identity(entry)"
              class="text-label-small text-n-slate-11"
            >
              {{ identity(entry) }}
            </span>
            <span
              v-if="freshness(entry)"
              class="text-label-small"
              :class="entry.stale ? 'text-n-amber-11' : 'text-n-slate-11'"
              data-test-id="commerce-overview-freshness"
            >
              {{ freshness(entry) }}
            </span>
          </div>
          <Button
            v-if="!NOT_OPENABLE_STATES.includes(entry.state)"
            :label="t('COMMERCE.OVERVIEW.OPEN_STORE')"
            variant="ghost"
            color="slate"
            size="xs"
            @click="emit('openStore', entry.store.id)"
          />
        </li>
      </ul>
    </section>
  </div>
</template>
