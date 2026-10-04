<script setup>
import { ref, computed, watch } from 'vue';
import parsePhoneNumber from 'libphonenumber-js';
import { useI18n } from 'vue-i18n';
import countries from 'shared/constants/countries.js';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import {
  getActiveCountryCode,
  getActiveDialCode,
} from 'shared/components/PhoneInput/helper';
import {
  hasUnresolvedTrunkPrefix,
  stripPhoneFormatting,
  toE164,
} from 'shared/helpers/phoneNumber';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  placeholder: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  showBorder: {
    type: Boolean,
    default: true,
  },
  /** A validation message from outside the component, e.g. what the server said about this field. */
  errorMessage: {
    type: String,
    default: '',
  },
  /**
   * An ISO 3166-1 alpha-2 region the user chose for this contact, used to read a local number. The country
   * this component pre-fills from the browser timezone is deliberately not one: it is a visible default, not
   * a statement about the contact, and reading a trunk-prefixed number against it would be guessing.
   */
  regionCode: {
    type: String,
    default: '',
  },
});

const modelValue = defineModel({
  type: [String, Number],
  default: '',
});

const { t } = useI18n();

const showDropdown = ref(false);
const searchQuery = ref('');
const activeCountryCode = ref(getActiveCountryCode());
const activeDialCode = ref(getActiveDialCode());
const phoneNumber = ref('');
// Set only by the country picker and by parsing a number that already carries its own country — never by the
// timezone pre-fill.
const pickedRegion = ref('');
// What this component last wrote to the model. Normalizing can make the emitted number differ from what was
// typed ("0551112233" in SA becomes +966551112233), and without this the watcher below would write the
// normalized national part straight back into the field, moving the caret while someone is still typing.
const lastEmitted = ref(null);

const rules = {
  phoneNumber: {
    minLength: minLength(2),
    // Spaces, hyphens and parentheses are how people write phone numbers; they are stripped on the way out.
    formattedNumber: value => !value || /^[\d\s\u00a0()./+-]+$/.test(value),
  },
  activeDialCode: {
    required,
    validDialCode: value => {
      return countries.some(country => country.dial_code === value);
    },
  },
};

const v$ = useVuelidate(rules, {
  phoneNumber,
  activeDialCode,
});

/** The region a local number may be read against, or null when there is none and nothing may be assumed. */
const explicitRegion = computed(
  () => pickedRegion.value || props.regionCode || null
);

const hasError = computed(
  () => v$.value.$invalid || Boolean(props.errorMessage)
);

const countryList = computed(() => {
  return countries.map(country => ({
    value: country.id,
    label: country.name,
    dialCode: country.dial_code,
    emoji: country.emoji,
    isSelected: String(activeCountryCode.value) === String(country.id),
    action: 'phoneNumberInput',
  }));
});

const filteredCountries = computed(() => {
  const query = searchQuery.value.toLowerCase();
  return countryList.value.filter(({ label, dialCode, value }) =>
    [label, dialCode, value].some(field => field.toLowerCase().includes(query))
  );
});

const activeCountry = computed(() =>
  activeCountryCode.value
    ? countryList.value.find(
        country => country.value === activeCountryCode.value
      )
    : ''
);

const inputBorderClass = computed(() => {
  const errorClass =
    'outline-n-ruby-8 dark:outline-n-ruby-8 hover:outline-n-ruby-9 dark:hover:outline-n-ruby-9 disabled:outline-n-ruby-8 dark:disabled:outline-n-ruby-8';
  const focusClass =
    'has-[:focus]:outline-n-brand dark:has-[:focus]:outline-n-brand';

  if (!props.showBorder) {
    if (hasError.value) return errorClass;
    return `outline-transparent ${focusClass}`;
  }

  if (hasError.value) {
    return errorClass;
  }
  return `${focusClass} outline-n-weak dark:outline-n-weak hover:outline-n-slate-6 dark:hover:outline-n-slate-6 disabled:outline-n-weak dark:disabled:outline-n-weak`;
});

const phoneNumberError = computed(() => {
  if (props.errorMessage) return props.errorMessage;
  if (!v$.value.$dirty) return '';
  if (v$.value.activeDialCode.$invalid) return t('PHONE_INPUT.DIAL_CODE_ERROR');
  if (v$.value.phoneNumber.$invalid) return t('PHONE_INPUT.ERROR');
  // A trunk-prefixed number means something different in every country, so rather than prefix a dial code
  // onto the zero and store a number that does not exist, ask which country it is.
  if (hasUnresolvedTrunkPrefix(phoneNumber.value, explicitRegion.value)) {
    return t('CONTACT_ERRORS.PHONE_NUMBER.NEEDS_COUNTRY');
  }
  return '';
});

