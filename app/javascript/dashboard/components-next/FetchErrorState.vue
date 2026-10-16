<script setup>
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

// What a list shows when its request failed.
//
// Every list in this dashboard swallowed its fetch error and fell through to the empty state, so a
// request that never came back was drawn as "you have nothing here" -- on the campaign pages
// complete with the sample records the empty state illustrates itself with. An empty list and a
// failed one are different facts and this is the second one.
//
// No backdrop: the empty state's sample records are an invitation to create the first one, which is
// exactly the wrong thing to show when we do not yet know what exists.
defineProps({
  title: {
    type: String,
    default: '',
  },
  subtitle: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['retry']);

const { t } = useI18n();
</script>

<template>
  <EmptyStateLayout
    :title="title || t('GENERAL_SETTINGS.FETCH_ERROR.TITLE')"
    :subtitle="subtitle || t('GENERAL_SETTINGS.FETCH_ERROR.SUBTITLE')"
    :show-backdrop="false"
    icon="i-lucide-cloud-off"
  >
    <template #actions>
      <Button
        :label="t('GENERAL_SETTINGS.FETCH_ERROR.RETRY')"
        icon="i-lucide-refresh-cw"
        size="sm"
        @click="emit('retry')"
      />
    </template>
  </EmptyStateLayout>
</template>
