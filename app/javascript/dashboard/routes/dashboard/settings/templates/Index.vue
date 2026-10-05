<script setup>
import { computed, onActivated, onDeactivated, ref } from 'vue';
import { picoSearch } from '@chatwoot/pico-search';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import { INBOX_TYPES, TWILIO_CHANNEL_MEDIUM } from 'dashboard/helper/inbox';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsAppTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import TemplateBuilderDialog from './TemplateBuilderDialog.vue';
import TemplateCard from './TemplateCard.vue';
import TemplatePreviewDrawer from './TemplatePreviewDrawer.vue';
import {
  formatTemplateDate,
  formatTemplateLanguage,
  groupTemplates,
  templateRowFromRecord,
  templateStatusLabelKey,
  templateTypeKey,
} from './templateUtils';

const FUZZY_SEARCH_KEYS = [
  { name: 'name', weight: 4 },
  'category',
  'language',
  'status',
  'inboxNames',
  'searchableContent',
];

const store = useStore();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
// Managed templates come from the one shared query, with their state and what may be done to them. Twilio's content
// templates keep their own per-inbox path, unchanged: the manager is WhatsApp's, and dropping Twilio from this page
// would be a regression.
const managedTemplates = ref([]);
const twilioTemplates = ref([]);
const wabaContexts = ref([]);
const searchQuery = ref('');
const selectedInboxId = ref('all');
const selectedLanguage = ref('all');
const selectedType = ref('all');
const selectedStatus = ref('all');
const selectedTemplate = ref(null);
const editingTemplate = ref(null);
const pendingAction = ref(null);
const openFilterMenu = ref(null);
const previewPanelRef = ref(null);
const builderRef = ref(null);
const confirmRef = ref(null);
const templateRecordsByInboxId = new Map();
const lastSyncAttemptsByInboxId = ref({});
const isSyncing = ref(false);
const isActing = ref(false);

const templates = computed(() =>
  [...managedTemplates.value, ...twilioTemplates.value].sort((first, second) =>
    String(first.name).localeCompare(String(second.name))
  )
);
const {
  run: runTemplateRequest,
  abort: abortTemplateRequest,
  isPending: isLoading,
} = useAbortableRequest();

const hasTemplates = computed(() => templates.value.length > 0);

const lastSyncAttemptAt = computed(() => {
  const timestamps = [
    ...Object.values(lastSyncAttemptsByInboxId.value).map(value =>
      new Date(value).getTime()
    ),
    ...wabaContexts.value.map(waba => (waba.last_synced_at || 0) * 1000),
  ].filter(value => Number.isFinite(value) && value > 0);

  return timestamps.length ? new Date(Math.max(...timestamps)) : null;
});

const typeLabels = computed(() => ({
  TEXT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.TEXT'),
  IMAGE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.IMAGE'),
  VIDEO: t('WHATSAPP_TEMPLATE_MGMT.TYPES.VIDEO'),
  DOCUMENT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.DOCUMENT'),
  MEDIA: t('WHATSAPP_TEMPLATE_MGMT.TYPES.MEDIA'),
  QUICK_REPLY: t('WHATSAPP_TEMPLATE_MGMT.TYPES.QUICK_REPLY'),
  CALL_TO_ACTION: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CALL_TO_ACTION'),
  CATALOG: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CATALOG'),
  COPY_CODE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.COPY_CODE'),
}));

const whatsappInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP ||
      (inbox.channel_type === INBOX_TYPES.TWILIO &&
        inbox.medium === TWILIO_CHANNEL_MEDIUM.WHATSAPP)
  )
);

const twilioWhatsappInboxes = computed(() =>
  whatsappInboxes.value.filter(
    inbox => inbox.channel_type === INBOX_TYPES.TWILIO
  )
);

