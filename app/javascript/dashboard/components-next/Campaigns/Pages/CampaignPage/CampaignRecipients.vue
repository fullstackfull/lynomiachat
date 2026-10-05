<script setup>
// Recipients of an SMS or WhatsApp campaign: the account's labels and, for Lynomia, its shared audiences
// (docs/campaigns/04-ui.md). The campaign stores references only; recipients are resolved when it is sent. The count is
// the server's, each contact once (docs/campaigns/05-preview-and-dedup.md); a failed count is unknown, never zero.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useMapGetter } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import CampaignsAPI from 'dashboard/api/campaigns';
import { buildCampaignAudience } from 'shared/constants/campaign';

import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AudienceExplainer from 'dashboard/components-next/audience/AudienceExplainer.vue';
import { useAudienceFilterTypes } from 'dashboard/components-next/filter/audienceProvider';
import { useContactFilterContext } from 'dashboard/components-next/filter/contactProvider';
import { summariseAudience } from 'dashboard/helper/audienceSummary';

defineProps({
  message: { type: String, default: '' },
});

// The page owns the trip to Contacts and back, because it is the page that has a draft to keep.
const emit = defineEmits(['createAudience']);

const labelIds = defineModel('labelIds', { type: Array, default: () => [] });
const audienceIds = defineModel('audienceIds', {
  type: Array,
  default: () => [],
});

const { t } = useI18n();

const labels = useMapGetter('labels/getLabels');
// The Sidebar loads the contact filters; campaigns may use only the shared ones.
const contactViews = useMapGetter('customViews/getContactCustomViews');
// Those filters arrive asynchronously. Without this the section said "no shared audiences yet" to an account
// that has several, simply because the dialog opened before the fetch returned.
const customViewUiFlags = useMapGetter('customViews/getUIFlags');
const isLoadingAudiences = computed(() => customViewUiFlags.value?.isFetching);

const { filterTypes } = useContactFilterContext();
const { audienceFilterTypes } = useAudienceFilterTypes();
// An audience's conditions can come from either vocabulary, so a summary needs both.
const allFilterTypes = computed(() => [
  ...(filterTypes.value || []),
  ...(audienceFilterTypes.value || []),
]);

const labelOptions = computed(() =>
  labels.value.map(label => ({ value: label.id, label: label.title }))
);
const sharedAudiences = computed(() =>
  contactViews.value.filter(view => view.shared)
);
// Each option says what its audience actually asks for. The summary is read from the stored query, so the list
// costs no request and asks no provider anything.
const audienceOptions = computed(() =>
  sharedAudiences.value.map(view => ({
    value: view.id,
    label: view.name,
    description:
      summariseAudience(view.query, allFilterTypes.value, {
        limit: 2,
        andLabel: t('CONTACTS_FILTER.QUERY_DROPDOWN_LABELS.AND').toLowerCase(),
        moreLabel: count =>
          t('CAMPAIGN.RECIPIENTS.AUDIENCES.CONDITIONS', { count }, count),
      }) || undefined,
  }))
);
const hasNoAudiences = computed(
  () => !isLoadingAudiences.value && sharedAudiences.value.length === 0
);

const PREVIEW_DELAY_MS = 300;
const { run, abort, isPending } = useAbortableRequest();
const count = ref(null);
const countFailed = ref(false);
const audience = computed(() =>
  buildCampaignAudience(labelIds.value, audienceIds.value)
);

const fetchCount = debounce(async () => {
  try {
    const response = await run(signal =>
      CampaignsAPI.audiencePreview(audience.value, { signal })
    );
    if (response) count.value = response.data.count;
  } catch {
    countFailed.value = true;
  }
}, PREVIEW_DELAY_MS);

watch(audience, entries => {
  count.value = null;
  countFailed.value = false;
  if (entries.length) {
    fetchCount();
  } else {
    abort();
  }
});

const countNote = computed(() => {
  if (!audience.value.length) return '';
  if (countFailed.value) return t('CAMPAIGN.RECIPIENTS.COUNT.FAILED');
  if (isPending.value || count.value === null)
    return t('CAMPAIGN.RECIPIENTS.COUNT.LOADING');
  const matching = t(
    'CAMPAIGN.RECIPIENTS.COUNT.MATCHING',
    { count: count.value },
    count.value
  );
  return `${matching} ${t('CAMPAIGN.RECIPIENTS.COUNT.NOTE')}`;
});
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-test-id="campaign-recipients">
    <legend class="mb-1 text-sm font-medium text-n-slate-12">
      {{ t('CAMPAIGN.RECIPIENTS.TITLE') }}
    </legend>
    <div class="flex flex-col gap-1">
      <span class="text-label-small text-n-slate-11">
        {{ t('CAMPAIGN.RECIPIENTS.LABELS.LABEL') }}
      </span>
      <TagMultiSelectComboBox
        v-model="labelIds"
        :options="labelOptions"
        :placeholder="t('CAMPAIGN.RECIPIENTS.LABELS.PLACEHOLDER')"
        :has-error="!!message"
        class="[&>div>button]:bg-n-alpha-black2"
        data-test-id="campaign-recipient-labels"
      />
    </div>
    <div class="flex flex-col gap-1">
      <span class="text-label-small text-n-slate-11">
        {{ t('CAMPAIGN.RECIPIENTS.AUDIENCES.LABEL') }}
      </span>
      <TagMultiSelectComboBox
        v-model="audienceIds"
        :options="audienceOptions"
        :placeholder="t('CAMPAIGN.RECIPIENTS.AUDIENCES.PLACEHOLDER')"
        :empty-state="
          isLoadingAudiences
            ? t('CAMPAIGN.RECIPIENTS.AUDIENCES.LOADING')
            : t('CAMPAIGN.RECIPIENTS.AUDIENCES.EMPTY')
        "
        :has-error="!!message"
        class="[&>div>button]:bg-n-alpha-black2"
        data-test-id="campaign-recipient-audiences"
      />
    </div>
    <!-- An account with none needs to know what one is and be able to make one, here, without losing this
         campaign. Saying "no shared audiences yet" inside a dropdown nobody opens did neither. -->
    <AudienceExplainer v-if="hasNoAudiences" compact>
      <template #action>
        <Button
          sm
          faded
          slate
          icon="i-lucide-plus"
          :label="t('CAMPAIGN.RECIPIENTS.AUDIENCES.CREATE')"
          data-test-id="campaign-create-audience"
          @click="emit('createAudience')"
        />
        <span class="text-label-small text-n-slate-11">
          {{ t('CAMPAIGN.RECIPIENTS.AUDIENCES.CREATE_HINT') }}
        </span>
      </template>
    </AudienceExplainer>
    <p v-if="message" class="mb-0 text-label-small text-n-ruby-11">
      {{ message }}
    </p>
    <p
      v-else-if="countNote"
      class="mb-0 text-label-small text-n-slate-11"
      data-test-id="campaign-recipient-count"
    >
      {{ countNote }}
    </p>
  </fieldset>
</template>
