<script>
import validations from './validations';
import { useVuelidate } from '@vuelidate/core';

export default {
  props: {
    threshold: {
      type: Number,
      default: null,
    },
    thresholdUnit: {
      type: String,
      default: 'Minutes',
    },
    label: {
      type: String,
      default: '',
    },
    placeholder: {
      type: String,
      default: '',
    },
  },
  emits: ['unit', 'isInValid', 'updateThreshold'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      thresholdTime: this.threshold || '',
      thresholdUnitValue: this.thresholdUnit,
    };
  },
  validations,
  computed: {
    // The values are the API's own enum and stay as they are; only the words beside them are translated.
    options() {
      return [
        { value: 'Minutes', label: this.$t('SLA.FORM.UNITS.MINUTES') },
        { value: 'Hours', label: this.$t('SLA.FORM.UNITS.HOURS') },
        { value: 'Days', label: this.$t('SLA.FORM.UNITS.DAYS') },
      ];
    },
    thresholdTimeErrorMessage() {
      let errorMessage = '';
      if (this.v$.thresholdTime.$error) {
        if (!this.v$.thresholdTime.numeric || !this.v$.thresholdTime.minValue) {
          errorMessage = this.$t(
            'SLA.FORM.THRESHOLD_TIME.INVALID_FORMAT_ERROR'
          );
        }
      }
      return errorMessage;
    },
  },
  watch: {
    threshold: {
      immediate: true,
      handler(value) {
        if (!Number.isNaN(value)) {
          this.thresholdTime = value;
        }
      },
    },
    thresholdUnit: {
      immediate: true,
      handler(value) {
        this.thresholdUnitValue = value;
      },
    },
  },
  methods: {
    onThresholdUnitChange() {
      this.$emit('unit', this.thresholdUnitValue);
    },
    onThresholdTimeChange() {
      this.v$.thresholdTime.$touch();
      const isInvalid = this.v$.thresholdTime.$invalid;
      this.$emit('isInValid', isInvalid);
      this.$emit(
        'updateThreshold',
        this.thresholdTime ? Number(this.thresholdTime) : null
      );
    },
  },
};
</script>

<template>
  <div class="flex items-center w-full gap-3">
    <woot-input
      v-model="thresholdTime"
      type="number"
      :class="{ error: v$.thresholdTime.$error }"
      class="flex-grow [&>input]:!rounded-xl [&>input]:!px-3 [&>input]:!py-1.5 [&>input]:!text-sm [&>input]:!mb-0.5"
      :label="label"
      :placeholder="placeholder"
      :error="thresholdTimeErrorMessage"
      @update:model-value="onThresholdTimeChange"
    />
    <div class="self-end">
      <select
        v-model="thresholdUnitValue"
        class="ps-4 pe-7 py-1.5 min-w-[6.5rem] h-control-md text-sm font-medium border-0 rounded-xl hover:cursor-pointer"
        @change="onThresholdUnitChange"
      >
        <option
          v-for="(option, index) in options"
          :key="index"
          :value="option.value"
        >
          {{ option.label }}
        </option>
      </select>
    </div>
  </div>
</template>
