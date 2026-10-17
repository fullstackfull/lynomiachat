<script setup>
// STOPPING A CAMPAIGN THAT IS SENDING, which is terminal and so is confirmed.
//
// Cancelling is not deleting and the difference is the point: the recipient snapshot stays,
// because who was reached before it was stopped is exactly what an operator cancelling a
// half-sent campaign needs to read afterwards. The copy says so, and says the other thing
// an operator has to know -- that messages already handed to the provider cannot be
// recalled.
//
// `display_id`, not `id`: the campaigns API addresses a campaign by the number it hands
// out, and using the primary key here is the defect that made the analytics page show
// another campaign's results.
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

const handleDialogConfirm = async () => {
  const id = props.selectedCampaign?.display_id;
  if (!id) return;

  try {
    await store.dispatch('campaigns/cancel', { id });
    useAlert(t('CAMPAIGN.CONFIRM_CANCEL.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CAMPAIGN.CONFIRM_CANCEL.ERROR_MESSAGE'));
  }
  dialogRef.value?.close();
};

const isUpdating = computed(() => uiFlags.value.isUpdating);

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CAMPAIGN.CONFIRM_CANCEL.TITLE')"
    :confirm-button-label="t('CAMPAIGN.CONFIRM_CANCEL.CONFIRM')"
    :is-loading="isUpdating"
    :disable-confirm-button="isUpdating"
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
        {{ t('CAMPAIGN.CONFIRM_CANCEL.DESCRIPTION') }}
      </p>
    </template>
  </Dialog>
</template>
