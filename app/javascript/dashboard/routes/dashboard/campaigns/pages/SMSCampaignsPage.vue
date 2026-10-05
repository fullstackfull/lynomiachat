<script setup>
import { computed, onActivated, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { useRoute, useRouter } from 'vue-router';
import {
  useStore,
  useStoreGetters,
  useMapGetter,
} from 'dashboard/composables/store';
import {
  audienceIdFromQuery,
  findAccountLabel,
  findSharedAudience,
  labelIdFromQuery,
  audienceReturnRoute,
} from 'dashboard/helper/audienceHelper';
import {
  saveCampaignDraft,
  takeCampaignDraft,
  clearCampaignDraft,
} from 'dashboard/helper/campaignDraft';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import SMSCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import SMSCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/SMSCampaignEmptyState.vue';

const { t } = useI18n();
const getters = useStoreGetters();
const store = useStore();
const route = useRoute();
const router = useRouter();

const selectedCampaign = ref(null);
const [showSMSCampaignDialog, toggleSMSCampaignDialog] = useToggle();

const initialSharedAudienceIds = ref([]);
const initialLabelIds = ref([]);
const initialDraft = ref(null);
const accountLabels = useMapGetter('labels/getLabels');

const CAMPAIGN_TYPE = 'sms';

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const confirmDeleteCampaignDialogRef = ref(null);

const SMSCampaigns = computed(() => getters['campaigns/getSMSCampaigns'].value);

const hasNoSMSCampaigns = computed(
  () => SMSCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};

// The same bridge WhatsApp has: an audience or a label named in the route opens the dialog with it chosen, and a
// draft left behind by a trip to Contacts is restored. Reading the draft also clears it.
onActivated(async () => {
  const audienceId = audienceIdFromQuery(route.query);
  const labelId = labelIdFromQuery(route.query);
  initialDraft.value = takeCampaignDraft(CAMPAIGN_TYPE, Date.now());
  if (!audienceId && !labelId && !initialDraft.value) return;

  if (audienceId) {
    await store.dispatch('customViews/get', 'contact');
    const audience = findSharedAudience(
      getters['customViews/getContactCustomViews'].value,
      audienceId
    );
    initialSharedAudienceIds.value = audience ? [audience.id] : [];
  }
  if (labelId) {
    const label = findAccountLabel(accountLabels.value, labelId);
    initialLabelIds.value = label ? [label.id] : [];
  }
  toggleSMSCampaignDialog(true);
});

const closeDialog = () => {
  toggleSMSCampaignDialog(false);
  initialSharedAudienceIds.value = [];
  initialLabelIds.value = [];
  initialDraft.value = null;
  clearCampaignDraft(CAMPAIGN_TYPE);
};

const handleCreateAudience = draft => {
  saveCampaignDraft(CAMPAIGN_TYPE, draft, Date.now());
  router.push(audienceReturnRoute('campaigns_sms_index'));
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.SMS.HEADER_TITLE')"
    :button-label="t('CAMPAIGN.SMS.NEW_CAMPAIGN')"
    @click="toggleSMSCampaignDialog()"
    @close="closeDialog"
  >
    <template #action>
      <SMSCampaignDialog
        v-if="showSMSCampaignDialog"
        :initial-shared-audience-ids="initialSharedAudienceIds"
        :initial-label-ids="initialLabelIds"
        :initial-draft="initialDraft"
        @close="closeDialog"
        @create-audience="handleCreateAudience"
      />
    </template>
    <div
      v-if="isFetchingCampaigns"
      class="flex items-center justify-center py-10 text-n-slate-11"
      role="status"
      aria-live="polite"
    >
      <span class="sr-only">{{ t('CAMPAIGN.LOADING') }}</span>
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoSMSCampaigns"
      :campaigns="SMSCampaigns"
      @delete="handleDelete"
    />
    <SMSCampaignEmptyState
      v-else
      :title="t('CAMPAIGN.SMS.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.SMS.EMPTY_STATE.SUBTITLE')"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
  </CampaignLayout>
</template>
