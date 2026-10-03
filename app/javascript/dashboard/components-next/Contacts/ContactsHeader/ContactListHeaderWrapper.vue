<script setup>
import { ref, computed, unref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import { useAlert, useTrack } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { CONTACTS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import contactFilterItems from 'dashboard/routes/dashboard/contacts/contactFilterItems';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import countries from 'shared/constants/countries';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';

import ContactsHeader from 'dashboard/components-next/Contacts/ContactsHeader/ContactHeader.vue';
import CreateNewContactDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue';
import ContactExportDialog from 'dashboard/components-next/Contacts/ContactsForm/ContactExportDialog.vue';
import ContactImportDialog from 'dashboard/components-next/Contacts/ContactsForm/ContactImportDialog.vue';
import CreateSegmentDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateSegmentDialog.vue';
import RecipeDialog from 'dashboard/components-next/recipes/RecipeDialog.vue';
import { AUDIENCE_PRESETS } from 'dashboard/recipes/audiencePresets';
import DeleteSegmentDialog from 'dashboard/components-next/Contacts/ContactsForm/DeleteSegmentDialog.vue';
import ContactsFilter from 'dashboard/components-next/filter/ContactsFilter.vue';
import {
  useAudienceFilterTypes,
  audienceValuesForEdit,
} from 'dashboard/components-next/filter/audienceProvider.js';
import { AUDIENCE_QUERY_PARAM } from 'dashboard/helper/audienceHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { frontendURL } from 'dashboard/helper/URLHelper';

const props = defineProps({
  showSearch: { type: Boolean, default: true },
  searchValue: { type: String, default: '' },
  activeSort: { type: String, default: 'last_activity_at' },
  activeOrdering: { type: String, default: '' },
  headerTitle: { type: String, default: '' },
  segmentsId: { type: [String, Number], default: 0 },
  activeSegment: { type: Object, default: null },
  hasAppliedFilters: { type: Boolean, default: false },
  isLabelView: { type: Boolean, default: false },
  isActiveView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:sort',
  'search',
  'applyFilter',
  'clearFilters',
]);

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const createNewContactDialogRef = ref(null);
const contactExportDialogRef = ref(null);
const contactImportDialogRef = ref(null);
const createSegmentDialogRef = ref(null);
const deleteSegmentDialogRef = ref(null);
const presetDialogRef = ref(null);

const showFiltersModal = ref(false);
const appliedFilter = ref([]);
const segmentsQuery = ref({});

const appliedFilters = useMapGetter('contacts/getAppliedContactFiltersV4');
const { audienceFilterTypes, loadAudienceFields } = useAudienceFilterTypes();
onMounted(() => loadAudienceFields());
const contactAttributes = useMapGetter('attributes/getContactAttributes');
const labels = useMapGetter('labels/getLabels');
const hasActiveSegments = computed(
  () => props.activeSegment && props.segmentsId !== 0
);
const activeSegmentName = computed(() => props.activeSegment?.name);
// Lynomia shared audiences: members open them; only administrators change or delete them.
const { isAdmin } = useAdmin();
const isSharedSegment = computed(() => Boolean(props.activeSegment?.shared));
const canManageSegment = computed(
  () => !isSharedSegment.value || isAdmin.value
);

const openCreateNewContactDialog = () => {
  createNewContactDialogRef.value?.dialogRef.open();
};
const openContactImportDialog = () =>
  contactImportDialogRef.value?.dialogRef.open();
const openContactExportDialog = () =>
  contactExportDialogRef.value?.dialogRef.open();
const openCreateSegmentDialog = () => createSegmentDialogRef.value?.open();
const openDeleteSegmentDialog = () =>
  deleteSegmentDialogRef.value?.dialogRef.open();

const onCreate = async contact => {
  try {
    await store.dispatch('contacts/create', contact);
    createNewContactDialogRef.value?.onSuccess();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.SUCCESS_MESSAGE')
    );
  } catch (error) {
    const i18nPrefix = 'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION';
    if (error instanceof DuplicateContactException) {
      if (error.data.includes('email')) {
        useAlert(t(`${i18nPrefix}.EMAIL_ADDRESS_DUPLICATE`));
      } else if (error.data.includes('phone_number')) {
        useAlert(t(`${i18nPrefix}.PHONE_NUMBER_DUPLICATE`));
      }
    } else if (error instanceof ExceptionWithMessage) {
      useAlert(error.data);
    } else {
      useAlert(t(`${i18nPrefix}.ERROR_MESSAGE`));
    }
  }
};

const onImport = async file => {
  try {
    await store.dispatch('contacts/import', file);
    contactImportDialogRef.value?.dialogRef.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.SUCCESS_MESSAGE')
    );
    useTrack(CONTACTS_EVENTS.IMPORT_SUCCESS);
  } catch (error) {
    useAlert(
      error.message ??
        t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.ERROR_MESSAGE')
    );
    useTrack(CONTACTS_EVENTS.IMPORT_FAILURE);
  }
};

