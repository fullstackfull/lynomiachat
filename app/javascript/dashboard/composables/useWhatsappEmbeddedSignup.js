import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
  isValidBusinessData,
  classifySignupEvent,
  SIGNUP_RESULT,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';

// Drives Meta's WhatsApp embedded-signup popup (Facebook JS SDK). FB.login()
// resolves an auth `code` while the WABA identifiers (waba_id, phone_number_id)
// arrive separately over a postMessage event — order isn't guaranteed, so we
// hold both and resolve once both are present.
//
// `runEmbeddedSignup` returns the signup credentials; the caller exchanges them
// for an inbox via `inboxes/createWhatsAppEmbeddedSignup` and owns its own UX
// (alerts, navigation, etc). Resolves `null` when the user cancels the popup;
// rejects on SDK load errors, signup errors, and completions that yield no usable
// phone number. The window listener is scoped to a single run, so this is safe to
// call from anywhere without lifecycle wiring.
export function useWhatsappEmbeddedSignup() {
  const { t } = useI18n();
  const isAuthenticating = ref(false);

  const runEmbeddedSignup = () => {
    if (isAuthenticating.value) return Promise.resolve(null);

    // NO FB.login WITHOUT A CONFIGURATION.
    //
    // This path used to pass window.chatwootConfig values straight into FB.login, so a missing or blank
    // configuration id meant `config_id: undefined` went to Meta and came back as an opaque "Login cancelled"
    // -- indistinguishable from the user closing the popup, with nothing for an operator to act on. The
    // reauthorize flow already refuses both missing values with these exact strings
    // (channels/whatsapp/Reauthorize.vue:208-213, :283-288), so this reuses that source and those semantics
    // rather than inventing either. The `'none'` sentinel counts as missing, which is how
    // onboarding/inbox-setup/useChannelConfig.js:26-28 already reads it. Neither message echoes a value.
    const { whatsappAppId, whatsappConfigurationId } =
      window.chatwootConfig ?? {};
    if (!whatsappAppId || whatsappAppId === 'none') {
      return Promise.reject(
        new Error(t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_APP_ID_MISSING'))
      );
    }
    if (!whatsappConfigurationId) {
      return Promise.reject(
        new Error(t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_CONFIG_ID_MISSING'))
      );
    }

    isAuthenticating.value = true;

    return new Promise((resolve, reject) => {
      let authCode = null;
      let businessData = null;
      let isCoexistence = false;
      let settled = false;
      let messageHandler;

      const settle = (fn, value) => {
        if (settled) return;
        settled = true;
        window.removeEventListener('message', messageHandler);
        isAuthenticating.value = false;
        fn(value);
      };

      // Both the auth code and the business data arrive asynchronously and in
      // no fixed order; only resolve once we're holding both.
      const resolveIfReady = () => {
        if (!authCode || !businessData) return;
        settle(resolve, {
          code: authCode,
          business_id: businessData.business_id || '',
          waba_id: businessData.waba_id,
          phone_number_id: businessData.phone_number_id || '',
          is_coexistence: isCoexistence,
        });
      };

      messageHandler = createMessageHandler(data => {
        const result = classifySignupEvent(data);

        if (result.type === SIGNUP_RESULT.FINISH) {
          // Keep the first terminal event: a coexistence FINISH must win over a
          // later normal FINISH that can arrive before the auth code is known.
          if (businessData) return;
          if (!isValidBusinessData(data.data)) {
            const invalidData = t(
              'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.INVALID_BUSINESS_DATA'
            );
            settle(reject, new Error(invalidData));
            return;
          }
          businessData = data.data;
          isCoexistence = result.isCoexistence;
          resolveIfReady();
        } else if (result.type === SIGNUP_RESULT.UNSUPPORTED) {
          const unsupported = t(
            'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.UNSUPPORTED_COMPLETION'
          );
          settle(reject, new Error(unsupported));
        } else if (result.type === SIGNUP_RESULT.CANCEL) {
          settle(resolve, null);
        } else if (result.type === SIGNUP_RESULT.ERROR) {
          const signupError = t(
            'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SIGNUP_ERROR'
          );
          settle(reject, new Error(result.errorMessage || signupError));
        }
      });

      window.addEventListener('message', messageHandler);

      (async () => {
        try {
          await setupFacebookSdk(
            whatsappAppId,
            window.chatwootConfig?.whatsappApiVersion
          );
          authCode = await initWhatsAppEmbeddedSignup(whatsappConfigurationId);
          resolveIfReady();
        } catch (error) {
          // FB.login() rejects with 'Login cancelled' when the user dismisses
          // the popup — treat it as a cancel rather than an error.
          if (error.message === 'Login cancelled') {
            settle(resolve, null);
          } else {
            settle(reject, error);
          }
        }
      })();
    });
  };

  return { isAuthenticating, runEmbeddedSignup };
}
