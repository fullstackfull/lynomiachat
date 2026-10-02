<script setup>
// Recipients of an SMS or WhatsApp campaign: the account's labels and, for Lynomia, its shared audiences
// (docs/campaigns/04-ui.md). The campaign stores references only; recipients are resolved when it is sent.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

defineProps({
  message: { type: String, default: '' },
});

const labelIds = defineModel('labelIds', { type: Array, default: () => [] });
const audienceIds = defineModel('audienceIds', {
  type: Array,
  default: () => [],
});

const { t } = useI18n();

const labels = useMapGetter('labels/getLabels');
// The Sidebar loads the contact filters; campaigns may use only the shared ones.
const contactViews = useMapGetter('customViews/getContactCustomViews');

const labelOptions = computed(() =>
  labels.value.map(label => ({ value: label.id, label: label.title }))
);
const audienceOptions = computed(() =>
  contactViews.value
    .filter(view => view.shared)
    .map(view => ({ value: view.id, label: view.name }))
);
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
        :empty-state="t('CAMPAIGN.RECIPIENTS.AUDIENCES.EMPTY')"
        :has-error="!!message"
        class="[&>div>button]:bg-n-alpha-black2"
        data-test-id="campaign-recipient-audiences"
      />
    </div>
    <p v-if="message" class="mb-0 text-label-small text-n-ruby-11">
      {{ message }}
    </p>
  </fieldset>
</template>
