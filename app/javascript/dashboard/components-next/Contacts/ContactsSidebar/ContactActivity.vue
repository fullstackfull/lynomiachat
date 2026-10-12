<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import ContactActivityEntry from './ContactActivityEntry.vue';
import { useContactActivity } from 'dashboard/composables/useContactActivity';
import { CONTACT_ACTIVITY_FILTERS } from 'dashboard/constants/contactActivity';

const { t } = useI18n();
const route = useRoute();

const contactId = computed(() => route.params.contactId);

const {
  entries,
  category,
  error,
  isLoading,
  hasLoadedOnce,
  isPartial,
  hasMore,
  isEmpty,
  warnings,
  load,
  loadMore,
  setCategory,
} = useContactActivity(contactId);

const filters = computed(() =>
  CONTACT_ACTIVITY_FILTERS.map(value => ({
    value,
    label: t(`CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.FILTER.${value.toUpperCase()}`),
  }))
);

// A 422 from the request boundary carries the reason; anything else gets the generic message rather than a raw
// error pushed at an agent.
const errorMessage = computed(() => {
  if (!error.value) return '';
  return (
    error.value.response?.data?.message ||
    t('CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.ERROR')
  );
});

const partialMessage = computed(() =>
  t('CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.PARTIAL', {
    sources: warnings.value.map(warning => warning.scope).join(', '),
  })
);

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-3 px-6 pb-6">
    <div class="flex flex-wrap gap-1.5" role="group">
      <button
        v-for="filter in filters"
        :key="filter.value"
        type="button"
        class="px-2 py-1 rounded-md text-label-small focus-ring"
        :class="
          category === filter.value
            ? 'bg-n-slate-4 text-n-slate-12'
            : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
        "
        :aria-pressed="category === filter.value"
        @click="setCategory(filter.value)"
      >
        {{ filter.label }}
      </button>
    </div>

    <Banner v-if="errorMessage" color="ruby">{{ errorMessage }}</Banner>

    <template v-else>
      <Banner v-if="isPartial" color="amber">{{ partialMessage }}</Banner>

      <div
        v-if="isLoading && !hasLoadedOnce"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>

      <p
        v-else-if="isEmpty"
        class="py-10 m-0 text-sm leading-6 text-center text-n-slate-11"
      >
        {{ t('CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.EMPTY_STATE') }}
      </p>

      <template v-else>
        <ul class="m-0 list-none divide-y divide-n-weak">
          <ContactActivityEntry
            v-for="entry in entries"
            :key="entry.id"
            :entry="entry"
          />
        </ul>

        <button
          v-if="hasMore"
          type="button"
          class="py-2 w-full rounded-lg bg-n-alpha-1 text-button-small text-n-slate-11 hover:bg-n-alpha-2 focus-ring"
          :disabled="isLoading"
          @click="loadMore"
        >
          {{
            isLoading
              ? t('CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.LOADING')
              : t('CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.LOAD_MORE')
          }}
        </button>
      </template>
    </template>
  </div>
</template>
