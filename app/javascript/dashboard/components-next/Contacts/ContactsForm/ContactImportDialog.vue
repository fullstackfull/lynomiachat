<script setup>
// Lynomia Contacts, phase C (docs/contacts/04-bulk-import.md). Two steps in one dialog rather than a wizard:
// choose what to import and what should happen to it, then look at what that would do before it happens.
//
// Nothing here parses or inserts anything. The preview and the import send the same payload to the server, which
// classifies the rows with the code the import itself then runs, so the counts shown are the counts that happen.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import ContactAPI from 'dashboard/api/contacts';
import countries from 'shared/constants/countries.js';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

const emit = defineEmits(['import']);

const SOURCES = { FILE: 'file', PASTE: 'paste' };
const STEPS = { OPTIONS: 'options', PREVIEW: 'preview' };
const DUPLICATE_POLICIES = ['update', 'keep'];
// In the order a reader wants them: what will be created, what already exists, and what will not happen.
const TILES = [
  'new_contact',
  'update_existing',
  'skip_existing',
  'duplicate_in_file',
  'no_identity',
  'invalid',
];
// A row the user needs to act on. The ones that will simply be created need no explaining.
const NOTEWORTHY = ['invalid', 'duplicate_in_file', 'no_identity'];

const { t } = useI18n();

const uiFlags = useMapGetter('contacts/getUIFlags');
const accountLabels = useMapGetter('labels/getLabels');
const isImporting = computed(() => uiFlags.value.isImporting);

const dialogRef = ref(null);
const fileInput = ref(null);

const step = ref(STEPS.OPTIONS);
const source = ref(SOURCES.FILE);
const selectedFile = ref(null);
const pastedNumbers = ref('');
const selectedLabels = ref([]);
const defaultCountry = ref('');
const duplicatePolicy = ref(DUPLICATE_POLICIES[0]);
const preview = ref(null);
const isPreviewing = ref(false);
const errorMessage = ref('');

const csvUrl = '/downloads/import-contacts-sample.csv';

const labelOptions = computed(() =>
  (accountLabels.value ?? []).map(({ title }) => ({
    value: title,
    label: title,
  }))
);

const countryOptions = computed(() =>
  countries.map(({ id, name, emoji }) => ({
    value: id,
    label: `${emoji} ${name}`,
  }))
);

const duplicatePolicyOptions = computed(() =>
  DUPLICATE_POLICIES.map(policy => ({
    value: policy,
    label: t(
      `CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DUPLICATES.${policy.toUpperCase()}`
    ),
  }))
);

const selectedFileName = computed(() => {
  const name = selectedFile.value?.name ?? '';
  const dot = name.lastIndexOf('.');
  const base = dot === -1 ? name : name.slice(0, dot);
  return base.length > 20 ? `${base.slice(0, 20)}...${name.slice(dot)}` : name;
});

const hasSource = computed(() =>
  source.value === SOURCES.FILE
    ? Boolean(selectedFile.value)
    : pastedNumbers.value.trim().length > 0
);

const payload = computed(() => ({
  file: source.value === SOURCES.FILE ? selectedFile.value : null,
  phoneNumbers: source.value === SOURCES.PASTE ? pastedNumbers.value : '',
  labels: selectedLabels.value,
  defaultCountry: defaultCountry.value,
  duplicatePolicy: duplicatePolicy.value,
}));

const counts = computed(() => preview.value?.counts ?? {});
const isPartialPreview = computed(
  () =>
    Boolean(preview.value) &&
    preview.value.total_rows > preview.value.previewed_rows
);
const noteworthyRows = computed(() =>
  (preview.value?.rows ?? []).filter(row =>
    NOTEWORTHY.includes(row.classification)
  )
);

const reasonFor = row => {
  const key = row.reason
    ? `CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.REASONS.${row.reason.toUpperCase()}`
    : null;
  return key ? t(key, { detail: row.detail ?? '' }) : '';
};

const resetState = () => {
  step.value = STEPS.OPTIONS;
  source.value = SOURCES.FILE;
  selectedFile.value = null;
  pastedNumbers.value = '';
  selectedLabels.value = [];
  defaultCountry.value = '';
  duplicatePolicy.value = DUPLICATE_POLICIES[0];
  preview.value = null;
  errorMessage.value = '';
  if (fileInput.value) fileInput.value.value = null;
};

