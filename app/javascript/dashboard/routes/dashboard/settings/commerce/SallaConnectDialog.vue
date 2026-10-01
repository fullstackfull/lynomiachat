<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { safeHttpsUrl } from 'dashboard/components/widgets/conversation/commerce/commerceHelper';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// Connects a Salla store (docs/commerce/10-salla-install-correlation.md): a one-time code the merchant pastes into the
// Lynomia app's settings in Salla, after which Salla's signed events connect the store. No token ever reaches the
// browser; the code lives only in this dialog and is cleared when it closes.
const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'connected']);

const POLL_INTERVAL_MS = 5000;
const PENDING = ['waiting', 'claimed'];

const { t, locale } = useI18n();
const { apiErrorMessage } = useCommerceLabels();
const dialogRef = ref(null);
const connection = ref(null);
const status = ref('none');
const errorMessage = ref('');
const isCreating = ref(false);
let pollTimer = null;

const installUrl = computed(() => safeHttpsUrl(connection.value?.install_url));
const expiresAt = computed(() =>
  connection.value
    ? new Intl.DateTimeFormat(locale.value, { timeStyle: 'short' }).format(
        new Date(connection.value.expires_at)
      )
    : ''
);
const statusMessage = computed(
  () =>
    ({
      waiting: t('COMMERCE.SETTINGS.SALLA.STATUS.WAITING'),
      claimed: t('COMMERCE.SETTINGS.SALLA.STATUS.CLAIMED'),
      connected: t('COMMERCE.SETTINGS.SALLA.STATUS.CONNECTED'),
      conflict: t('COMMERCE.SETTINGS.SALLA.STATUS.CONFLICT'),
      expired: t('COMMERCE.SETTINGS.SALLA.STATUS.EXPIRED'),
      limit_reached: t('COMMERCE.SETTINGS.SALLA.STATUS.LIMIT_REACHED'),
    })[status.value] || ''
);
const statusClass = computed(
  () =>
    ({
      connected: 'bg-n-teal-2 text-n-teal-11',
      conflict: 'bg-n-ruby-2 text-n-ruby-11',
      expired: 'bg-n-amber-2 text-n-amber-11',
      limit_reached: 'bg-n-amber-2 text-n-amber-11',
    })[status.value] || 'bg-n-alpha-2 text-n-slate-11'
);

const stopPolling = () => {
  clearInterval(pollTimer);
  pollTimer = null;
};

const poll = async () => {
  try {
    const response = await CommerceAPI.getSallaConnection();
    status.value = response.data.status;
    if (PENDING.includes(status.value)) return;

    stopPolling();
    if (status.value === 'connected') emit('connected');
  } catch (error) {
    errorMessage.value = apiErrorMessage(error);
    stopPolling();
  }
};

const createCode = async () => {
  isCreating.value = true;
  errorMessage.value = '';
  try {
    const response = await CommerceAPI.createSallaConnection();
    connection.value = response.data;
    status.value = 'waiting';
    stopPolling();
    pollTimer = setInterval(poll, POLL_INTERVAL_MS);
  } catch (error) {
    errorMessage.value = apiErrorMessage(error);
  } finally {
    isCreating.value = false;
  }
};

const copyCode = async () => {
  await copyTextToClipboard(connection.value.code);
  useAlert(t('COMMERCE.SETTINGS.SALLA.COPIED'));
};

watch(
  () => props.show,
  show => {
    if (show) {
      dialogRef.value?.open();
      return;
    }
    dialogRef.value?.close();
    stopPolling();
    connection.value = null;
    status.value = 'none';
    errorMessage.value = '';
  }
);

onBeforeUnmount(stopPolling);
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('COMMERCE.SETTINGS.SALLA.TITLE')"
    :description="t('COMMERCE.SETTINGS.SALLA.DESCRIPTION')"
    :show-confirm-button="false"
    :cancel-button-label="t('COMMERCE.SETTINGS.SALLA.CLOSE')"
    width="md"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <ol
        class="flex list-decimal flex-col gap-1.5 ps-5 text-body-main text-n-slate-12"
      >
        <li>{{ t('COMMERCE.SETTINGS.SALLA.STEP_CODE') }}</li>
        <li>{{ t('COMMERCE.SETTINGS.SALLA.STEP_INSTALL') }}</li>
        <li>{{ t('COMMERCE.SETTINGS.SALLA.STEP_SETTINGS') }}</li>
      </ol>

      <div
        v-if="connection"
        class="flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3"
      >
        <span class="text-label-small text-n-slate-11">
          {{ t('COMMERCE.SETTINGS.SALLA.CODE_LABEL') }}
        </span>
        <div class="flex flex-wrap items-center justify-between gap-2">
          <code
            dir="ltr"
            class="text-heading-2 tracking-wider text-n-slate-12"
            data-test-id="salla-connection-code"
          >
            {{ connection.code }}
          </code>
          <Button
            :label="t('COMMERCE.SETTINGS.SALLA.COPY')"
            icon="i-lucide-copy"
            variant="faded"
            color="slate"
            size="xs"
            @click="copyCode"
          />
        </div>
        <span class="text-label-small text-n-slate-11">
          {{ t('COMMERCE.SETTINGS.SALLA.EXPIRES', { time: expiresAt }) }}
        </span>
        <a
          v-if="installUrl"
          :href="installUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="text-label-small text-n-blue-11 hover:underline"
          data-test-id="salla-install-link"
        >
          {{ t('COMMERCE.SETTINGS.SALLA.OPEN_SALLA') }}
        </a>
      </div>

      <p
        v-if="statusMessage"
        class="rounded-lg px-3 py-2 text-body-main"
        :class="statusClass"
        data-test-id="salla-connection-status"
      >
        {{ statusMessage }}
      </p>
      <p
        v-if="errorMessage"
        class="rounded-lg bg-n-ruby-2 px-3 py-2 text-body-main text-n-ruby-11"
        data-test-id="salla-connection-error"
      >
        {{ errorMessage }}
      </p>

      <Button
        v-if="status !== 'connected'"
        :label="
          connection
            ? t('COMMERCE.SETTINGS.SALLA.NEW_CODE')
            : t('COMMERCE.SETTINGS.SALLA.CREATE_CODE')
        "
        :variant="connection ? 'faded' : 'solid'"
        size="sm"
        :is-loading="isCreating"
        data-test-id="salla-create-code"
        @click="createCode"
      />
    </div>
  </Dialog>
</template>
