<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import DurationInput from 'dashboard/components-next/input/DurationInput.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { DURATION_UNITS } from 'dashboard/components-next/input/constants';
import { SECONDS_PER_MINUTE } from 'dashboard/constants/supportTickets';

// One SLA policy. The API speaks seconds; nobody configures a support target in seconds, so the form collects
// minutes, hours or days through the shared duration control and converts at the boundary.
const props = defineProps({
  // A policy to edit, or null to create one.
  policy: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();

// One minute to 999 days, in minutes: the floor the control already uses elsewhere, and a ceiling the column
// can hold.
const MIN_MINUTES = 1;
const MAX_MINUTES = 1438560;

const dialogRef = ref(null);
const isSaving = ref(false);

const emptyForm = () => ({
  name: '',
  description: '',
  firstResponseMinutes: 60,
  firstResponseUnit: DURATION_UNITS.HOURS,
  resolutionMinutes: 1440,
  resolutionUnit: DURATION_UNITS.HOURS,
  onlyDuringBusinessHours: false,
});

const form = ref(emptyForm());

const isEditing = computed(() => Boolean(props.policy?.id));

const isSubmitDisabled = computed(() => !form.value.name.trim());

// Which unit reads most naturally for a stored value, so editing a one-day target does not open on "1440".
const unitFor = minutes => {
  if (!minutes) return DURATION_UNITS.MINUTES;
  if (minutes % (24 * 60) === 0) return DURATION_UNITS.DAYS;
  if (minutes % 60 === 0) return DURATION_UNITS.HOURS;
  return DURATION_UNITS.MINUTES;
};

const toMinutes = seconds =>
  seconds ? Math.floor(seconds / SECONDS_PER_MINUTE) : 0;

const reset = () => {
  if (!props.policy) {
    form.value = emptyForm();
    return;
  }

  const firstResponseMinutes = toMinutes(
    props.policy.first_response_time_threshold
  );
  const resolutionMinutes = toMinutes(props.policy.resolution_time_threshold);

  form.value = {
    name: props.policy.name || '',
    description: props.policy.description || '',
    firstResponseMinutes,
    firstResponseUnit: unitFor(firstResponseMinutes),
    resolutionMinutes,
    resolutionUnit: unitFor(resolutionMinutes),
    onlyDuringBusinessHours: Boolean(props.policy.only_during_business_hours),
  };
};

watch(() => props.policy, reset, { immediate: true });

// A threshold of zero is no threshold: the server treats a nil column as "this policy does not govern that
// target", and sending 0 would promise an instant one.
const payload = () => ({
  name: form.value.name.trim(),
  description: form.value.description.trim(),
  first_response_time_threshold: form.value.firstResponseMinutes
    ? form.value.firstResponseMinutes * SECONDS_PER_MINUTE
    : null,
  resolution_time_threshold: form.value.resolutionMinutes
    ? form.value.resolutionMinutes * SECONDS_PER_MINUTE
    : null,
  only_during_business_hours: form.value.onlyDuringBusinessHours,
});

const onConfirm = async () => {
  isSaving.value = true;
  try {
    const response = isEditing.value
      ? await SupportTicketsAPI.updateSlaPolicy(props.policy.id, payload())
      : await SupportTicketsAPI.createSlaPolicy(payload());
    useAlert(
      isEditing.value
        ? t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.UPDATE_SUCCESS')
        : t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.CREATE_SUCCESS')
    );
    emit('saved', response.data.payload);
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const open = () => {
  reset();
  dialogRef.value?.open();
};

defineExpose({ open, dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="xl"
    overflow-y-auto
    :title="
      isEditing
        ? t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.EDIT_TITLE')
        : t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.CREATE_TITLE')
    "
    :description="t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.DESCRIPTION')"
    :confirm-button-label="t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.SUBMIT')"
    :is-loading="isSaving"
    :disable-confirm-button="isSubmitDisabled"
    @confirm="onConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.NAME')"
        :placeholder="t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.NAME_PLACEHOLDER')"
      />

      <Input
        v-model="form.description"
        :label="t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.POLICY_DESCRIPTION')"
        :placeholder="
          t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.POLICY_DESCRIPTION_PLACEHOLDER')
        "
      />

      <div class="flex flex-col gap-1">
        <span class="text-label text-n-slate-12">
          {{ t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.FIRST_RESPONSE') }}
        </span>
        <div class="flex items-center gap-2">
          <DurationInput
            v-model:model-value="form.firstResponseMinutes"
            v-model:unit="form.firstResponseUnit"
            :min="MIN_MINUTES"
            :max="MAX_MINUTES"
          />
        </div>
        <span class="text-label-small text-n-slate-10">
          {{ t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.THRESHOLD_HINT') }}
        </span>
      </div>

      <div class="flex flex-col gap-1">
        <span class="text-label text-n-slate-12">
          {{ t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.RESOLUTION') }}
        </span>
        <div class="flex items-center gap-2">
          <DurationInput
            v-model:model-value="form.resolutionMinutes"
            v-model:unit="form.resolutionUnit"
            :min="MIN_MINUTES"
            :max="MAX_MINUTES"
          />
        </div>
        <span class="text-label-small text-n-slate-10">
          {{ t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.THRESHOLD_HINT') }}
        </span>
      </div>

      <div class="flex items-start justify-between gap-4">
        <div class="flex flex-col gap-1 min-w-0">
          <span class="text-label text-n-slate-12">
            {{ t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.BUSINESS_HOURS') }}
          </span>
          <span class="text-label-small text-n-slate-10">
            {{ t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.BUSINESS_HOURS_HINT') }}
          </span>
        </div>
        <Switch
          v-model="form.onlyDuringBusinessHours"
          :label="t('SUPPORT_TICKETS.SLA_SETTINGS.FORM.BUSINESS_HOURS')"
        />
      </div>
    </div>
  </Dialog>
</template>
