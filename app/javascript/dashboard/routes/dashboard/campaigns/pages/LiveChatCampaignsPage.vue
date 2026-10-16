<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useStore,
  useStoreGetters,
  useMapGetter,
} from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import FetchErrorState from 'dashboard/components-next/FetchErrorState.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import LiveChatCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue';
import EditLiveChatCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/EditLiveChatCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import LiveChatCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/LiveChatCampaignEmptyState.vue';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const createDialogRef = ref(null);
const editLiveChatCampaignDialogRef = ref(null);
const confirmDeleteCampaignDialogRef = ref(null);
const selectedCampaign = ref(null);

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);
// A failed fetch is not an empty account. Without this the page drew its empty state -- sample
// campaign cards and all -- for a request that never came back.
const hasFetchError = computed(() => uiFlags.value.hasError);

const retryFetch = () => store.dispatch('campaigns/get');

// The create flow used to be an absolutely positioned div hung off the header button: no backdrop, no focus
// trap, no Escape, and on a 900px screen its Create button sat below the fold. It is a real modal now.
const openCreateDialog = () => createDialogRef.value?.dialogRef?.open();

const liveChatCampaigns = computed(
  () => getters['campaigns/getLiveChatCampaigns'].value
);

const hasNoLiveChatCampaigns = computed(
  () => liveChatCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleEdit = campaign => {
  selectedCampaign.value = campaign;
  editLiveChatCampaignDialogRef.value.dialogRef.open();
};
const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};
</script>

<template>
  <CampaignLayout
    :header-title="t('CAMPAIGN.LIVE_CHAT.HEADER_TITLE')"
    :header-description="t('CAMPAIGN.LIVE_CHAT.HEADER_DESCRIPTION')"
    :count="isFetchingCampaigns ? null : liveChatCampaigns.length"
    :button-label="t('CAMPAIGN.LIVE_CHAT.NEW_CAMPAIGN')"
    @click="openCreateDialog"
  >
    <div
      v-if="isFetchingCampaigns"
      class="flex justify-center items-center py-10 text-n-slate-11"
      role="status"
      aria-live="polite"
    >
      <span class="sr-only">{{ t('CAMPAIGN.LOADING') }}</span>
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoLiveChatCampaigns"
      :campaigns="liveChatCampaigns"
      is-live-chat-type
      @edit="handleEdit"
      @delete="handleDelete"
    />
    <LiveChatCampaignEmptyState
      v-else-if="!hasFetchError"
      :title="t('CAMPAIGN.LIVE_CHAT.EMPTY_STATE.TITLE')"
      :subtitle="t('CAMPAIGN.LIVE_CHAT.EMPTY_STATE.SUBTITLE')"
    />
    <FetchErrorState v-else @retry="retryFetch" />
    <LiveChatCampaignDialog ref="createDialogRef" />
    <EditLiveChatCampaignDialog
      ref="editLiveChatCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
  </CampaignLayout>
</template>
