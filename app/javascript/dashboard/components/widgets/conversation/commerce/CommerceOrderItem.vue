<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Button from 'dashboard/components-next/button/Button.vue';
import CommerceOrderActions from './CommerceOrderActions.vue';
import { useCommerceLabels } from './useCommerceLabels';
import {
  formatAmount,
  formatDate,
  hasTracking,
  safeAdminUrl,
  safeHttpsUrl,
  trackingMessage,
} from './commerceHelper';

const props = defineProps({
  order: { type: Object, required: true },
  // The order's store, shown when orders of several stores are listed together (Customer 360).
  store: { type: Object, default: null },
  // Orders found by number may be another customer's: their tracking is not offered for sending into the conversation.
  canSend: { type: Boolean, default: true },
  // The order's store when this agent is offered order actions there (the linked customer's orders only).
  actionsStoreId: { type: Number, default: null },
  conversationId: { type: [Number, String], default: null },
});

const emit = defineEmits(['actionDone']);

const { t, locale } = useI18n();
const { orderStatus, paymentStatus, shipmentStatus, providerName } =
  useCommerceLabels();

const STATUS_CLASSES = {
  completed: 'bg-n-teal-3 text-n-teal-11',
  processing: 'bg-n-blue-3 text-n-blue-11',
  shipped: 'bg-n-blue-3 text-n-blue-11',
  delivered: 'bg-n-teal-3 text-n-teal-11',
  pending: 'bg-n-amber-3 text-n-amber-11',
  on_hold: 'bg-n-amber-3 text-n-amber-11',
  cancelled: 'bg-n-slate-3 text-n-slate-11',
  refunded: 'bg-n-slate-3 text-n-slate-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};
const PAYMENT_CLASSES = {
  paid: 'bg-n-teal-3 text-n-teal-11',
  unpaid: 'bg-n-amber-3 text-n-amber-11',
  partially_paid: 'bg-n-amber-3 text-n-amber-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};
const NEUTRAL_BADGE = 'bg-n-slate-3 text-n-slate-11';

const total = computed(() =>
  formatAmount(props.order.total, props.order.currency, locale.value)
);
const createdAt = computed(() =>
  formatDate(props.order.created_at, locale.value)
);
const adminUrl = computed(() => safeAdminUrl(props.order.admin_order_url));
const trackingUrl = computed(() => safeHttpsUrl(props.order.tracking?.url));
const canSendTracking = computed(
  () => props.canSend && hasTracking(props.order)
);

const sendTracking = () => {
  emitter.emit(
    BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
    trackingMessage(props.order, t)
  );
  useAlert(t('COMMERCE.PANEL.TRACKING_INSERTED'));
};
</script>

<template>
  <div
    class="flex flex-col gap-2 py-3 border-b border-n-weak last:border-b-0"
    data-test-id="commerce-order"
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <span class="text-heading-3 text-n-slate-12" dir="ltr">
        {{ t('COMMERCE.PANEL.ORDER_NUMBER', { number: order.order_number }) }}
      </span>
      <div class="flex items-center gap-1">
        <span class="text-body-main text-n-slate-12">{{ total }}</span>
        <CommerceOrderActions
          v-if="actionsStoreId && conversationId"
          :conversation-id="conversationId"
          :store-id="actionsStoreId"
          :order="order"
          @done="emit('actionDone')"
        />
      </div>
    </div>
    <span
      v-if="store"
      class="text-label-small text-n-slate-11"
      data-test-id="commerce-order-store"
    >
      {{
        t('COMMERCE.OVERVIEW.ORDER_STORE', {
          store: store.name,
          provider: providerName(store.provider),
        })
      }}
    </span>
    <div class="flex flex-wrap items-center gap-1.5">
      <span
        class="px-1.5 py-0.5 rounded-md text-label-small"
        :class="STATUS_CLASSES[order.status] || NEUTRAL_BADGE"
      >
        {{ orderStatus(order.status) }}
      </span>
      <span
        class="px-1.5 py-0.5 rounded-md text-label-small"
        :class="PAYMENT_CLASSES[order.payment_status] || NEUTRAL_BADGE"
      >
        {{ paymentStatus(order.payment_status) }}
      </span>
    </div>
    <div
      class="flex flex-wrap items-center gap-x-3 gap-y-1 text-body-main text-n-slate-11"
    >
      <span>{{ createdAt }}</span>
      <span v-if="order.item_count != null">
        {{
          t(
            'COMMERCE.PANEL.ITEMS',
            { count: order.item_count },
            order.item_count
          )
        }}
      </span>
      <span v-if="order.shipping?.method">{{ order.shipping.method }}</span>
      <span v-if="order.shipping?.status" data-test-id="commerce-shipment">
        {{ shipmentStatus(order.shipping.status) }}
      </span>
    </div>
    <div
      v-if="adminUrl || trackingUrl || canSendTracking"
      class="flex flex-wrap gap-2"
    >
      <a
        v-if="adminUrl"
        :href="adminUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="text-label-small text-n-blue-11 hover:underline"
      >
        {{ t('COMMERCE.PANEL.VIEW_ORDER') }}
      </a>
      <a
        v-if="trackingUrl"
        :href="trackingUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="text-label-small text-n-blue-11 hover:underline"
      >
        {{ t('COMMERCE.PANEL.TRACK_SHIPMENT') }}
      </a>
      <Button
        v-if="canSendTracking"
        :label="t('COMMERCE.PANEL.SEND_TRACKING')"
        variant="link"
        size="xs"
        @click="sendTracking"
      />
    </div>
  </div>
</template>