const onExport = async query => {
  try {
    await store.dispatch('contacts/export', query);
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.EXPORT_CONTACT.SUCCESS_MESSAGE')
    );
  } catch (error) {
    useAlert(
      error.message ||
        t('CONTACTS_LAYOUT.HEADER.ACTIONS.EXPORT_CONTACT.ERROR_MESSAGE')
    );
  }
};

const onCreateSegment = async payload => {
  try {
    const payloadData = {
      ...payload,
      query: segmentsQuery.value,
    };
    const response = await store.dispatch('customViews/create', payloadData);
    createSegmentDialogRef.value?.dialogRef.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.SUCCESS_MESSAGE')
    );
    const segmentId = response?.data?.id;
    if (!segmentId) return;
    // Navigate to the created segment
    router.push({
      name: 'contacts_dashboard_segments_index',
      params: { segmentId },
      query: { page: 1 },
    });
  } catch {
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.ERROR_MESSAGE')
    );
  }
};

const onDeleteSegment = async payload => {
  try {
    await store.dispatch('customViews/delete', {
      id: Number(props.segmentsId),
      ...payload,
    });
    router.push({
      name: 'contacts_dashboard_index',
      query: {
        page: 1,
      },
    });
    deleteSegmentDialogRef.value?.dialogRef.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.SUCCESS_MESSAGE')
    );
  } catch (error) {
    // A shared audience automation rules use is refused with the reason.
    deleteSegmentDialogRef.value?.dialogRef.close();
    useAlert(
      isSharedSegment.value && error.message
        ? error.message
        : t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.ERROR_MESSAGE'
          )
    );
  }
};

// Cross-module audience actions (docs/usability/04-implemented-productivity-features.md). An audience is a saved
// contact filter, so every one of these reuses what already exists: the same create API for a duplicate, the target
// module's own route for "use it there", the dashboard's own clipboard helper for a link.
const accountId = useMapGetter('getCurrentAccountId');

const duplicateSegment = () => {
  if (!props.activeSegment) return;
  // The copy is saved from the audience's own conditions, through the same dialog and the same create call as
  // "save these filters as an audience": the name, and whether the copy is shared, stay the user's choice.
  segmentsQuery.value = props.activeSegment.query;
  createSegmentDialogRef.value?.open({
    name: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.DUPLICATE_NAME', {
      name: props.activeSegment.name,
    }),
    // Only administrators may share an audience, and only they see the checkbox: defaulting it on for anyone else
    // would send a `shared` the server refuses.
    shared: isSharedSegment.value && isAdmin.value,
    title: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.DUPLICATE_TITLE'),
  });
};

// An audience preset builds the conditions; naming it and deciding whether the account shares it stays the user's
// explicit act, in the same dialog and through the same create call as saving a filter by hand.
const openPresetDialog = () => presetDialogRef.value?.open();

const createFromPreset = (preset, values) => {
  segmentsQuery.value = preset.build(values);
  presetDialogRef.value?.close();
  createSegmentDialogRef.value?.open({
    name: t(preset.name),
    title: t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.TITLE'),
  });
};

const segmentUrl = () =>
  `${window.chatwootConfig.hostURL}${frontendURL(
    `accounts/${accountId.value}/contacts/segments/${props.segmentsId}`
  )}`;

const useInAutomation = () =>
  router.push({
    name: 'automation_list',
    query: { [AUDIENCE_QUERY_PARAM]: props.activeSegment.id },
  });

const useInCampaign = () =>
  router.push({
    name: 'campaigns_whatsapp_index',
    query: { [AUDIENCE_QUERY_PARAM]: props.activeSegment.id },
  });

