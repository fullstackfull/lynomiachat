<script setup>
// The Audiences destination (docs/product-enablement/13-audience-ux-implementation.md).
//
// Before this, an audience could only be reached as a sidebar leaf, and only if one already existed: with none, the
// sidebar hid the word "Audiences" entirely, and the only way to make one was an unlabelled save icon that appeared
// after you had applied a filter. So the concept had no home. This is it.
//
// It creates nothing new on the server. An audience is a saved contact filter (`CustomFilter`, `filter_type: contact`),
// so this page lists the records the sidebar already fetched, acts on them through the same `custom_filters` API, and
// sends every edit to the filter panel that already owns it. There is no audience model, no membership table, and
// nothing here evaluates a filter until somebody asks for a count.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactAPI from 'dashboard/api/contacts';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  audienceAutomationRoute,
  audienceCampaignRoute,
  audienceRoute,
} from 'dashboard/helper/audienceHelper';
import { AUDIENCE_PRESETS } from 'dashboard/recipes/audiencePresets';
import { useContactFilterContext } from 'dashboard/components-next/filter/contactProvider';
import { useAudienceFilterTypes } from 'dashboard/components-next/filter/audienceProvider';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyState from 'dashboard/components-next/empty-state/EmptyState.vue';
import AudienceCard from 'dashboard/components-next/audience/AudienceCard.vue';
import AudienceExplainer from 'dashboard/components-next/audience/AudienceExplainer.vue';
import RecipeDialog from 'dashboard/components-next/recipes/RecipeDialog.vue';
import CreateSegmentDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateSegmentDialog.vue';
import DeleteSegmentDialog from 'dashboard/components-next/Contacts/ContactsForm/DeleteSegmentDialog.vue';

const FILTER_TYPE_CONTACT = 'contact';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { isAdmin } = useAdmin();

const audiences = useMapGetter('customViews/getContactCustomViews');
const uiFlags = useMapGetter('customViews/getUIFlags');
const accountId = useMapGetter('getCurrentAccountId');
const isFetching = computed(() => uiFlags.value.isFetching);

// The contact vocabulary already includes the Commerce and Conversation conditions, so one provider names every
// attribute an audience can be built from; `loadAudienceFields` is what fills in their options.
const { filterTypes } = useContactFilterContext();
const { loadAudienceFields } = useAudienceFilterTypes();

// Shared first, then by name: the shared ones are the account's, and the ones campaigns and automation rules can use.
const sortedAudiences = computed(() =>
  [...audiences.value].sort(
    (a, b) =>
      Number(Boolean(b.shared)) - Number(Boolean(a.shared)) ||
      a.name.localeCompare(b.name)
  )
);
const hasAudiences = computed(() => sortedAudiences.value.length > 0);

// Counts live here rather than on the card so they survive a re-render, and so one row's request cannot be mistaken
// for another's. Keyed by audience id.
const counts = ref({});
const countingId = ref(null);

const presetDialogRef = ref(null);
const createDialogRef = ref(null);
const deleteDialogRef = ref(null);
// The conditions the create dialog will save. The dialog asks only for a name, so whoever opens it owns this.
const pendingQuery = ref({});
const pendingDelete = ref(null);

onMounted(() => {
  // The sidebar fetches these too, but this page can be the first thing a session opens.
  store.dispatch('customViews/get', FILTER_TYPE_CONTACT);
  loadAudienceFields();
});

const openAudience = audience => router.push(audienceRoute(audience));
// Editing an audience is editing its conditions, in the filter panel on its own page. One editor, not two.
const editAudience = audience =>
  router.push(audienceRoute(audience, { edit: true }));

const countAudience = async audience => {
  if (countingId.value) return;

  countingId.value = audience.id;
  try {
    // The same request the audience's own page makes, so the number is the one the list would show. On demand only:
    // browsing this page evaluates nothing.
    const { data } = await ContactAPI.filter(1, 'name', audience.query);
    counts.value = { ...counts.value, [audience.id]: data?.meta?.count ?? 0 };
  } catch {
    // A filter the server will not evaluate (a deleted custom attribute, a condition it refuses) has no honest
    // number. Say so rather than showing a zero.
    useAlert(t('CONTACTS_LAYOUT.AUDIENCES.COUNT_FAILED'));
  } finally {
    countingId.value = null;
  }
};

const duplicateAudience = audience => {
  // The same conditions under a new name, through the same dialog and the same create call as saving a filter by
  // hand: the name, and whether the copy is shared, stay the user's choice.
  pendingQuery.value = audience.query;
  createDialogRef.value?.open({
    name: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.DUPLICATE_NAME', {
      name: audience.name,
    }),
    // Only administrators may share an audience; defaulting it on for anyone else would send a `shared` the server
    // refuses.
    shared: Boolean(audience.shared) && isAdmin.value,
    title: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.DUPLICATE_TITLE'),
  });
};