// A template is created in a WhatsApp Business Account, which is a property of a WhatsApp Cloud inbox.
const builderInboxOptions = computed(() =>
  inboxes.value
    .filter(
      inbox =>
        inbox.channel_type === INBOX_TYPES.WHATSAPP &&
        inbox.provider_config?.business_account_id
    )
    .map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const inboxesById = computed(() =>
  Object.fromEntries(inboxes.value.map(inbox => [inbox.id, inbox]))
);

const inboxOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_INBOXES'),
  },
  ...whatsappInboxes.value.map(inbox => ({
    value: String(inbox.id),
    label: inbox.name,
  })),
]);

const languageOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_LANGUAGES'),
  },
  ...[...new Set(templates.value.map(template => template.language))]
    .filter(Boolean)
    .sort()
    .map(language => ({
      value: language,
      label: formatTemplateLanguage(language),
    })),
]);

const typeOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_TYPES'),
  },
  ...[...new Set(templates.value.map(templateTypeKey))]
    .map(type => ({
      value: type,
      label: typeLabels.value[type],
    }))
    .sort((first, second) => first.label.localeCompare(second.label)),
]);

const statusOptions = computed(() => [
  {
    value: 'all',
    label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_STATUSES'),
  },
  ...[...new Set(templates.value.map(template => template.status))]
    .filter(Boolean)
    .map(status => ({
      value: status,
      label: templateStatusLabelKey(status)
        ? t(templateStatusLabelKey(status))
        : status,
    }))
    .sort((first, second) => first.label.localeCompare(second.label)),
]);

const filterMenus = computed(() =>
  [
    {
      key: 'status',
      icon: 'i-lucide-circle-dot',
      options: statusOptions.value,
      active: selectedStatus.value,
    },
    {
      key: 'inbox',
      icon: 'i-lucide-inbox',
      options: inboxOptions.value,
      active: selectedInboxId.value,
    },
    {
      key: 'language',
      icon: 'i-lucide-languages',
      options: languageOptions.value,
      active: selectedLanguage.value,
    },
    {
      key: 'type',
      icon: 'i-lucide-layout-template',
      options: typeOptions.value,
      active: selectedType.value,
    },
  ].map(menu => {
    const items = menu.options.map(option => ({
      ...option,
      action: menu.key,
      isSelected: option.value === menu.active,
    }));

    return {
      ...menu,
      items,
      selected: items.find(item => item.isSelected) || items[0],
    };
  })
);

const closeFilterMenu = () => {
  openFilterMenu.value = null;
};

const toggleFilterMenu = key => {
  openFilterMenu.value = openFilterMenu.value === key ? null : key;
};

const openPreview = template => {
  selectedTemplate.value = template;
  previewPanelRef.value?.open();
};

const handleFilterAction = ({ action, value }) => {
  closeFilterMenu();
  if (action === 'inbox') selectedInboxId.value = value;
  else if (action === 'language') selectedLanguage.value = value;
  else if (action === 'status') selectedStatus.value = value;
  else selectedType.value = value;
};

const filteredTemplates = computed(() => {
  let records = templates.value;

  if (selectedInboxId.value !== 'all') {
    records = records.filter(template =>
      template.inboxes.some(inbox => String(inbox.id) === selectedInboxId.value)
    );
  }

  if (selectedLanguage.value !== 'all') {
    records = records.filter(
      template => template.language === selectedLanguage.value
    );
  }

  if (selectedType.value !== 'all') {
    records = records.filter(
      template => templateTypeKey(template) === selectedType.value
    );
  }

  if (selectedStatus.value !== 'all') {
    records = records.filter(
      template => template.status === selectedStatus.value
    );
  }

  const query = searchQuery.value.trim();
  if (!query) return records;

  const normalizedQuery = query.toLowerCase();
  const contentMatches = records.filter(template =>
    [template.name, template.searchableContent].some(value =>
      value?.toLowerCase().includes(normalizedQuery)
    )
  );
  if (contentMatches.length) return contentMatches;

  return picoSearch(records, query, FUZZY_SEARCH_KEYS);
});

const showSearch = computed(() =>
  Boolean(filteredTemplates.value.length || searchQuery.value)
);