const chooseSource = value => {
  source.value = value;
  errorMessage.value = '';
};

const handleFileClick = () => fileInput.value?.click();

const handleFileChange = () => {
  const file = fileInput.value?.files?.[0] ?? null;
  errorMessage.value = '';
  // Checked here as well as on the server: the file picker's `accept` is a suggestion the browser lets through.
  if (file && !file.name.toLowerCase().endsWith('.csv')) {
    selectedFile.value = null;
    errorMessage.value = t(
      'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.ERRORS.NOT_A_CSV'
    );
    return;
  }
  selectedFile.value = file;
};

const handleRemoveFile = () => {
  selectedFile.value = null;
  if (fileInput.value) fileInput.value.value = null;
};

const loadPreview = async () => {
  if (!hasSource.value) return;

  isPreviewing.value = true;
  errorMessage.value = '';
  try {
    const { data } = await ContactAPI.previewImport(payload.value);
    preview.value = data;
    step.value = STEPS.PREVIEW;
  } catch (error) {
    errorMessage.value =
      error.response?.data?.message ??
      error.response?.data?.error ??
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.ERRORS.PREVIEW_FAILED');
  } finally {
    isPreviewing.value = false;
  }
};

const startImport = () => emit('import', payload.value);

const back = () => {
  step.value = STEPS.OPTIONS;
};

const closeDialog = () => dialogRef.value?.close();

