<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { formatAmount } from './commerceHelper';
import { useCommerceLabels } from './useCommerceLabels';
import { useCommerceActionLabels } from './useCommerceActionLabels';

// The order card's actions (docs/commerce/28-commerce-actions-architecture.md). Nothing runs from the menu: the agent
// picks an action, fills in what it needs, reviews what will happen in the store and confirms with a button (never
// Enter). The backend reads the order again before sending anything; this dialog shows only what the backend answers.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  storeId: { type: Number, required: true },
  order: { type: Object, required: true },
});

const emit = defineEmits(['done']);

const ACTION_ORDER = [
  'update_order_status',
  'resend_invoice',
  'resend_payment_link',
  'cancel_order',
  'refund_partial',
  'refund_full',
];
const DESTRUCTIVE = ['cancel_order', 'refund_partial', 'refund_full'];
const NEEDS_FORM = [
  'update_order_status',
  'cancel_order',
  'refund_partial',
  'refund_full',
];
const AMOUNT_PATTERN = /^\d{1,12}(\.\d{1,4})?$/;
const POLL_INTERVAL_MS = 1500;
const POLL_LIMIT = 40;
const OPEN_RUN_STATUSES = ['pending', 'running', 'unknown'];
const STEPS = {
  MENU: 'menu',
  FORM: 'form',
  REVIEW: 'review',
  RESULT: 'result',
};

const { t, locale } = useI18n();
const { apiErrorMessage, errorMessage, orderStatus, providerName } =
  useCommerceLabels();
const { actionLabel, unavailableReason, refundReasons, cancelReasons } =
  useCommerceActionLabels();

const dialogRef = ref(null);
const step = ref(STEPS.MENU);
const availability = ref(null);
const isLoading = ref(false);
const loadError = ref('');
const actionType = ref('');
const amount = ref('');
const reason = ref('');
const targetStatus = ref('');
const formError = ref('');
const idempotencyKey = ref('');
const isSubmitting = ref(false);
const submitError = ref('');
const run = ref(null);
const pollsLeft = ref(0);
let pollTimer = null;

const capability = computed(
  () => availability.value?.actions?.[actionType.value] || {}
);
// Unsupported actions are not listed; the others say why they are not possible.
const listedActions = computed(() =>
  ACTION_ORDER.map(type => ({
    type,
    ...(availability.value?.actions?.[type] || {}),
  })).filter(action => action.available || action.reason !== 'unsupported')
);
const isRefund = computed(() => actionType.value.startsWith('refund_'));
const isDestructive = computed(() => DESTRUCTIVE.includes(actionType.value));
const earlierUnresolved = computed(() =>
  OPEN_RUN_STATUSES.includes(availability.value?.last_run?.status)
);
const storeLine = computed(() => {
  const store = availability.value?.store;
  if (!store) return '';
  return t('COMMERCE.ACTIONS.STORE_LINE', {
    store: store.name,
    provider: providerName(store.provider),
  });
});
const money = value =>
  formatAmount(value, capability.value.currency, locale.value);
const statusOptions = computed(() =>
  (capability.value.targets || []).map(value => ({
    value,
    label: orderStatus(value),
  }))
);

const consequence = computed(() => {
  const shown = money(amount.value);
  switch (actionType.value) {
    case 'refund_full':
    case 'refund_partial':
      if (capability.value.mode !== 'gateway') {
        return t('COMMERCE.ACTIONS.CONSEQUENCES.REFUND_MANUAL', {
          amount: shown,
        });
      }
      return capability.value.gateway
        ? t('COMMERCE.ACTIONS.CONSEQUENCES.REFUND_GATEWAY', {
            amount: shown,
            gateway: capability.value.gateway,
          })
        : t('COMMERCE.ACTIONS.CONSEQUENCES.REFUND_GATEWAY_UNNAMED', {
            amount: shown,
          });
    case 'cancel_order':
      return capability.value.restocks === false
        ? t('COMMERCE.ACTIONS.CONSEQUENCES.CANCEL_NO_RESTOCK')
        : t('COMMERCE.ACTIONS.CONSEQUENCES.CANCEL');
    case 'update_order_status':
      return t('COMMERCE.ACTIONS.CONSEQUENCES.STATUS', {
        from: orderStatus(availability.value?.order?.status),
        to: orderStatus(targetStatus.value),
      });
    case 'resend_payment_link':
      return t('COMMERCE.ACTIONS.CONSEQUENCES.RESEND_PAYMENT_LINK');
    default:
      return t('COMMERCE.ACTIONS.CONSEQUENCES.RESEND_INVOICE');
  }
});