const fetchTemplates = async () => {
  try {
    await runTemplateRequest(async signal => {
      const didFetchInboxes = await store.dispatch('inboxes/get');
      if (!didFetchInboxes) throw new Error();
      if (signal.aborted) return;

      const inboxesToFetch = [...twilioWhatsappInboxes.value];
      // Started alongside the Twilio fetches and awaited below. The catch is what keeps an aborted request from
      // becoming an unhandled rejection when this runner returns early.
      const managed = WhatsAppTemplatesAPI.get({ signal }).catch(error => {
        if (isAbortError(error)) return { data: {} };
        throw error;
      });
      const responses = await Promise.allSettled(
        inboxesToFetch.map(async inbox => {
          const { data } = await InboxesAPI.getMessageTemplates(
            inbox.id,
            {},
            { signal }
          );

          if (!Array.isArray(data.payload)) {
            throw new TypeError();
          }

          return {
            inboxId: inbox.id,
            lastSyncAttemptAt: data.meta?.last_sync_attempt_at,
            records: data.payload.map(template => ({
              template,
              inbox,
              lastUpdatedAt: data.meta?.last_sync_attempt_at,
            })),
          };
        })
      );

      if (signal.aborted) return;

      const successfulResponses = responses.filter(
        response => response.status === 'fulfilled'
      );
      const activeInboxIds = new Set(inboxesToFetch.map(inbox => inbox.id));
      const nextLastSyncAttempts = {
        ...lastSyncAttemptsByInboxId.value,
      };

      templateRecordsByInboxId.forEach((_, inboxId) => {
        if (!activeInboxIds.has(inboxId)) {
          templateRecordsByInboxId.delete(inboxId);
          delete nextLastSyncAttempts[inboxId];
        }
      });
      successfulResponses.forEach(({ value }) => {
        templateRecordsByInboxId.set(value.inboxId, value.records);
        nextLastSyncAttempts[value.inboxId] = value.lastSyncAttemptAt;
      });
      lastSyncAttemptsByInboxId.value = nextLastSyncAttempts;
      twilioTemplates.value = groupTemplates(
        [...templateRecordsByInboxId.values()].flat()
      );

      const { data } = await managed;
      if (signal.aborted || !data.payload) return;
      managedTemplates.value = data.payload.map(record =>
        templateRowFromRecord(record, inboxesById.value)
      );
      wabaContexts.value = data.meta?.whatsapp_business_accounts || [];

      if (
        !inboxOptions.value.some(({ value }) => value === selectedInboxId.value)
      )
        selectedInboxId.value = 'all';
      if (
        !languageOptions.value.some(
          ({ value }) => value === selectedLanguage.value
        )
      )
        selectedLanguage.value = 'all';
      if (!typeOptions.value.some(({ value }) => value === selectedType.value))
        selectedType.value = 'all';
      if (
        !statusOptions.value.some(({ value }) => value === selectedStatus.value)
      )
        selectedStatus.value = 'all';

      if (responses.some(response => response.status === 'rejected')) {
        const errorMessage = successfulResponses.length
          ? t('WHATSAPP_TEMPLATE_MGMT.PARTIAL_FETCH_ERROR')
          : t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR');
        useAlert(errorMessage);
      }
    });
  } catch {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR'));
  }
};

const CONFIRMATIONS = {
  submit: {
    title: 'WHATSAPP_TEMPLATE_MGMT.CONFIRM.SUBMIT.TITLE',
    description: 'WHATSAPP_TEMPLATE_MGMT.CONFIRM.SUBMIT.DESCRIPTION',
    confirm: 'WHATSAPP_TEMPLATE_MGMT.CONFIRM.SUBMIT.CONFIRM',
  },
  delete: {
    title: 'WHATSAPP_TEMPLATE_MGMT.CONFIRM.DELETE.TITLE',
    description: 'WHATSAPP_TEMPLATE_MGMT.CONFIRM.DELETE.DESCRIPTION_REMOTE',
    descriptionDraft: 'WHATSAPP_TEMPLATE_MGMT.CONFIRM.DELETE.DESCRIPTION_DRAFT',
    confirm: 'WHATSAPP_TEMPLATE_MGMT.CONFIRM.DELETE.CONFIRM',
  },
};

