<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';

import NextButton from 'dashboard/components-next/button/Button.vue';

const shouldStartWithPlusSign = (value = '') => value.startsWith('+');

export default {
  components: {
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      accountId: '',
      apiKey: '',
      apiSecret: '',
      applicationId: '',
      inboxName: '',
      phoneNumber: '',
      callbackUsername: '',
      callbackPassword: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
  },
  validations: {
    inboxName: { required },
    phoneNumber: { required, shouldStartWithPlusSign },
    apiKey: { required },
    apiSecret: { required },
    applicationId: { required },
    accountId: { required },
    // Basic auth is the only authentication Bandwidth offers for callbacks, and the webhook now fails closed
    // without it (docs/p11/00-p10-security-closure.md), so these are required rather than optional.
    callbackUsername: { required },
    callbackPassword: { required },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const smsChannel = await this.$store.dispatch('inboxes/createChannel', {
          name: this.inboxName?.trim(),
          channel: {
            type: 'sms',
            phone_number: this.phoneNumber,
            provider_config: {
              api_key: this.apiKey,
              api_secret: this.apiSecret,
              application_id: this.applicationId,
              account_id: this.accountId,
              callback_username: this.callbackUsername,
              callback_password: this.callbackPassword,
            },
          },
        });

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: smsChannel.id,
          },
        });
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.ADD.SMS.API.ERROR_MESSAGE'));
      }
    },
  },
};
</script>

<template>
  <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel()">
    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.INBOX_NAME.PLACEHOLDER')
          "
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.INBOX_NAME.ERROR')
        }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.PHONE_NUMBER.PLACEHOLDER')
          "
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.PHONE_NUMBER.ERROR')
        }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.accountId.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.ACCOUNT_ID.LABEL') }}
        <input
          v-model="accountId"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.ACCOUNT_ID.PLACEHOLDER')
          "
          @blur="v$.accountId.$touch"
        />
        <span v-if="v$.accountId.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.ACCOUNT_ID.ERROR')
        }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.applicationId.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.APPLICATION_ID.LABEL') }}
        <input
          v-model="applicationId"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.APPLICATION_ID.PLACEHOLDER')
          "
          @blur="v$.applicationId.$touch"
        />
        <span v-if="v$.applicationId.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.APPLICATION_ID.ERROR')
        }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.apiKey.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.API_KEY.LABEL') }}
        <input
          v-model="apiKey"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.SMS.BANDWIDTH.API_KEY.PLACEHOLDER')"
          @blur="v$.apiKey.$touch"
        />
        <span v-if="v$.apiKey.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.API_KEY.ERROR')
        }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.apiSecret.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.API_SECRET.LABEL') }}
        <input
          v-model="apiSecret"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.API_SECRET.PLACEHOLDER')
          "
          @blur="v$.apiSecret.$touch"
        />
        <span v-if="v$.apiSecret.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.API_SECRET.ERROR')
        }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.callbackUsername.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.CALLBACK_USERNAME.LABEL') }}
        <input
          v-model="callbackUsername"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.CALLBACK_USERNAME.PLACEHOLDER')
          "
          @blur="v$.callbackUsername.$touch"
        />
        <span v-if="v$.callbackUsername.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.CALLBACK_USERNAME.ERROR')
        }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.callbackPassword.$error }">
        {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.CALLBACK_PASSWORD.LABEL') }}
        <input
          v-model="callbackPassword"
          type="password"
          :placeholder="
            $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.CALLBACK_PASSWORD.PLACEHOLDER')
          "
          @blur="v$.callbackPassword.$touch"
        />
        <span v-if="v$.callbackPassword.$error" class="message">{{
          $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.CALLBACK_PASSWORD.ERROR')
        }}</span>
      </label>
    </div>

    <p class="mb-0 text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.ADD.SMS.BANDWIDTH.CALLBACK_HELP') }}
    </p>

    <div class="w-full mt-4">
      <NextButton
        :is-loading="uiFlags.isCreating"
        type="submit"
        solid
        blue
        :label="$t('INBOX_MGMT.ADD.SMS.BANDWIDTH.SUBMIT_BUTTON')"
      />
    </div>
  </form>
</template>
