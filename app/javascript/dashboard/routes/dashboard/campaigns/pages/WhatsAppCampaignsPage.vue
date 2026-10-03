<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import {
  useStore,
  useStoreGetters,
  useMapGetter,
} from 'dashboard/composables/store';
import {
  audienceIdFromQuery,
  findSharedAudience,
} from 'dashboard/helper/audienceHelper';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import WhatsAppCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import WhatsAppCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/WhatsAppCampaignEmptyState.vue';
import { useRoute, useRouter } from 'vue-router';

const { t } = useI18n();
const getters = useStoreGetters();
const store = useStore();
const route = useRoute();
const router = useRouter();

const selectedCampaign = ref(null);
const [showWhatsAppCampaignDialog, toggleWhatsAppCampaignDialog] = useToggle();

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const confirmDeleteCampaignDialogRef = ref(null);
const initialSharedAudienceIds = ref([]);

const WhatsAppCampaigns = computed(
  () => getters['campaigns/getWhatsAppCampaigns'].value
);

const hasNoWhatsAppCampaigns = computed(
  () => WhatsAppCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};

// "Use in a new WhatsApp campaign", from an audience. The audience's own record decides: an id that is not one of
// this account's shared audiences opens the ordinary empty dialog, and the server would refuse it anyway.
onMounted(async () => {
  const audienceId = audienceIdFromQuery(route.query);
  if (!audienceId) return;

  router.replace({ name: route.name, params: route.params, query: {} });
  await store.dispatch('customViews/get', 'contact');
  const audience = findSharedAudience(
    getters['customViews/getContactCustomViews'].value,
    audienceId
  );
  initialSharedAudienceIds.value = audience ? [audience.id] : [];
  toggleWhatsAppCampaignDialog(true);
});

// Closing clears the prefill, so the next "New campaign" starts empty.
const closeDialog = () => {
  toggleWhatsAppCampaignDialog(false);
  initialSharedAudienceIds.value = [];
};

const handleAnalytics = campaign => {
  router.push({
    name: 'campaigns_whatsapp_analytics',
    params: { campaignId: campaign.id },
  });
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.WHATSAPP.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.WHATSAPP.NEW_CAMPAIGN')"
    @click="toggleWhatsAppCampaignDialog()"
    @close="closeDialog"
  >
    <template #action>
      <WhatsAppCampaignDialog
        v-if="showWhatsAppCampaignDialog"
        :initial-shared-audience-ids="initialSharedAudienceIds"
        @close="closeDialog"
      />
    </template>
    <div
      v-if="isFetchingCampaigns"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoWhatsAppCampaigns"
      :campaigns="WhatsAppCampaigns"
      @delete="handleDelete"
      @analytics="handleAnalytics"
    />
    <WhatsAppCampaignEmptyState
      v-else
      :title="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.WHATSAPP.EMPTY_STATE.SUBTITLE')"
      class="pt-14"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
  </CampaignLayout>
</template>