const confirmation = computed(() => {
  const action = pendingAction.value;
  if (!action) return null;

  const copy = CONFIRMATIONS[action.name];
  const isDraft = action.template.state === 'draft';

  return {
    title: t(copy.title, { name: action.template.name }),
    description: t(
      isDraft && copy.descriptionDraft
        ? copy.descriptionDraft
        : copy.description
    ),
    confirmLabel: t(copy.confirm),
  };
});

const alertError = error => {
  const code = error?.response?.data?.error?.code;
  useAlert(
    code
      ? t(`WHATSAPP_TEMPLATE_MGMT.ERRORS.${code}`)
      : t('WHATSAPP_TEMPLATE_MGMT.ERRORS.GENERIC')
  );
};

const openBuilder = template => {
  editingTemplate.value = template || null;
  builderRef.value?.open();
};

const duplicateTemplate = async template => {
  try {
    const { data } = await WhatsAppTemplatesAPI.duplicate(template.id);
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.DUPLICATED', { name: template.name }));
    await fetchTemplates();
    openBuilder(
      managedTemplates.value.find(record => record.id === data.id) || null
    );
  } catch (error) {
    alertError(error);
  }
};

const runPendingAction = async () => {
  const action = pendingAction.value;
  if (!action || isActing.value) return;

  isActing.value = true;
  try {
    if (action.name === 'submit') {
      await WhatsAppTemplatesAPI.submit(action.template.id);
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.SUBMITTED'));
    } else {
      await WhatsAppTemplatesAPI.delete(action.template.id);
      useAlert(t('WHATSAPP_TEMPLATE_MGMT.DELETED'));
      previewPanelRef.value?.close();
    }
    await fetchTemplates();
  } catch (error) {
    alertError(error);
  } finally {
    isActing.value = false;
    pendingAction.value = null;
  }
};

const handleTemplateAction = (action, template) => {
  if (action === 'edit') return openBuilder(template);
  if (action === 'duplicate') return duplicateTemplate(template);

  pendingAction.value = { name: action, template };
  return confirmRef.value?.open();
};

const handleBuilderSaved = async () => {
  await fetchTemplates();
  const refreshed = managedTemplates.value.find(
    record => record.id === selectedTemplate.value?.id
  );
  if (refreshed) selectedTemplate.value = refreshed;
};

const syncTemplates = async () => {
  if (isSyncing.value) return;

  isSyncing.value = true;

  const responses = await Promise.allSettled(
    whatsappInboxes.value.map(inbox =>
      store.dispatch('inboxes/syncTemplates', inbox.id)
    )
  );
  const failedCount = responses.filter(
    response => response.status === 'rejected'
  ).length;

  if (!failedCount) {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.SYNC_SUCCESS'));
  } else if (failedCount < responses.length) {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.PARTIAL_SYNC_ERROR'));
  } else {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.SYNC_ERROR'));
  }

  isSyncing.value = false;
};