const copySegmentLink = async () => {
  try {
    await copyTextToClipboard(segmentUrl());
    useAlert(t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.LINK_COPIED'));
  } catch {
    // A clipboard the browser refuses (no permission, an insecure origin): say so and stay where we are.
    useAlert(t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.LINK_COPY_FAILED'));
  }
};

const closeAdvanceFiltersModal = () => {
  showFiltersModal.value = false;
  appliedFilter.value = [];
};

const clearFilters = async () => {
  emit('clearFilters');
};

const onApplyFilter = async payload => {
  payload = useSnakeCase(payload);
  segmentsQuery.value = filterQueryGenerator(payload);
  emit('applyFilter', filterQueryGenerator(payload));
  showFiltersModal.value = false;
};

const onUpdateSegment = async (payload, segmentName) => {
  payload = useSnakeCase(payload);
  const payloadData = {
    ...props.activeSegment,
    name: segmentName,
    query: filterQueryGenerator(payload),
  };
  await store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
};

const setParamsForEditSegmentModal = () => {
  return {
    countries,
    filterTypes: contactFilterItems,
    allCustomAttributes: useSnakeCase(contactAttributes.value),
    labels: labels.value || [],
  };
};

const initializeSegmentToFilterModal = segment => {
  const query = unref(segment)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    // Conversation and Commerce conditions (Lynomia Audience) rebuild from their own options.
    const audienceType = audienceFilterTypes.value.find(
      type => type.attributeKey === transformed.attributeKey
    );
    let values = [];
    if (audienceType) {
      values = audienceValuesForEdit(audienceType, transformed.values);
    } else if (Array.isArray(transformed.values)) {
      values = generateValuesForEditCustomViews(
        useSnakeCase(filter),
        setParamsForEditSegmentModal()
      );
    }

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
};

const onToggleFilters = async () => {
  appliedFilter.value = [];
  await loadAudienceFields();
  if (hasActiveSegments.value) {
    initializeSegmentToFilterModal(props.activeSegment);
  } else {
    appliedFilter.value = props.hasAppliedFilters
      ? [...appliedFilters.value]
      : [
          {
            attributeKey: 'name',
            filterOperator: 'equal_to',
            values: '',
            queryOperator: 'and',
            attributeModel: 'standard',
          },
        ];
  }
  showFiltersModal.value = true;
};

// "Start from scratch instead", from the preset gallery: the ordinary filter builder.
const buildAudienceFromScratch = () => {
  presetDialogRef.value?.close();
  onToggleFilters();
};

defineExpose({
  onToggleFilters,
});
</script>

<template>
  <ContactsHeader
    :show-search="showSearch"
    :search-value="searchValue"
    :active-sort="activeSort"
    :active-ordering="activeOrdering"
    :header-title="headerTitle"
    :is-segments-view="hasActiveSegments"
    :can-manage-segment="canManageSegment"
    :is-label-view="isLabelView"
    :is-active-view="isActiveView"
    :has-active-filters="hasAppliedFilters"
    :active-segment="hasActiveSegments ? activeSegment : null"
    :button-label="t('CONTACTS_LAYOUT.HEADER.MESSAGE_BUTTON')"
    @search="emit('search', $event)"
    @update:sort="emit('update:sort', $event)"
    @add="openCreateNewContactDialog"
    @import="openContactImportDialog"
    @export="openContactExportDialog"
    @filter="onToggleFilters"
    @create-segment="openCreateSegmentDialog"
    @delete-segment="openDeleteSegmentDialog"
    @duplicate-segment="duplicateSegment"
    @use-in-automation="useInAutomation"
    @use-in-campaign="useInCampaign"
    @copy-segment-link="copySegmentLink"
    @audience-preset="openPresetDialog"
  >
    <template #filter>
      <div
        class="absolute mt-1 inset-x-0 sm:inset-x-auto sm:ltr:right-0 sm:rtl:left-0 top-full"
      >
        <ContactsFilter
          v-if="showFiltersModal"
          v-model="appliedFilter"
          :segment-name="activeSegmentName"
          :is-segment-view="hasActiveSegments && canManageSegment"
          :shared-segment="isSharedSegment"
          :active-rule-count="activeSegment?.active_automation_rules_count || 0"
          :campaign-count="activeSegment?.campaigns_count || 0"
          @apply-filter="onApplyFilter"
          @update-segment="onUpdateSegment"
          @close="closeAdvanceFiltersModal"
          @clear-filters="clearFilters"
        />
      </div>
    </template>
  </ContactsHeader>

  <CreateNewContactDialog ref="createNewContactDialogRef" @create="onCreate" />
  <ContactExportDialog ref="contactExportDialogRef" @export="onExport" />
  <ContactImportDialog ref="contactImportDialogRef" @import="onImport" />
  <CreateSegmentDialog ref="createSegmentDialogRef" @create="onCreateSegment" />
  <RecipeDialog
    ref="presetDialogRef"
    :recipes="AUDIENCE_PRESETS"
    :title="t('RECIPES.AUDIENCE.TITLE')"
    :description="t('RECIPES.AUDIENCE.DESCRIPTION')"
    @create="createFromPreset"
    @scratch="buildAudienceFromScratch"
  />
  <DeleteSegmentDialog ref="deleteSegmentDialogRef" @delete="onDeleteSegment" />
</template>
