<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n, I18nT } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';
import Banner from 'next/banner/Banner.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import InboxesAPI from 'dashboard/api/inboxes';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import globalConstants from 'dashboard/constants/globals.js';
import { useBranding } from 'shared/composables/useBranding';

const props = defineProps({
  enableCallingOnComplete: {
    type: Boolean,
    default: false,
  },
  isDisabled: {
    type: Boolean,
    default: false,
  },
  showRestrictionAlert: {
    type: Boolean,
    default: false,
  },
  restrictionStatusUrl: {
    type: String,
    default: '',
  },
  // Lynomia: 'business_app' shows the "WhatsApp Business" (existing WhatsApp Business App /
  // Coexistence) copy. The Meta flow and the API call are identical for both variants.
  variant: {
    type: String,
    default: 'default',
    validator: value => ['default', 'business_app'].includes(value),
  },
});

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { isAuthenticating, runEmbeddedSignup } = useWhatsappEmbeddedSignup();

const isProcessing = ref(false);
const processingMessage = ref('');

const { replaceInstallationName } = useBranding();
const isBusinessApp = computed(() => props.variant === 'business_app');

const defaultBenefits = computed(() => [
  {
    key: 'EASY_SETUP',
    text: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BENEFITS.EASY_SETUP'),
  },
  {
    key: 'SECURE_AUTH',
    text: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BENEFITS.SECURE_AUTH'),
  },
  {
    key: 'AUTO_CONFIG',
    text: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BENEFITS.AUTO_CONFIG'),
  },
]);

const businessAppBenefits = computed(() => [
  {
    key: 'KEEP_APP',
    text: replaceInstallationName(
      t(
        'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.BENEFITS.KEEP_APP'
      )
    ),
  },
  {
    key: 'SYNC',
    text: replaceInstallationName(
      t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.BENEFITS.SYNC')
    ),
  },
  {
    key: 'OFFICIAL',
    text: replaceInstallationName(
      t(
        'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.BENEFITS.OFFICIAL'
      )
    ),
  },
]);

const benefits = computed(() =>
  isBusinessApp.value ? businessAppBenefits.value : defaultBenefits.value
);

const copy = computed(() => {
  if (!isBusinessApp.value) {
    return {
      title: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.TITLE'),
      description: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.DESC'),
      submit: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SUBMIT_BUTTON'),
    };
  }
  return {
    title: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.TITLE'),
    description: replaceInstallationName(
      t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.DESC')
    ),
    submit: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.SUBMIT'),
  };
});

const showLoader = computed(() => isAuthenticating.value || isProcessing.value);

const enableCallingForInbox = async inboxId => {
  try {
    await InboxesAPI.enableWhatsappCalling(inboxId);
  } catch (_) {
    useAlert(
      t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CALLING_ENABLE_FAILED')
    );
  }
};

const handleSignupSuccess = async inboxData => {
  if (inboxData && inboxData.id) {
    if (props.enableCallingOnComplete) {
      processingMessage.value = t(
        'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.ENABLING_CALLING'
      );
      await enableCallingForInbox(inboxData.id);
    }
    isProcessing.value = false;
    useAlert(t('INBOX_MGMT.FINISH.MESSAGE'));
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        page: 'new',
        inbox_id: inboxData.id,
      },
    });
  } else {
    isProcessing.value = false;
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SUCCESS_FALLBACK'));
    router.replace({
      name: 'settings_inbox_list',
    });
  }
};

const launchEmbeddedSignup = async () => {
  if (props.isDisabled) return;

  let credentials;
  try {
    credentials = await runEmbeddedSignup();
  } catch (error) {
    useAlert(
      error.message ||
        t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SDK_LOAD_ERROR')
    );
    return;
  }

  // Resolves null when the user dismisses the Meta popup.
  if (!credentials) {
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'));
    return;
  }

  isProcessing.value = true;
  processingMessage.value = t(
    'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.PROCESSING'
  );
  try {
    const inboxData = await store.dispatch(
      'inboxes/createWhatsAppEmbeddedSignup',
      credentials
    );
    await handleSignupSuccess(inboxData);
  } catch (error) {
    isProcessing.value = false;
    useAlert(
      parseAPIErrorResponse(error) ||
        t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
    );
  }
};
</script>

<template>
  <div class="h-full">
    <LoadingState v-if="showLoader" :message="processingMessage" />

    <div v-else>
      <div class="flex flex-col items-start mb-6 text-start">
        <div class="flex justify-start mb-6">
          <div
            class="flex size-11 items-center justify-center rounded-full bg-n-alpha-2"
          >
            <Icon icon="i-woot-whatsapp" class="text-n-slate-10 size-6" />
          </div>
        </div>

        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{ copy.title }}
        </h3>
        <p class="text-sm leading-[24px] text-n-slate-12">
          {{ copy.description }}
        </p>
      </div>

      <div class="flex flex-col gap-2 mb-6">
        <div
          v-for="benefit in benefits"
          :key="benefit.key"
          class="flex gap-2 items-center text-sm text-n-slate-11"
        >
          <Icon icon="i-lucide-check" class="text-n-slate-11 size-4" />
          {{ benefit.text }}
        </div>
      </div>

      <p v-if="isBusinessApp" class="mb-6 text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.NOTE') }}
      </p>

      <div class="flex flex-col gap-2 mb-6">
        <I18nT
          keypath="INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.LEARN_MORE.TEXT"
          tag="span"
          class="text-sm text-n-slate-11"
        >
          <template #link>
            <a
              :href="globalConstants.WHATSAPP_EMBEDDED_SIGNUP_DOCS_URL"
              target="_blank"
              rel="noopener noreferrer"
              class="underline text-n-brand"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.LEARN_MORE.LINK_TEXT'
                )
              }}
            </a>
          </template>
        </I18nT>
      </div>

      <Banner v-if="showRestrictionAlert" color="amber" class="w-full mb-6">
        <div class="flex items-start gap-3 text-start">
          <Icon
            icon="i-lucide-triangle-alert"
            class="flex-shrink-0 size-4 mt-0.5"
          />
          <span>
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.RESTRICTED_WARNING')
            }}
            <a
              v-if="restrictionStatusUrl"
              :href="restrictionStatusUrl"
              class="link underline"
              rel="noopener noreferrer nofollow"
              target="_blank"
            >
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.STATUS_LINK') }}
            </a>
          </span>
        </div>
      </Banner>

      <div class="flex mt-4">
        <NextButton
          :disabled="isAuthenticating || isDisabled"
          :is-loading="isAuthenticating"
          faded
          slate
          class="w-full"
          @click="launchEmbeddedSignup"
        >
          {{ copy.submit }}
        </NextButton>
      </div>
    </div>
  </div>
</template>
