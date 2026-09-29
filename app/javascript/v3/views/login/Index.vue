<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';

export default {
  components: {
    FormInput,
    GoogleOAuthButton,
    Spinner,
    NextButton,
    SimpleDivider,
    MfaVerification,
    Icon,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    currentYear() {
      return new Date().getFullYear();
    },
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.authError) {
      const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
      const translatedMessage = this.getTranslatedMessage(messageKey);
      useAlert(translatedMessage);
      this.requestIdleCallbackPolyfill(() => {
        const { query } = this.$route;
        this.$router.replace({ query: { ...query, error: undefined } });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.SAML.API.ERROR_MESSAGE':
          return this.$t('LOGIN.SAML.API.ERROR_MESSAGE');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
            this.loginApi.showLoading = false;
            this.$router.push({
              name: 'auth_verify_email',
              state: { email: credentials.email },
            });
            return;
          }

          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified() {
      this.handleImpersonation();
      window.location = '/app';
    },
    handleMfaCancel() {
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <main class="auth-page">
    <!-- Left branding panel -->
    <section class="auth-visual">
      <div class="auth-visual-grid" />
      <div class="auth-glow auth-glow-one" />
      <div class="auth-glow auth-glow-two" />

      <div class="visual-top">
        <span class="visual-badge">
          {{ $t('LOGIN.BRAND_PANEL.BADGE') }}
        </span>
      </div>

      <div class="visual-content">
        <p class="visual-eyebrow">{{ globalConfig.installationName }}</p>

        <h1>
          {{ $t('LOGIN.BRAND_PANEL.HEADLINE') }}
          <span>{{ $t('LOGIN.BRAND_PANEL.HEADLINE_HIGHLIGHT') }}</span>
        </h1>

        <p class="visual-description">
          {{ $t('LOGIN.BRAND_PANEL.DESCRIPTION') }}
        </p>

        <div class="visual-points">
          <div class="visual-point">
            <span class="point-dot" />
            <span>{{ $t('LOGIN.BRAND_PANEL.POINT_FAST') }}</span>
          </div>

          <div class="visual-point">
            <span class="point-dot" />
            <span>{{ $t('LOGIN.BRAND_PANEL.POINT_ONE_PLACE') }}</span>
          </div>

          <div class="visual-point">
            <span class="point-dot" />
            <span>{{ $t('LOGIN.BRAND_PANEL.POINT_MODERN') }}</span>
          </div>
        </div>
      </div>

      <div class="visual-footer">
        <span>
          {{
            $t('LOGIN.BRAND_PANEL.COPYRIGHT', {
              year: currentYear,
              name: globalConfig.installationName,
            })
          }}
        </span>

        <div class="visual-footer-links">
          <a
            :href="globalConfig.privacyURL"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ $t('LOGIN.BRAND_PANEL.PRIVACY') }}
          </a>
          <a
            :href="globalConfig.termsURL"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ $t('LOGIN.BRAND_PANEL.TERMS') }}
          </a>
        </div>
      </div>
    </section>

    <!-- Right login panel -->
    <section class="auth-panel">
      <div class="auth-container">
        <div class="auth-logo-wrap">
          <div class="auth-logo-box">
            <img
              :src="globalConfig.logo"
              :alt="globalConfig.installationName"
              class="auth-logo"
            />
          </div>
        </div>

        <!-- MFA -->
        <div v-if="mfaRequired" class="auth-card">
          <MfaVerification
            :mfa-token="mfaToken"
            @verified="handleMfaVerified"
            @cancel="handleMfaCancel"
          />
        </div>

        <!-- Login -->
        <div
          v-else
          class="auth-card"
          :class="{
            'auth-card-error': loginApi.hasErrored,
          }"
        >
          <div class="auth-heading">
            <h2>{{ replaceInstallationName($t('LOGIN.TITLE')) }}</h2>
            <p>
              {{
                $t('LOGIN.SUBTITLE', { name: globalConfig.installationName })
              }}
            </p>
          </div>

          <div v-if="!email">
            <div class="flex flex-col gap-4 mb-4">
              <GoogleOAuthButton v-if="showGoogleOAuth" />
              <div v-if="showSamlLogin" class="text-center">
                <router-link
                  to="/app/login/sso"
                  class="inline-flex justify-center w-full px-4 py-3 items-center bg-n-background dark:bg-n-solid-3 rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
                >
                  <Icon
                    icon="i-lucide-lock-keyhole"
                    class="size-5 text-n-slate-11"
                  />
                  <span class="ml-2 text-base font-medium text-n-slate-12">
                    {{ $t('LOGIN.SAML.LABEL') }}
                  </span>
                </router-link>
              </div>
              <SimpleDivider
                v-if="showGoogleOAuth || showSamlLogin"
                :label="$t('COMMON.OR')"
                class="uppercase"
              />
            </div>

            <form class="auth-form" @submit.prevent="submitFormLogin">
              <FormInput
                v-model="credentials.email"
                name="email_address"
                type="text"
                data-testid="email_input"
                :tabindex="1"
                required
                :label="$t('LOGIN.EMAIL.LABEL')"
                :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
                :has-error="v$.credentials.email.$error"
                @input="v$.credentials.email.$touch"
              />

              <FormInput
                v-model="credentials.password"
                type="password"
                name="password"
                data-testid="password_input"
                required
                :tabindex="2"
                :label="$t('LOGIN.PASSWORD.LABEL')"
                :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
                :has-error="v$.credentials.password.$error"
                @input="v$.credentials.password.$touch"
              >
                <p
                  v-if="!globalConfig.disableUserProfileUpdate"
                  class="forgot-row"
                >
                  <router-link
                    to="auth/reset/password"
                    tabindex="4"
                    class="forgot-link"
                  >
                    {{ $t('LOGIN.FORGOT_PASSWORD') }}
                  </router-link>
                </p>
              </FormInput>

              <NextButton
                lg
                type="submit"
                data-testid="submit_button"
                class="login-button"
                :tabindex="3"
                :label="$t('LOGIN.SUBMIT')"
                :disabled="loginApi.showLoading"
                :is-loading="loginApi.showLoading"
              />
            </form>

            <div v-if="showSignupLink" class="register-section">
              <span>{{ $t('COMMON.OR') }}</span>
              <router-link to="auth/signup" class="register-link">
                {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
              </router-link>
            </div>
          </div>

          <div v-else class="loading-area">
            <Spinner color-scheme="primary" size="" />
          </div>
        </div>

        <div class="mobile-footer">
          <a
            :href="globalConfig.privacyURL"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ $t('LOGIN.BRAND_PANEL.PRIVACY') }}
          </a>
          <span>&bull;</span>
          <a
            :href="globalConfig.termsURL"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ $t('LOGIN.BRAND_PANEL.TERMS') }}
          </a>
        </div>
      </div>
    </section>
  </main>
