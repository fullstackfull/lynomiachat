<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import AccountLinkAPI from 'dashboard/api/accountLink';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

// Minting the proof that this merchant controls this workspace.
//
// An external platform cannot honestly establish that by itself: it cannot read an account it has not linked, and
// going by email address would be a takeover rather than a link. So the proof is made here, by somebody who has
// already signed in as an administrator, and handed over as a short-lived one-time code.
//
// The code is the only thing that ever leaves this page, it is shown once, and only its HMAC is stored server
// side. No token and no account identifier passes through the browser.

const POLL_INTERVAL_MS = 5000;
// Statuses that can still change on their own; anything else is settled and polling stops.
const PENDING = ['waiting', 'claimed'];

const { t, locale } = useI18n();
const { installationName } = useBranding();

const connection = ref(null);
const status = ref('none');
const errorMessage = ref('');
const isCreating = ref(false);
const isLoading = ref(true);
let pollTimer = null;

const expiresAt = computed(() =>
  connection.value
    ? new Intl.DateTimeFormat(locale.value, { timeStyle: 'short' }).format(
        new Date(connection.value.expires_at)
      )
    : ''
);

// The vocabulary is AccountLinkCode's, not Salla's: there is no `conflict` or `limit_reached`
// here, and there IS a `revoked`, which is what the merchant sees after support hands a grant back.
const statusMessage = computed(
  () =>
    ({
      waiting: t('ACCOUNT_LINK.STATUS.WAITING'),
      claimed: t('ACCOUNT_LINK.STATUS.CLAIMED'),
      connected: t('ACCOUNT_LINK.STATUS.CONNECTED'),
      expired: t('ACCOUNT_LINK.STATUS.EXPIRED'),
      revoked: t('ACCOUNT_LINK.STATUS.REVOKED'),
    })[status.value] || ''
);

const statusClass = computed(
  () =>
    ({
      connected: 'bg-n-teal-2 text-n-teal-11',
      expired: 'bg-n-amber-2 text-n-amber-11',
      revoked: 'bg-n-ruby-2 text-n-ruby-11',
    })[status.value] || 'bg-n-alpha-2 text-n-slate-11'
);

const stopPolling = () => {
  clearInterval(pollTimer);
  pollTimer = null;
};

const readStatus = async () => {
  try {
    const response = await AccountLinkAPI.getStatus();
    status.value = response.data.status;
    if (PENDING.includes(status.value)) return;
    stopPolling();
  } catch (error) {
    errorMessage.value = t('ACCOUNT_LINK.ERROR');
    stopPolling();
  }
};

const createCode = async () => {
  isCreating.value = true;
  errorMessage.value = '';
  try {
    const response = await AccountLinkAPI.createCode();
    connection.value = response.data;
    status.value = 'waiting';
    stopPolling();
    pollTimer = setInterval(readStatus, POLL_INTERVAL_MS);
  } catch (error) {
    errorMessage.value = t('ACCOUNT_LINK.ERROR');
  } finally {
    isCreating.value = false;
  }
};

const copyCode = async () => {
  await copyTextToClipboard(connection.value.code);
  useAlert(t('ACCOUNT_LINK.COPIED'));
};

onMounted(async () => {
  await readStatus();
  isLoading.value = false;
  // Pick the polling back up for a merchant who reloads the page mid-connection.
  if (PENDING.includes(status.value)) {
    pollTimer = setInterval(readStatus, POLL_INTERVAL_MS);
  }
});

onBeforeUnmount(stopPolling);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('ACCOUNT_LINK.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('ACCOUNT_LINK.TITLE')"
        :description="t('ACCOUNT_LINK.DESCRIPTION', { installationName })"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-4">
        <ol
          class="flex list-decimal flex-col gap-1.5 ps-5 text-body-main text-n-slate-12"
        >
          <li>{{ t('ACCOUNT_LINK.STEP_CODE') }}</li>
          <li>{{ t('ACCOUNT_LINK.STEP_PASTE') }}</li>
          <li>{{ t('ACCOUNT_LINK.STEP_APPROVE') }}</li>
        </ol>

        <div
          v-if="connection"
          class="flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3"
        >
          <span class="text-label-small text-n-slate-11">
            {{ t('ACCOUNT_LINK.CODE_LABEL') }}
          </span>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <!-- dir=ltr: the code is a machine value and must not mirror in Arabic. -->
            <code
              dir="ltr"
              class="text-heading-2 tracking-wider text-n-slate-12"
              data-test-id="account-link-code"
            >
              {{ connection.code }}
            </code>
            <Button
              :label="t('ACCOUNT_LINK.COPY')"
              icon="i-lucide-copy"
              variant="faded"
              color="slate"
              size="xs"
              @click="copyCode"
            />
          </div>
          <span class="text-label-small text-n-slate-11">
            {{ t('ACCOUNT_LINK.EXPIRES', { time: expiresAt }) }}
          </span>
          <span class="text-label-small text-n-amber-11">
            {{ t('ACCOUNT_LINK.SHOWN_ONCE') }}
          </span>
        </div>

        <p
          v-if="statusMessage"
          class="rounded-lg px-3 py-2 text-body-main"
          :class="statusClass"
          data-test-id="account-link-status"
        >
          {{ statusMessage }}
        </p>
        <p
          v-if="errorMessage"
          class="rounded-lg bg-n-ruby-2 px-3 py-2 text-body-main text-n-ruby-11"
          data-test-id="account-link-error"
        >
          {{ errorMessage }}
        </p>

        <div>
          <Button
            :label="
              connection
                ? t('ACCOUNT_LINK.NEW_CODE')
                : t('ACCOUNT_LINK.CREATE_CODE')
            "
            :variant="connection ? 'faded' : 'solid'"
            size="sm"
            :is-loading="isCreating"
            data-test-id="account-link-create"
            @click="createCode"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
