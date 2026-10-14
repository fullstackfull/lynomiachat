<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import AccountLinkAPI from 'dashboard/api/accountLink';
import AccountGrantsAPI from 'dashboard/api/accountGrants';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

// Minting the proof that this merchant controls this workspace, and seeing who holds it.
//
// An external platform cannot honestly establish that by itself: it cannot read an account it has not linked, and
// going by email address would be a takeover rather than a link. So the proof is made here, by somebody who has
// already signed in as an administrator, and handed over as a short-lived one-time code.
//
// THE CODE NAMES ITS INTEGRATION. Without that it is a bearer token for whoever presents it first, and on an
// installation carrying more than one app that is reachable by ordinary mistake rather than by attack: paste it
// into the wrong integration's field and that one gets a working grant while the intended one is told only
// "invalid or expired". The selector below is not a convenience -- the server refuses a code with no audience.
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
const platformApps = ref([]);
const selectedAppId = ref('');
const grants = ref([]);
const revokingAppId = ref(null);
const revokeDialogRef = ref(null);
const grantToRevoke = ref(null);
let pollTimer = null;

const expiresAt = computed(() =>
  connection.value
    ? new Intl.DateTimeFormat(locale.value, { timeStyle: 'short' }).format(
        new Date(connection.value.expires_at)
      )
    : ''
);

const appOptions = computed(() =>
  platformApps.value.map(app => ({ value: app.id, label: app.name }))
);

const formatDate = value =>
  value
    ? new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(
        new Date(value)
      )
    : '';

// The vocabulary is AccountLinkCode's, not Salla's: there is no `conflict` or `limit_reached`
// here, and there IS a `revoked`, which is what the merchant sees after a grant is handed back.
const connectedApp = ref('');
// Which integration the live code was minted for. It survives a reload, where `connection` does
// not: after refreshing, the code itself is gone from the page but knowing who it is addressed
// to is exactly what tells a merchant whether they generated the right one.
const intendedApp = ref('');