</template>

<style>
/* Lynomia custom login page styles */
html,
body,
#app {
  min-height: 100%;
}

body {
  margin: 0;
  background: #08111f;
}

.auth-page {
  width: 100%;
  min-height: 100vh;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  background: #ffffff;
}

/* =========================
   LEFT BRANDING SIDE
   ========================= */

.auth-visual {
  position: relative;
  min-height: 100vh;
  overflow: hidden;

  display: flex;
  flex-direction: column;
  justify-content: space-between;

  padding: 56px 64px 48px;

  color: #ffffff;

  background: radial-gradient(
      circle at 10% 5%,
      rgba(69, 126, 255, 0.36),
      transparent 35%
    ),
    radial-gradient(circle at 95% 85%, rgba(32, 87, 181, 0.42), transparent 38%),
    linear-gradient(145deg, #071322 0%, #0a1e39 44%, #103a6f 100%);
}

.auth-visual-grid {
  position: absolute;
  inset: 0;
  pointer-events: none;

  background-image: linear-gradient(
      rgba(255, 255, 255, 0.025) 1px,
      transparent 1px
    ),
    linear-gradient(90deg, rgba(255, 255, 255, 0.025) 1px, transparent 1px);

  background-size: 58px 58px;

  mask-image: linear-gradient(
    to bottom,
    rgba(0, 0, 0, 0.8),
    rgba(0, 0, 0, 0.12)
  );
}

.auth-glow {
  position: absolute;
  border-radius: 50%;
  pointer-events: none;
  filter: blur(2px);
}

.auth-glow-one {
  width: 420px;
  height: 420px;
  top: 14%;
  right: -230px;

  border: 1px solid rgba(255, 255, 255, 0.08);

  box-shadow: 0 0 120px rgba(68, 132, 255, 0.11);
}

.auth-glow-two {
  width: 220px;
  height: 220px;
  left: -100px;
  bottom: 15%;

  border: 1px solid rgba(255, 255, 255, 0.05);
}

.visual-top,
.visual-content,
.visual-footer {
  position: relative;
  z-index: 2;
}

.visual-top {
  display: flex;
  align-items: center;
}

.visual-badge {
  display: inline-flex;
  align-items: center;

  padding: 8px 14px;

  color: rgba(255, 255, 255, 0.72);

  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.02em;

  background: rgba(255, 255, 255, 0.055);

  border: 1px solid rgba(255, 255, 255, 0.1);

  border-radius: 999px;

  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
}

.visual-content {
  max-width: 560px;
  margin: auto 0;
}

.visual-eyebrow {
  margin: 0 0 22px;

  color: #84adff;

  font-size: 11px;
  line-height: 1;
  font-weight: 700;
  letter-spacing: 0.19em;
}

.visual-content h1 {
  max-width: 620px;

  margin: 0;

  color: #ffffff;

  font-size: clamp(3.1rem, 5.1vw, 5.8rem);
  line-height: 0.99;

  font-weight: 500;
  letter-spacing: -0.06em;
}

.visual-content h1 span {
  display: block;

  color: #db2777;
}

.visual-description {
  max-width: 480px;

  margin: 30px 0 0;

  color: rgba(255, 255, 255, 0.58);

  font-size: 15px;
  line-height: 1.75;
}

.visual-points {
  display: flex;
  flex-direction: column;

  gap: 12px;

  margin-top: 34px;
}

.visual-point {
  display: flex;
  align-items: center;

  gap: 11px;

  color: rgba(255, 255, 255, 0.72);

  font-size: 13px;
}

.point-dot {
  width: 6px;
  height: 6px;

  flex: 0 0 6px;

  border-radius: 50%;

  background: #76a7ff;

  box-shadow: 0 0 0 4px rgba(118, 167, 255, 0.08);
}

.visual-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;

  color: rgba(255, 255, 255, 0.33);

  font-size: 11px;
}

