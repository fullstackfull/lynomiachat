<script setup>
import { computed, ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  selectedCampaign: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const uiFlags = useMapGetter('campaigns/getUIFlags');

const deleteCampaign = async id => {
  if (!id) return;

  try {
    await store.dispatch('campaigns/delete', id);
    useAlert(t('CAMPAIGN.CONFIRM_DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CAMPAIGN.CONFIRM_DELETE.API.ERROR_MESSAGE'));
  }
};

const handleDialogConfirm = async () => {
  await deleteCampaign(props.selectedCampaign.id);
  dialogRef.value?.close();
};

const isDeleting = computed(() => uiFlags.value.isDeleting);

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CAMPAIGN.CONFIRM_DELETE.TITLE')"
    :confirm-button-label="t('CAMPAIGN.CONFIRM_DELETE.CONFIRM')"
    :is-loading="isDeleting"
    :disable-confirm-button="isDeleting"
    @confirm="handleDialogConfirm"
  >
    <template #description="{ descriptionId }">
      <p
        v-if="selectedCampaign?.title"
        class="mb-1 text-heading-3 text-n-slate-12"
      >
        {{ selectedCampaign.title }}
      </p>
      <p :id="descriptionId" class="mb-0 text-sm text-n-slate-11">
        {{ t('CAMPAIGN.CONFIRM_DELETE.DESCRIPTION') }}
      </p>
    </template>
  </Dialog>
</template>