const emitPhoneNumber = value => {
  if (!value) {
    lastEmitted.value = '';
    modelValue.value = '';
    return;
  }

  const typed = stripPhoneFormatting(value);
  // A number pasted in international form carries its own country, which beats the picker.
  if (typed.startsWith('+')) {
    lastEmitted.value = toE164(typed) ?? typed;
    modelValue.value = lastEmitted.value;
    return;
  }

  // With a region the user actually chose, libphonenumber resolves the national prefix properly: "0551112233"
  // in SA is +966551112233, not +9660551112233. Without one, the dial code is still prefixed as before — the
  // server has the last word on whether that is a real number.
  lastEmitted.value =
    toE164(typed, explicitRegion.value) ?? `${activeDialCode.value}${typed}`;
  modelValue.value = lastEmitted.value;
};

const onSelectCountry = async ({ value, dialCode }) => {
  if (!value || !showDropdown.value) return;

  activeCountryCode.value = value;
  activeDialCode.value = dialCode;
  // Choosing from the picker is the explicit answer a local number needs.
  pickedRegion.value = value;
  searchQuery.value = '';
  showDropdown.value = false;
  if (!v$.value.$invalid && phoneNumber.value) {
    emitPhoneNumber(phoneNumber.value);
  }
};

const toggleCountryDropdown = () => {
  showDropdown.value = !showDropdown.value;
};

const closeCountryDropdown = () => {
  showDropdown.value = false;
};

watch(phoneNumber, async value => {
  await v$.value.$touch();
  if (!v$.value.$invalid) {
    emitPhoneNumber(value);
  }
});

watch(
  modelValue,
  newValue => {
    // Our own emit: the field already shows what the user typed, so leave it alone.
    if (newValue === lastEmitted.value) return;

    const number = parsePhoneNumber(newValue);
    if (number) {
      // A number that parses states its own country, so it answers the region question by itself.
      if (number?.country) pickedRegion.value = number.country;
      if (number?.country) activeCountryCode.value = number.country;
      if (number?.countryCallingCode)
        activeDialCode.value = `+${number.countryCallingCode}`;
      phoneNumber.value = newValue.replace(`+${number.countryCallingCode}`, '');
    }
  },
  { immediate: true }
);
</script>

<template>
  <div>
    <div
      v-on-clickaway="() => closeCountryDropdown()"
      class="relative flex items-center h-8 transition-all duration-500 ease-in-out outline outline-1 outline-offset-[-1px] rounded-lg bg-n-alpha-black2"
      :class="[inputBorderClass, { 'cursor-not-allowed opacity-50': disabled }]"
    >
      <Input
        v-model="phoneNumber"
        type="tel"
        :placeholder="placeholder"
        :disabled="disabled"
        custom-input-class="!border-0 !outline-none h-8 !py-0.5 !bg-transparent ltr:!pl-1 rtl:!pr-1"
        class="w-full !flex-row"
      >
        <template #prefix>
          <div class="flex items-center flex-shrink-0">
            <Button
              :label="activeCountry?.emoji || ''"
              color="slate"
              size="sm"
              :icon="
                !activeCountry ? 'i-lucide-globe' : 'i-lucide-chevron-down'
              "
              trailing-icon
              :disabled="disabled"
              type="button"
              class="!h-[1.875rem] top-1 ltr:ml-px rtl:mr-px !px-2 outline-0 !outline-none !rounded-lg border-0 ltr:!rounded-r-none rtl:!rounded-l-none"
              @click="toggleCountryDropdown"
            >
              <span
                v-if="activeCountry"
                class="inline-flex justify-center text-sm whitespace-nowrap"
              >
                {{ activeCountry?.emoji }}
              </span>
            </Button>
            <span
              v-if="activeCountry"
              class="text-sm start-[38px] top-2.5 text-n-slate-11 ltr:!pl-1 rtl:!pr-1"
            >
              {{ activeDialCode }}
            </span>
          </div>
        </template>
      </Input>
      <DropdownMenu
        v-if="showDropdown"
        :menu-items="filteredCountries"
        show-search
        class="z-[100] w-48 mt-2 ltr:left-0 rtl:right-0 top-full max-h-52"
        @action="onSelectCountry"
      />
    </div>
    <p
      v-if="phoneNumberError"
      class="min-w-0 mt-1 mb-0 text-xs whitespace-normal break-words transition-all duration-500 ease-in-out text-n-ruby-9 dark:text-n-ruby-9"
    >
      {{ phoneNumberError }}
    </p>
  </div>
</template>