const copyAudienceLink = async audience => {
  const url = `${window.chatwootConfig.hostURL}${frontendURL(
    `accounts/${accountId.value}/contacts/segments/${audience.id}`
  )}`;
  try {
    await copyTextToClipboard(url);
    useAlert(t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.LINK_COPIED'));
  } catch {
    useAlert(t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.LINK_COPY_FAILED'));
  }
};

const confirmDelete = audience => {
  pendingDelete.value = audience;
  deleteDialogRef.value?.dialogRef.open();
};

const deleteAudience = async payload => {
  const audience = pendingDelete.value;
  if (!audience) return;

  try {
    await store.dispatch('customViews/delete', {
      id: audience.id,
      ...payload,
    });
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.SUCCESS_MESSAGE')
    );
  } catch (error) {
    // A shared audience automation rules or unsent campaigns still reference is refused with the reason.
    useAlert(
      (audience.shared && error.message) ||
        t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.ERROR_MESSAGE')
    );
  } finally {
    deleteDialogRef.value?.dialogRef.close();
    pendingDelete.value = null;
  }
};

const openPresets = () => presetDialogRef.value?.open();

const createFromPreset = (preset, values) => {
  pendingQuery.value = preset.build(values);
  presetDialogRef.value?.close();
  createDialogRef.value?.open({
    name: t(preset.name),
    title: t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.TITLE'),
  });
};

// "Start from scratch instead": the filter builder on the contacts list, which is where conditions are chosen by
// hand. The preset gallery is an offer, never the only way in.
const buildFromFilters = () => {
  presetDialogRef.value?.close();
  router.push({ name: 'contacts_dashboard_index', query: { page: 1 } });
};

const createAudience = async payload => {
  try {
    await store.dispatch('customViews/create', {
      ...payload,
      query: pendingQuery.value,
    });
    createDialogRef.value?.dialogRef.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.SUCCESS_MESSAGE')
    );
  } catch (error) {
    useAlert(
      error.message ||
        t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.ERROR_MESSAGE')
    );
  }
};
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-auto bg-n-surface-1">
    <header class="sticky top-0 z-20 px-6 bg-n-surface-1">
      <div
        class="flex flex-col gap-3 py-6 mx-auto sm:flex-row sm:items-center sm:justify-between max-w-5xl"
      >
        <h1 class="mb-0 text-xl font-medium truncate text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.AUDIENCES.TITLE') }}
        </h1>
        <div class="flex flex-wrap items-center gap-2">
          <Button
            icon="i-lucide-sparkles"
            color="slate"
            variant="faded"
            size="sm"
            :label="t('RECIPES.AUDIENCE.ACTION')"
            @click="openPresets"
          />
          <Button
            icon="i-lucide-list-filter"
            size="sm"
            :label="t('CONTACTS_LAYOUT.AUDIENCES.FROM_FILTERS')"
            @click="buildFromFilters"
          />
        </div>
      </div>
    </header>

    <main class="flex-1 px-6 pb-6 overflow-y-auto">
      <div class="flex flex-col gap-4 w-full mx-auto max-w-5xl">
        <AudienceExplainer compact />

        <div
          v-if="isFetching && !hasAudiences"
          class="flex items-center justify-center py-10 text-n-slate-11"
          role="status"
          aria-live="polite"
        >
          <span class="sr-only">
            {{ t('CONTACTS_LAYOUT.AUDIENCES.LOADING') }}
          </span>
          <Spinner />
        </div>

        <EmptyState
          v-else-if="!hasAudiences"
          icon="i-lucide-users-round"
          :title="t('CONTACTS_LAYOUT.AUDIENCES.EMPTY_STATE.TITLE')"
          :description="t('CONTACTS_LAYOUT.AUDIENCES.EMPTY_STATE.DESCRIPTION')"
        >
          <template #action>
            <div class="flex flex-wrap items-center justify-center gap-2">
              <Button
                icon="i-lucide-sparkles"
                size="sm"
                :label="t('RECIPES.AUDIENCE.ACTION')"
                @click="openPresets"
              />
              <Button
                icon="i-lucide-list-filter"
                color="slate"
                variant="faded"
                size="sm"
                :label="t('CONTACTS_LAYOUT.AUDIENCES.FROM_FILTERS')"
                @click="buildFromFilters"
              />
            </div>
          </template>
        </EmptyState>

        <div v-else class="flex flex-col gap-3">
          <AudienceCard
            v-for="audience in sortedAudiences"
            :key="audience.id"
            :audience="audience"
            :filter-types="filterTypes"
            :count="counts[audience.id] ?? null"
            :is-counting="countingId === audience.id"
            @open="openAudience(audience)"
            @edit="editAudience(audience)"
            @duplicate="duplicateAudience(audience)"
            @use-in-automation="router.push(audienceAutomationRoute(audience))"
            @use-in-campaign="router.push(audienceCampaignRoute(audience))"
            @copy-link="copyAudienceLink(audience)"
            @delete="confirmDelete(audience)"
            @count="countAudience(audience)"
          />
        </div>
      </div>
    </main>

    <RecipeDialog
      ref="presetDialogRef"
      :recipes="AUDIENCE_PRESETS"
      :title="t('RECIPES.AUDIENCE.TITLE')"
      :description="t('RECIPES.AUDIENCE.DESCRIPTION')"
      @create="createFromPreset"
      @scratch="buildFromFilters"
    />
    <CreateSegmentDialog ref="createDialogRef" @create="createAudience" />
    <DeleteSegmentDialog ref="deleteDialogRef" @delete="deleteAudience" />
  </div>
</template>
