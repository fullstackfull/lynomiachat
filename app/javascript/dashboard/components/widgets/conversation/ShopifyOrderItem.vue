<script setup>
import { computed } from 'vue';
import Label from 'dashboard/components-next/label/Label.vue';
import { format } from 'date-fns';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  order: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const formatDate = dateString => {
  return format(new Date(dateString), 'MMM d, yyyy');
};

const formatCurrency = (amount, currency) => {
  return new Intl.NumberFormat('en', {
    style: 'currency',
    currency: currency || 'USD',
  }).format(amount);
};

const getStatusI18nKey = (type, status = '') => {
  return `CONVERSATION_SIDEBAR.SHOPIFY.${type.toUpperCase()}_STATUS.${status.toUpperCase()}`;
};

const fulfillmentStatus = computed(() => {
  const { fulfillment_status: status } = props.order;
  if (!status) {
    return '';
  }
  return t(getStatusI18nKey('FULFILLMENT', status));
});

const financialStatus = computed(() => {
  const { financial_status: status } = props.order;
  if (!status) {
    return '';
  }
  return t(getStatusI18nKey('FINANCIAL', status));
});

const getFulfillmentClass = status => {
  const classes = {
    fulfilled: 'text-n-teal-9',
    partial: 'text-n-amber-9',
    unfulfilled: 'text-n-ruby-9',
  };
  return classes[status] || 'text-n-slate-11';
};
</script>

<template>
  <div
    class="py-3 border-b border-n-weak last:border-b-0 flex flex-col gap-1.5"
  >
    <div class="flex justify-between items-center">
      <div class="font-medium flex">
        <a
          :href="order.admin_url"
          target="_blank"
          rel="noopener noreferrer"
          class="hover:underline text-n-slate-12 cursor-pointer truncate"
        >
          {{ $t('CONVERSATION_SIDEBAR.SHOPIFY.ORDER_ID', { id: order.id }) }}
          <i class="i-lucide-external-link ps-5" />
        </a>
      </div>
      <Label
        :label="financialStatus"
        :tone="order.financial_status === 'paid' ? 'success' : 'neutral'"
        variant="solid"
        compact
        :title="financialStatus"
        class="min-w-0 shrink [&>span]:truncate"
      />
    </div>
    <div class="text-sm text-n-slate-12">
      <span class="text-n-slate-11 border-e border-n-weak pe-2">
        {{ formatDate(order.created_at) }}
      </span>
      <span class="text-n-slate-11 ps-2">
        {{ formatCurrency(order.total_price, order.currency) }}
      </span>
    </div>
    <div v-if="fulfillmentStatus">
      <span
        :class="getFulfillmentClass(order.fulfillment_status)"
        class="capitalize font-medium"
        :title="fulfillmentStatus"
      >
        {{ fulfillmentStatus }}
      </span>
    </div>
  </div>
</template>