defineExpose({ dialogRef, resetState });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.TITLE')"
    @close="resetState"
  >
    <template #description>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DESCRIPTION') }}
        <a
          :href="csvUrl"
          target="_blank"
          rel="noopener noreferrer"
          download="import-contacts-sample.csv"
          class="text-n-blue-11"
        >
          {{
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DOWNLOAD_LABEL')
          }}
        </a>
      </p>
    </template>

    <div v-if="step === STEPS.OPTIONS" class="flex flex-col gap-5">
      <div class="flex flex-wrap gap-2" role="group">
        <Button
          v-for="value in [SOURCES.FILE, SOURCES.PASTE]"
          :key="value"
          sm
          type="button"
          :variant="source === value ? 'solid' : 'faded'"
          :color="source === value ? 'blue' : 'slate'"
          :label="
            t(
              `CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.SOURCES.${value.toUpperCase()}`
            )
          "
          @click="chooseSource(value)"
        />
      </div>

      <input
        ref="fileInput"
        type="file"
        accept="text/csv"
        class="hidden"
        @change="handleFileChange"
      />

      <div v-if="source === SOURCES.FILE" class="flex items-center gap-2">
        <label class="text-sm text-n-slate-12 whitespace-nowrap">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.LABEL') }}
        </label>
        <div class="flex items-center justify-between w-full gap-2">
          <span v-if="selectedFile" class="text-sm text-n-slate-12">
            {{ selectedFileName }}
          </span>
          <Button
            v-if="!selectedFile"
            sm
            type="button"
            :label="
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CHOOSE_FILE')
            "
            icon="i-lucide-upload"
            color="slate"
            variant="ghost"
            class="!w-fit"
            @click="handleFileClick"
          />
          <div v-else class="flex items-center gap-1">
            <Button
              sm
              type="button"
              :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CHANGE')"
              color="slate"
              variant="ghost"
              @click="handleFileClick"
            />
            <div class="w-px h-3 bg-n-strong" />
            <Button
              sm
              type="button"
              icon="i-lucide-trash"
              color="slate"
              variant="ghost"
              @click="handleRemoveFile"
            />
          </div>
        </div>
      </div>

      <div v-else class="flex flex-col gap-1">
        <label for="import-pasted-numbers" class="text-sm text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PASTE_LABEL') }}
        </label>
        <textarea
          id="import-pasted-numbers"
          v-model="pastedNumbers"
          rows="5"
          :placeholder="
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PASTE_PLACEHOLDER')
          "
          class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 border border-n-weak focus:border-n-brand focus:outline-none"
        />
        <p class="mb-0 text-xs text-n-slate-10">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PASTE_HINT') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.LABELS_LABEL') }}
        </label>
        <TagMultiSelectComboBox
          v-model="selectedLabels"
          :options="labelOptions"
          :placeholder="
            t(
              'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.LABELS_PLACEHOLDER'
            )
          "
          :empty-state="
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.NO_LABELS')
          "
        />
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-12">
            {{
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COUNTRY_LABEL')
            }}
          </label>
          <ComboBox
            v-model="defaultCountry"
            :options="countryOptions"
            :placeholder="
              t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COUNTRY_PLACEHOLDER'
              )
            "
          />
          <p class="mb-0 text-xs text-n-slate-10">
            {{
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COUNTRY_HINT')
            }}
          </p>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-12">
            {{
              t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DUPLICATES_LABEL'
              )
            }}
          </label>
          <ComboBox
            v-model="duplicatePolicy"
            :options="duplicatePolicyOptions"
          />
          <p class="mb-0 text-xs text-n-slate-10">
            {{
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DUPLICATES_HINT')
            }}
          </p>
        </div>
      </div>
    </div>

    <div v-else class="flex flex-col gap-4">
      <dl class="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <div
          v-for="tile in TILES"
          :key="tile"
          class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-2 dark:bg-n-solid-2"
        >
          <dt class="text-xs text-n-slate-11">
            {{
              t(
                `CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COUNTS.${tile.toUpperCase()}`
              )
            }}
          </dt>
          <dd class="mb-0 text-lg font-medium text-n-slate-12">
            {{ counts[tile] ?? 0 }}
          </dd>
        </div>
      </dl>

      <p class="mb-0 text-sm text-n-slate-11">
        {{
          isPartialPreview
            ? t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PARTIAL_PREVIEW',
                {
                  previewed: preview.previewed_rows,
                  total: preview.total_rows,
                }
              )
            : t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FULL_PREVIEW', {
                total: preview.total_rows,
              })
        }}
      </p>

      <p
        v-if="preview.default_country || preview.labels.length"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{
          t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CHOICES', {
            country:
              preview.default_country ||
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.NO_COUNTRY'),
            labels: preview.labels.length
              ? preview.labels.join(', ')
              : t(
                  'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.NO_LABELS_CHOSEN'
                ),
          })
        }}
      </p>

      <div v-if="noteworthyRows.length" class="overflow-y-auto max-h-64">
        <table class="w-full text-sm text-start">
          <thead class="text-xs text-n-slate-11">
            <tr>
              <th scope="col" class="py-1 font-medium text-start">
                {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.ROW') }}
              </th>
              <th scope="col" class="py-1 font-medium text-start">
                {{
                  t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.ROW_CONTACT')
                }}
              </th>
              <th scope="col" class="py-1 font-medium text-start">
                {{
                  t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.ROW_REASON')
                }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in noteworthyRows"
              :key="row.number"
              class="border-t border-n-weak"
            >
              <td class="py-1 text-n-slate-11">{{ row.number }}</td>
              <td class="py-1 text-n-slate-12">
                {{
                  row.email ||
                  row.phone_number ||
                  row.identifier ||
                  row.name ||
                  '—'
                }}
              </td>
              <td class="py-1 text-n-slate-11">{{ reasonFor(row) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <p v-if="errorMessage" class="mt-3 mb-0 text-sm text-n-ruby-11">
      {{ errorMessage }}
    </p>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          type="button"
          variant="link"
          class="h-10 hover:!no-underline hover:text-n-brand"
          :label="
            step === STEPS.OPTIONS
              ? t('DIALOG.BUTTONS.CANCEL')
              : t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.BACK')
          "
          @click="step === STEPS.OPTIONS ? closeDialog() : back()"
        />
        <Button
          v-if="step === STEPS.OPTIONS"
          type="button"
          color="blue"
          :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE')"
          :disabled="!hasSource || isPreviewing"
          :is-loading="isPreviewing"
          @click="loadPreview"
        />
        <Button
          v-else
          type="button"
          color="blue"
          :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.IMPORT')"
          :disabled="isImporting"
          :is-loading="isImporting"
          @click="startImport"
        />
      </div>
    </template>
  </Dialog>
</template>