.visual-footer-links {
  display: flex;
  align-items: center;

  gap: 20px;
}

.visual-footer a {
  color: rgba(255, 255, 255, 0.38);
  text-decoration: none;

  transition: color 0.2s ease;
}

.visual-footer a:hover {
  color: rgba(255, 255, 255, 0.82);
}

/* =========================
   RIGHT LOGIN SIDE
   ========================= */

.auth-panel {
  min-height: 100vh;

  display: flex;
  align-items: center;
  justify-content: center;

  padding: 56px;

  background: radial-gradient(
      circle at 100% 0%,
      rgba(50, 113, 234, 0.055),
      transparent 31%
    ),
    linear-gradient(180deg, #ffffff 0%, #fbfcfe 100%);
}

.auth-container {
  width: 100%;
  max-width: 430px;
}

.auth-logo-wrap {
  display: flex;
  justify-content: center;

  margin-bottom: 36px;
}

.auth-logo-box {
  min-width: 210px;
  min-height: 66px;
  border-radius: 7px;
  transform: skewX(-5deg);
  display: flex;
  align-items: center;
  justify-content: center;

  padding: 12px 24px;

  background: white;

  border: 1px solid rgba(17, 24, 39, 0.08);

  border-radius: 16px;

  box-shadow:
    0 10px 30px rgba(15, 31, 57, 0.12),
    inset 0 1px 0 rgba(255, 255, 255, 0.08);
}

.auth-logo {
  display: block;
  width: 265px;
  max-height: 80px;
  object-fit: contain;
}

.auth-card {
  width: 100%;
}

.auth-card-error {
  animation: auth-shake 0.38s ease;
}

@keyframes auth-shake {
  0%,
  100% {
    transform: translateX(0);
  }

  25% {
    transform: translateX(-5px);
  }

  75% {
    transform: translateX(5px);
  }
}

.auth-heading {
  margin-bottom: 32px;
  text-align: center;
}

.auth-heading h2 {
  margin: 0;

  color: #111827;

  font-size: 31px;
  line-height: 1.18;

  font-weight: 650;
  letter-spacing: -0.035em;
}

.auth-heading p {
  margin: 10px 0 0;

  color: #7a8494;

  font-size: 14px;
  line-height: 1.6;
}

.auth-form {
  display: flex;
  flex-direction: column;

  gap: 18px;
}

/* Login form only: the MFA card has its own light/dark colours */
.auth-form label {
  color: #344054 !important;

  font-size: 13px !important;
  font-weight: 500 !important;
}

.auth-card input {
  min-height: 50px;

  color: #101828 !important;

  background: #ffffff !important;

  border: 1px solid #d7dce5 !important;

  border-radius: 12px !important;

  box-shadow: 0 1px 2px rgba(16, 24, 40, 0.03) !important;

  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    background 0.2s ease !important;
}

.auth-card input::placeholder {
  color: #a1a8b4 !important;
}

.auth-card input:hover {
  border-color: #c1c8d3 !important;
}

.auth-card input:focus {
  background: #ffffff !important;

  border-color: #397cf6 !important;

  box-shadow: 0 0 0 4px rgba(57, 124, 246, 0.1) !important;
}

.forgot-row {
  display: flex;
  justify-content: flex-end;

  margin-top: -7px;
}

.forgot-link {
  color: #397cf6 !important;

  font-size: 13px;
  font-weight: 550;

  text-decoration: none;

  transition: color 0.2s ease;
}

.forgot-link:hover {
  color: #1e5ed4 !important;
}

.login-button {
  width: 100%;

  min-height: 50px;

  margin-top: 3px;

  border-radius: 12px !important;
  background: #db2777;
}

.auth-card [data-testid='submit_button'] {
  min-height: 50px;

  color: #ffffff !important;

  background: linear-gradient(
    135deg,
    #ef5da0 0%,
    #db2777 55%,
    #9d1c57 100%
  ) !important;

  border: none !important;

  border-radius: 12px !important;

  box-shadow: 0 8px 20px rgba(35, 95, 211, 0.2);

  transition:
    transform 0.2s ease,
    box-shadow 0.2s ease,
    filter 0.2s ease;
}

.auth-card [data-testid='submit_button']:hover {
  transform: translateY(-1px);

  filter: brightness(1.03);

  box-shadow: 0 12px 26px rgba(35, 95, 211, 0.27);
}

.register-section {
  display: flex;
  align-items: center;
  justify-content: center;

  gap: 6px;

  margin-top: 30px;
  padding-top: 25px;

  border-top: 1px solid #eceff4;

  color: #7a8494;

  font-size: 13px;
}

.register-link {
  color: #397cf6 !important;

  font-weight: 600;

  text-decoration: none;

  transition: color 0.2s ease;
}

.register-link:hover {
  color: #1e5ed4 !important;
}

.loading-area {
  min-height: 220px;

  display: flex;
  align-items: center;
  justify-content: center;
}

.mobile-footer {
  display: none;
}

/* =========================
   RESPONSIVE
   ========================= */

@media (max-width: 1100px) {
  .auth-visual {
    padding: 48px 44px 42px;
  }

  .auth-panel {
    padding: 48px 38px;
  }

  .visual-content h1 {
    font-size: clamp(3rem, 5.2vw, 4.5rem);
  }
}

@media (max-width: 900px) {
  .auth-page {
    display: block;
  }

  .auth-visual {
    display: none;
  }

  .auth-panel {
    min-height: 100vh;

    padding: 46px 24px 32px;
  }

  .auth-container {
    max-width: 440px;
  }

  .mobile-footer {
    display: flex;
    align-items: center;
    justify-content: center;

    gap: 10px;

    margin-top: 38px;

    color: #c2c7d0;

    font-size: 11px;
  }

  .mobile-footer a {
    color: #929baa !important;
    text-decoration: none;
  }
}

@media (max-width: 480px) {
  .auth-panel {
    padding: 30px 20px 28px;
  }

  .auth-logo-wrap {
    margin-bottom: 30px;
  }

  .auth-logo-box {
    min-width: 190px;
    min-height: 60px;

    padding: 11px 20px;

    border-radius: 14px;
  }

  .auth-logo {
    width: 150px;
  }

  .auth-heading {
    margin-bottom: 27px;
  }

  .auth-heading h2 {
    font-size: 27px;
  }

  .register-section {
    flex-wrap: wrap;
  }
}
</style>