const resultMessage = computed(() => {
  const status = run.value?.status;
  if (status === 'succeeded') return t('COMMERCE.ACTIONS.RESULT.SUCCEEDED');
  if (status === 'failed') return errorMessage(run.value.error_code);
  if (status === 'unknown') {
    return run.value.reconcile === 'exhausted'
      ? t('COMMERCE.ACTIONS.RESULT.UNRESOLVED')
      : t('COMMERCE.ACTIONS.RESULT.UNKNOWN');
  }
  return pollsLeft.value > 0
    ? t('COMMERCE.ACTIONS.RESULT.PROCESSING')
    : t('COMMERCE.ACTIONS.RESULT.STILL_PROCESSING');
});
const isWaiting = computed(
  () =>
    ['pending', 'running'].includes(run.value?.status) && pollsLeft.value > 0
);

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};
onBeforeUnmount(stopPolling);

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  availability.value = null;
  try {
    const response = await CommerceAPI.getOrderActions(
      props.conversationId,
      props.storeId,
      props.order.external_order_id
    );
    availability.value = response.data;
  } catch (error) {
    loadError.value = apiErrorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

const open = () => {
  stopPolling();
  step.value = STEPS.MENU;
  run.value = null;
  submitError.value = '';
  dialogRef.value?.open();
  load();
};

const close = () => dialogRef.value?.close();

const toReview = () => {
  formError.value = '';
  if (isRefund.value) {
    const value = amount.value.trim();
    const valid =
      AMOUNT_PATTERN.test(value) &&
      Number(value) > 0 &&
      Number(value) <= Number(capability.value.max_amount);
    if (!valid) {
      formError.value = t('COMMERCE.ACTIONS.FORM.INVALID_AMOUNT', {
        amount: money(capability.value.max_amount),
      });
      return;
    }
    amount.value = value;
  }
  // One key per confirmation: a double click or a retried request is the same action, never a second one.
  idempotencyKey.value = `commerce-action:${window.crypto.randomUUID()}`;
  submitError.value = '';
  step.value = STEPS.REVIEW;
};

const choose = type => {
  actionType.value = type;
  const offered = availability.value.actions[type];
  amount.value = type === 'refund_full' ? offered.max_amount : '';
  reason.value = 'customer_request';
  targetStatus.value = offered.targets?.[0] || '';
  formError.value = '';
  if (NEEDS_FORM.includes(type)) step.value = STEPS.FORM;
  else toReview();
};

const actionParams = () => {
  if (isRefund.value) {
    return {
      amount: amount.value,
      currency: capability.value.currency,
      reason: reason.value,
    };
  }
  if (actionType.value === 'cancel_order') return { reason: reason.value };
  if (actionType.value === 'update_order_status') {
    return { target_status: targetStatus.value };
  }
  return {};
};

const finish = () => {
  if (run.value.status !== 'succeeded') return;
  useAlert(
    t('COMMERCE.ACTIONS.DONE_ALERT', {
      number: props.order.order_number,
      store: availability.value.store.name,
    })
  );
  emit('done');
};

const poll = async () => {
  try {
    const response = await CommerceAPI.getActionRun(
      props.conversationId,
      run.value.id
    );
    run.value = response.data;
  } catch {
    // The run is kept server-side; the next poll or the panel's refresh shows it.
  }
  pollsLeft.value -= 1;
  if (isWaiting.value) {
    pollTimer = setTimeout(poll, POLL_INTERVAL_MS);
  } else {
    finish();
  }
};

const confirm = async () => {
  if (isSubmitting.value) return;
  isSubmitting.value = true;
  submitError.value = '';
  try {
    const response = await CommerceAPI.requestOrderAction(
      props.conversationId,
      props.storeId,
      props.order.external_order_id,
      {
        action_type: actionType.value,
        version: availability.value.version,
        idempotency_key: idempotencyKey.value,
        params: actionParams(),
      }
    );
    run.value = response.data;
    step.value = STEPS.RESULT;
    pollsLeft.value = POLL_LIMIT;
    pollTimer = setTimeout(poll, POLL_INTERVAL_MS);
  } catch (error) {
    submitError.value =
      error?.response?.status === 401
        ? unavailableReason('permission_denied')
        : apiErrorMessage(error);
  } finally {
    isSubmitting.value = false;
  }
};

const back = () => {
  step.value =
    step.value === STEPS.REVIEW && NEEDS_FORM.includes(actionType.value)
      ? STEPS.FORM
      : STEPS.MENU;
};
</script>

<template>
  <Button
    icon="i-lucide-ellipsis"
    variant="ghost"
    color="slate"
    size="xs"
    :aria-label="t('COMMERCE.ACTIONS.MENU')"
    :title="t('COMMERCE.ACTIONS.MENU')"
    data-test-id="commerce-order-actions"
    @click="open"
  />
  <Dialog
    ref="dialogRef"
    :title="t('COMMERCE.ACTIONS.TITLE', { number: order.order_number })"
    width="md"
    @close="stopPolling"
  >
    <template #description>
      <p class="text-body-main text-n-slate-11">{{ storeLine }}</p>
    </template>

    <div class="flex flex-col gap-3" data-test-id="commerce-action-dialog">
      <div v-if="isLoading" class="flex items-center gap-2 text-n-slate-11">
        <Spinner class="text-n-brand" />
        <span class="text-body-main">{{ t('COMMERCE.ACTIONS.LOADING') }}</span>
      </div>
      <p v-else-if="loadError" class="text-body-main text-n-ruby-11">
        {{ loadError }}
      </p>

      <template v-else-if="availability && step === STEPS.MENU">
        <p
          v-if="earlierUnresolved"
          class="rounded-lg bg-n-amber-2 px-3 py-2 text-body-main text-n-amber-11"
          data-test-id="commerce-action-unresolved"
        >
          {{ t('COMMERCE.ACTIONS.RESULT.EARLIER_UNRESOLVED') }}
        </p>
        <p v-if="!listedActions.length" class="text-body-main text-n-slate-11">
          {{ t('COMMERCE.ACTIONS.NONE') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="action in listedActions"
            :key="action.type"
            class="flex flex-col gap-1"
          >
            <Button
              :label="actionLabel(action.type)"
              variant="faded"
              :color="DESTRUCTIVE.includes(action.type) ? 'ruby' : 'slate'"
              size="sm"
              class="justify-start"
              type="button"
              :disabled="!action.available"
              :data-test-id="`commerce-action-${action.type}`"
              @click="choose(action.type)"
            />
            <span
              v-if="!action.available"
              class="text-label-small text-n-slate-11"
            >
              {{ unavailableReason(action.reason) }}
            </span>
          </li>
        </ul>
      </template>

      <template v-else-if="step === STEPS.FORM">
        <span class="text-heading-3 text-n-slate-12">
          {{ actionLabel(actionType) }}
        </span>
        <template v-if="isRefund">
          <Input
            v-model="amount"
            :label="t('COMMERCE.ACTIONS.FORM.AMOUNT')"
            :disabled="actionType === 'refund_full'"
            :message="
              formError ||
              t('COMMERCE.ACTIONS.FORM.AMOUNT_HINT', {
                amount: money(capability.max_amount),
              })
            "
            :message-type="formError ? 'error' : 'info'"
            inputmode="decimal"
            dir="ltr"
            data-test-id="commerce-action-amount"
          />
        </template>
        <label
          v-if="isRefund || actionType === 'cancel_order'"
          class="flex flex-col gap-1 text-label-small text-n-slate-11"
        >
          {{ t('COMMERCE.ACTIONS.FORM.REASON') }}
          <Select
            v-model="reason"
            class="!w-full [&>select]:w-full"
            :options="isRefund ? refundReasons : cancelReasons"
          />
        </label>
        <label
          v-if="actionType === 'update_order_status'"
          class="flex flex-col gap-1 text-label-small text-n-slate-11"
        >
          {{ t('COMMERCE.ACTIONS.FORM.NEW_STATUS') }}
          <Select
            v-model="targetStatus"
            class="!w-full [&>select]:w-full"
            :options="statusOptions"
          />
        </label>
      </template>

      <template v-else-if="step === STEPS.REVIEW">
        <span class="text-heading-3 text-n-slate-12">
          {{ t('COMMERCE.ACTIONS.REVIEW.HEADING') }}
        </span>
        <dl
          class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-body-main"
          data-test-id="commerce-action-review"
        >
          <dt class="text-n-slate-11">
            {{ t('COMMERCE.ACTIONS.REVIEW.STORE') }}
          </dt>
          <dd class="text-n-slate-12">{{ storeLine }}</dd>
          <dt class="text-n-slate-11">
            {{ t('COMMERCE.ACTIONS.REVIEW.ORDER') }}
          </dt>
          <dd class="text-n-slate-12" dir="ltr">#{{ order.order_number }}</dd>
          <dt class="text-n-slate-11">
            {{ t('COMMERCE.ACTIONS.REVIEW.ACTION') }}
          </dt>
          <dd class="text-n-slate-12">{{ actionLabel(actionType) }}</dd>
          <template v-if="isRefund">
            <dt class="text-n-slate-11">
              {{ t('COMMERCE.ACTIONS.REVIEW.AMOUNT') }}
            </dt>
            <dd
              class="text-n-slate-12"
              data-test-id="commerce-action-amount-review"
            >
              {{ money(amount) }}
            </dd>
          </template>
        </dl>
        <p
          class="rounded-lg px-3 py-2 text-body-main"
          :class="
            isDestructive
              ? 'bg-n-ruby-2 text-n-ruby-11'
              : 'bg-n-alpha-2 text-n-slate-12'
          "
          data-test-id="commerce-action-consequence"
        >
          {{ consequence }}
        </p>
        <p v-if="submitError" class="text-body-main text-n-ruby-11">
          {{ submitError }}
        </p>
      </template>

      <div
        v-else-if="step === STEPS.RESULT"
        class="flex items-center gap-2 text-body-main"
        data-test-id="commerce-action-result"
      >
        <Spinner v-if="isWaiting" class="text-n-brand" />
        <span
          :class="{
            'text-n-teal-11': run?.status === 'succeeded',
            'text-n-ruby-11': run?.status === 'failed',
            'text-n-amber-11': run?.status === 'unknown',
            'text-n-slate-11': isWaiting,
          }"
        >
          {{ resultMessage }}
        </span>
      </div>
    </div>

    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <Button
          v-if="step === STEPS.FORM || step === STEPS.REVIEW"
          :label="t('COMMERCE.ACTIONS.FORM.BACK')"
          variant="faded"
          color="slate"
          class="w-full"
          type="button"
          :disabled="isSubmitting"
          @click="back"
        />
        <Button
          v-else
          :label="t('COMMERCE.ACTIONS.FORM.CLOSE')"
          variant="faded"
          color="slate"
          class="w-full"
          type="button"
          @click="close"
        />
        <Button
          v-if="step === STEPS.FORM"
          :label="t('COMMERCE.ACTIONS.FORM.REVIEW')"
          class="w-full"
          type="button"
          data-test-id="commerce-action-review-button"
          @click="toReview"
        />
        <Button
          v-if="step === STEPS.REVIEW"
          :label="t('COMMERCE.ACTIONS.FORM.CONFIRM')"
          :color="isDestructive ? 'ruby' : 'blue'"
          class="w-full"
          type="button"
          :is-loading="isSubmitting"
          :disabled="isSubmitting"
          data-test-id="commerce-action-confirm"
          @click="confirm"
        />
      </div>
    </template>
  </Dialog>
</template>
