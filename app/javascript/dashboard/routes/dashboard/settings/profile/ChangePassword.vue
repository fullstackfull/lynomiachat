<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      currentPassword: '',
      password: '',
      passwordConfirmation: '',
      isPasswordChanging: false,
      errorMessage: '',
    };
  },
  validations: {
    currentPassword: {
      required,
    },
    password: {
      minLength: minLength(6),
    },
    passwordConfirmation: {
      minLength: minLength(6),
      isEqPassword(value) {
        if (value !== this.password) {
          return false;
        }
        return true;
      },
    },
  },
  computed: {
    isButtonDisabled() {
      return (
        !this.currentPassword ||
        !this.passwordConfirmation ||
        !this.v$.passwordConfirmation.isEqPassword
      );
    },
  },
  methods: {
    async changePassword() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('PROFILE_SETTINGS.FORM.ERROR'));
        return;
      }
      let alertMessage = this.$t('PROFILE_SETTINGS.PASSWORD_UPDATE_SUCCESS');
      try {
        await this.$store.dispatch('updatePassword', {
          password: this.password,
          passwordConfirmation: this.passwordConfirmation,
          currentPassword: this.currentPassword,
        });
      } catch (error) {
        alertMessage =
          parseAPIErrorResponse(error) ||
          this.$t('RESET_PASSWORD.API.ERROR_MESSAGE');
      } finally {
        useAlert(alertMessage);
      }
    },
  },
};
</script>

<template>
  <form @submit.prevent="changePassword()">
    <div class="flex flex-col w-full gap-4">
      <woot-input
        v-model="currentPassword"
        type="password"
        class="[&>input]:!rounded-xl [&>input]:!px-3 [&>input]:!py-1.5 [&>input]:!text-sm [&>input]:!mb-0.5"
        :class="{ error: v$.currentPassword.$error }"
        :label="$t('PROFILE_SETTINGS.FORM.CURRENT_PASSWORD.LABEL')"
        :placeholder="$t('PROFILE_SETTINGS.FORM.CURRENT_PASSWORD.PLACEHOLDER')"
        :error="`${
          v$.currentPassword.$error
            ? $t('PROFILE_SETTINGS.FORM.CURRENT_PASSWORD.ERROR')
            : ''
        }`"
        @input="v$.currentPassword.$touch"
        @blur="v$.currentPassword.$touch"
      />

      <woot-input
        v-model="password"
        type="password"
        class="[&>input]:!rounded-xl [&>input]:!px-3 [&>input]:!py-1.5 [&>input]:!text-sm [&>input]:!mb-0.5"
        :class="{ error: v$.password.$error }"
        :label="$t('PROFILE_SETTINGS.FORM.PASSWORD.LABEL')"
        :placeholder="$t('PROFILE_SETTINGS.FORM.PASSWORD.PLACEHOLDER')"
        :error="`${
          v$.password.$error ? $t('PROFILE_SETTINGS.FORM.PASSWORD.ERROR') : ''
        }`"
        @input="v$.password.$touch"
        @blur="v$.password.$touch"
      />

      <woot-input
        v-model="passwordConfirmation"
        type="password"
        class="[&>input]:!rounded-xl [&>input]:!px-3 [&>input]:!py-1.5 [&>input]:!text-sm [&>input]:!mb-0.5"
        :class="{ error: v$.passwordConfirmation.$error }"
        :label="$t('PROFILE_SETTINGS.FORM.PASSWORD_CONFIRMATION.LABEL')"
        :placeholder="
          $t('PROFILE_SETTINGS.FORM.PASSWORD_CONFIRMATION.PLACEHOLDER')
        "
        :error="`${
          v$.passwordConfirmation.$error
            ? $t('PROFILE_SETTINGS.FORM.PASSWORD_CONFIRMATION.ERROR')
            : ''
        }`"
        @input="v$.passwordConfirmation.$touch"
        @blur="v$.passwordConfirmation.$touch"
      />

      <div>
        <NextButton
          type="submit"
          :label="$t('PROFILE_SETTINGS.FORM.PASSWORD_SECTION.BTN_TEXT')"
          :disabled="isButtonDisabled"
        />
      </div>
    </div>
  </form>
</template>
