<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert, useTrack } from 'dashboard/composables';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign.js';
import { CAMPAIGNS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events.js';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WhatsAppCampaignForm from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue';

defineProps({
  initialSharedAudienceIds: { type: Array, default: () => [] },
  initialLabelIds: { type: Array, default: () => [] },
  initialDraft: { type: Object, default: null },
});

const emit = defineEmits(['close', 'createAudience']);

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const formRef = ref(null);

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isCreating = computed(() => uiFlags.value.isCreating);
const isInvalidForm = computed(() => formRef.value?.isSubmitDisabled);

const addCampaign = async campaignDetails => {
  try {
    await store.dispatch('campaigns/create', campaignDetails);

    useTrack(CAMPAIGNS_EVENTS.CREATE_CAMPAIGN, {
      type: CAMPAIGN_TYPES.ONE_OFF,
    });

    useAlert(t('CAMPAIGN.WHATSAPP.CREATE.FORM.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAMPAIGN.WHATSAPP.CREATE.FORM.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

// The footer's button submits; the form validates and emits back what it built.
const handleConfirm = () => formRef.value?.handleSubmit();

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="xl"
    position="top"
    overflow-y-auto
    :title="t('CAMPAIGN.WHATSAPP.CREATE.TITLE')"
    :confirm-button-label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CREATE')"
    :cancel-button-label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CANCEL')"
    :is-loading="isCreating"
    :disable-confirm-button="isCreating || isInvalidForm"
    @confirm="handleConfirm"
    @close="emit('close')"
  >
    <WhatsAppCampaignForm
      ref="formRef"
      :initial-shared-audience-ids="initialSharedAudienceIds"
      :initial-label-ids="initialLabelIds"
      :initial-draft="initialDraft"
      :show-action-buttons="false"
      @submit="addCampaign"
      @cancel="dialogRef?.close()"
      @create-audience="draft => emit('createAudience', draft)"
    />
  </Dialog>
</template>