const statusMessage = computed(
  () =>
    ({
      waiting: intendedApp.value
        ? t('ACCOUNT_LINK.STATUS.WAITING_FOR', { app: intendedApp.value })
        : t('ACCOUNT_LINK.STATUS.WAITING'),
      claimed: t('ACCOUNT_LINK.STATUS.CLAIMED'),
      connected: connectedApp.value
        ? t('ACCOUNT_LINK.STATUS.CONNECTED', { app: connectedApp.value })
        : t('ACCOUNT_LINK.STATUS.CONNECTED_UNKNOWN'),
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

const readGrants = async () => {
  const response = await AccountGrantsAPI.get();
  grants.value = response.data.grants || [];
  platformApps.value = response.data.platform_apps || [];
  // Pre-select only when there is nothing to choose between. With several, the merchant picks,
  // because picking for them is how a code ends up minted for an integration nobody meant.
  if (!selectedAppId.value && platformApps.value.length === 1) {
    selectedAppId.value = platformApps.value[0].id;
  }
};

const readStatus = async () => {
  try {
    const response = await AccountLinkAPI.getStatus();
    status.value = response.data.status;
    connectedApp.value = response.data.connected_app || '';
    intendedApp.value = response.data.intended_app || '';
    if (PENDING.includes(status.value)) return;
    stopPolling();
    // A code that has just been spent changes who holds what, so the list below is re-read
    // rather than left showing the state from before the connection completed.
    await readGrants();
  } catch (error) {
    errorMessage.value = t('ACCOUNT_LINK.ERROR');
    stopPolling();
  }
};

const createCode = async () => {
  if (!selectedAppId.value) {
    errorMessage.value = t('ACCOUNT_LINK.CHOOSE_APP_FIRST');
    return;
  }

  isCreating.value = true;
  errorMessage.value = '';
  try {
    const response = await AccountLinkAPI.createCode(selectedAppId.value);
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

// CONFIRMED, BECAUSE IT CANNOT BE UNDONE FROM HERE. Disconnecting ends the integration's access
// immediately and signs out anyone currently inside through it; getting it back means the
// merchant minting another code and the platform redeeming it.
const askToRevoke = grant => {
  grantToRevoke.value = grant;
  revokeDialogRef.value?.open();
};

const confirmRevoke = async () => {
  const grant = grantToRevoke.value;
  if (!grant) return;

  revokingAppId.value = grant.platform_app_id;
  errorMessage.value = '';
  try {
    await AccountGrantsAPI.revoke(grant.platform_app_id);
    useAlert(
      t('ACCOUNT_LINK.GRANTS.REVOKED', { app: grant.platform_app_name })
    );
    await Promise.all([readGrants(), readStatus()]);
  } catch (error) {
    errorMessage.value = t('ACCOUNT_LINK.ERROR');
  } finally {
    revokingAppId.value = null;
    grantToRevoke.value = null;
    revokeDialogRef.value?.close();
  }
};

const copyCode = async () => {
  await copyTextToClipboard(connection.value.code);
  useAlert(t('ACCOUNT_LINK.COPIED'));
};

onMounted(async () => {
  try {
    await readGrants();
  } catch (error) {
    errorMessage.value = t('ACCOUNT_LINK.ERROR');
  }
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
      <div class="flex flex-col gap-6">
        <div class="flex flex-col gap-4">
          <ol
            class="flex list-decimal flex-col gap-1.5 ps-5 text-body-main text-n-slate-12"
          >
            <li>{{ t('ACCOUNT_LINK.STEP_CHOOSE') }}</li>
            <li>{{ t('ACCOUNT_LINK.STEP_CODE') }}</li>
            <li>{{ t('ACCOUNT_LINK.STEP_PASTE') }}</li>
            <li>{{ t('ACCOUNT_LINK.STEP_APPROVE') }}</li>
          </ol>

          <div class="flex flex-col gap-1.5">
            <label
              for="account-link-app"
              class="text-label-small text-n-slate-11"
            >
              {{ t('ACCOUNT_LINK.APP_LABEL') }}
            </label>
            <Select
              id="account-link-app"
              v-model="selectedAppId"
              :options="appOptions"
              :placeholder="t('ACCOUNT_LINK.APP_PLACEHOLDER')"
              :aria-label="t('ACCOUNT_LINK.APP_LABEL')"
              data-test-id="account-link-app"
            />
            <span class="text-label-small text-n-slate-11">
              {{ t('ACCOUNT_LINK.APP_HINT') }}
            </span>
          </div>

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
            <span
              v-if="connection.platform_app"
              class="text-label-small text-n-slate-11"
              data-test-id="account-link-audience"
            >
              {{
                t('ACCOUNT_LINK.ONLY_FOR', {
                  app: connection.platform_app.name,
                })
              }}
            </span>
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

        <!-- WHO HOLDS ACCESS, AND TAKING IT BACK. Consent that cannot be withdrawn by the
             party who gave it is not consent, so this is a merchant control and not a
             support one. -->
        <div class="flex flex-col gap-2">
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('ACCOUNT_LINK.GRANTS.TITLE') }}
          </h4>
          <p class="text-body-main text-n-slate-11">
            {{ t('ACCOUNT_LINK.GRANTS.DESCRIPTION') }}
          </p>

          <p
            v-if="!grants.length"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-body-main text-n-slate-11"
            data-test-id="account-link-grants-empty"
          >
            {{ t('ACCOUNT_LINK.GRANTS.EMPTY') }}
          </p>

          <ul
            v-else
            class="flex flex-col gap-2"
            data-test-id="account-link-grants"
          >
            <li
              v-for="grant in grants"
              :key="grant.platform_app_id"
              class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3"
            >
              <div class="flex flex-col gap-0.5">
                <span class="text-body-main text-n-slate-12">
                  {{ grant.platform_app_name }}
                </span>
                <span class="text-label-small text-n-slate-11">
                  {{
                    t('ACCOUNT_LINK.GRANTS.SINCE', {
                      date: formatDate(grant.granted_at),
                    })
                  }}
                </span>
                <span
                  v-if="grant.signs_in_as.length"
                  class="text-label-small text-n-slate-11"
                >
                  {{
                    t('ACCOUNT_LINK.GRANTS.SIGNS_IN_AS', {
                      people: grant.signs_in_as
                        .map(person => person.name)
                        .join(', '),
                    })
                  }}
                </span>
                <span v-else class="text-label-small text-n-slate-11">
                  {{ t('ACCOUNT_LINK.GRANTS.SIGNS_IN_AS_NOBODY') }}
                </span>
              </div>
              <Button
                :label="t('ACCOUNT_LINK.GRANTS.REVOKE')"
                variant="faded"
                color="ruby"
                size="xs"
                :is-loading="revokingAppId === grant.platform_app_id"
                :data-test-id="`account-link-revoke-${grant.platform_app_id}`"
                @click="askToRevoke(grant)"
              />
            </li>
          </ul>
        </div>
      </div>

      <Dialog
        ref="revokeDialogRef"
        type="alert"
        :title="t('ACCOUNT_LINK.GRANTS.CONFIRM_TITLE')"
        :description="
          t('ACCOUNT_LINK.GRANTS.CONFIRM', {
            app: grantToRevoke ? grantToRevoke.platform_app_name : '',
          })
        "
        :confirm-button-label="t('ACCOUNT_LINK.GRANTS.REVOKE')"
        :is-loading="revokingAppId !== null"
        @confirm="confirmRevoke"
      />
    </template>
  </SettingsLayout>
</template>