onActivated(fetchTemplates);
onDeactivated(abortTemplateRequest);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('WHATSAPP_TEMPLATE_MGMT.LOADING')"
    :no-records-found="!templates.length"
    :no-records-message="$t('WHATSAPP_TEMPLATE_MGMT.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('WHATSAPP_TEMPLATE_MGMT.TITLE')"
        :description="$t('WHATSAPP_TEMPLATE_MGMT.DESCRIPTION')"
        :link-text="$t('WHATSAPP_TEMPLATE_MGMT.LEARN_MORE')"
        feature-name="whatsapp_templates"
        :search-placeholder="
          showSearch ? $t('WHATSAPP_TEMPLATE_MGMT.SEARCH_PLACEHOLDER') : ''
        "
      >
        <template v-if="lastSyncAttemptAt" #meta>
          <span class="text-xs text-n-slate-10">
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.LAST_SYNC_ATTEMPT', {
                date: formatTemplateDate(lastSyncAttemptAt),
              })
            }}
          </span>
        </template>
        <template #tabs>
          <div
            v-if="hasTemplates"
            v-on-click-outside="closeFilterMenu"
            class="flex items-center gap-2"
          >
            <div v-for="menu in filterMenus" :key="menu.key" class="relative">
              <Button
                :icon="menu.icon"
                color="slate"
                size="sm"
                :class="{ 'bg-n-slate-9/10': openFilterMenu === menu.key }"
                aria-haspopup="menu"
                :aria-expanded="openFilterMenu === menu.key"
                @click="toggleFilterMenu(menu.key)"
              >
                <span class="min-w-0 truncate">{{ menu.selected.label }}</span>
                <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
              </Button>
              <DropdownMenu
                v-if="openFilterMenu === menu.key"
                :menu-items="menu.items"
                class="mt-2 min-w-52 top-full start-0"
                @action="handleFilterAction"
              />
            </div>
          </div>
        </template>
        <template v-if="filteredTemplates.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{
              $t('WHATSAPP_TEMPLATE_MGMT.COUNT', {
                n: filteredTemplates.length,
              })
            }}
          </span>
        </template>
        <template #actions>
          <div class="flex items-center gap-2">
            <Button
              :label="$t('WHATSAPP_TEMPLATE_MGMT.SYNC_TEMPLATES')"
              icon="i-lucide-refresh-cw"
              color="slate"
              size="sm"
              :is-loading="isSyncing"
              :disabled="!whatsappInboxes.length || isSyncing"
              @click="syncTemplates"
            />
            <Button
              :label="$t('WHATSAPP_TEMPLATE_MGMT.CREATE')"
              icon="i-lucide-plus"
              size="sm"
              data-test-id="create-template"
              :disabled="!builderInboxOptions.length"
              @click="openBuilder(null)"
            />
          </div>
        </template>
      </BaseSettingsHeader>
    </template>

    <template #emptyState>
      <div class="flex flex-col items-center gap-3 p-10 text-center">
        <span class="text-heading-3 text-n-slate-12">
          {{
            builderInboxOptions.length
              ? $t('WHATSAPP_TEMPLATE_MGMT.EMPTY')
              : $t('WHATSAPP_TEMPLATE_MGMT.EMPTY_NO_INBOX')
          }}
        </span>
        <span class="max-w-md text-body-main text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.EMPTY_DESCRIPTION') }}
        </span>
        <Button
          v-if="builderInboxOptions.length"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.CREATE')"
          icon="i-lucide-plus"
          data-test-id="create-template-empty"
          @click="openBuilder(null)"
        />
      </div>
    </template>

    <template #body>
      <div
        v-if="!filteredTemplates.length"
        class="flex items-center justify-center p-8"
      >
        <span class="text-base text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.NO_RESULTS') }}
        </span>
      </div>

      <div v-else class="border-t divide-y divide-n-weak border-n-weak">
        <TemplateCard
          v-for="template in filteredTemplates"
          :key="template.key"
          :template="template"
          @preview="openPreview(template)"
          @action="handleTemplateAction($event, template)"
        />
      </div>
    </template>

    <TemplatePreviewDrawer
      ref="previewPanelRef"
      :template="selectedTemplate"
      @action="handleTemplateAction($event, selectedTemplate)"
    />

    <TemplateBuilderDialog
      ref="builderRef"
      :template="editingTemplate"
      :inbox-options="builderInboxOptions"
      @saved="handleBuilderSaved"
    />

    <Dialog
      ref="confirmRef"
      type="alert"
      :title="confirmation?.title"
      :description="confirmation?.description"
      :confirm-button-label="confirmation?.confirmLabel"
      :is-loading="isActing"
      @confirm="runPendingAction"
      @close="pendingAction = null"
    />
  </SettingsLayout>
</template>
