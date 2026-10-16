<script>
import LabelDropdownItem from './LabelDropdownItem.vue';
import Hotkey from 'dashboard/components/base/Hotkey.vue';
import AddLabelModal from 'dashboard/routes/dashboard/settings/labels/AddLabel.vue';
import { picoSearch } from '@chatwoot/pico-search';
import { sanitizeLabel } from 'shared/helpers/sanitizeData';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    LabelDropdownItem,
    AddLabelModal,
    Hotkey,
    NextButton,
  },

  props: {
    accountLabels: {
      type: Array,
      default: () => [],
    },
    selectedLabels: {
      type: Array,
      default: () => [],
    },
    allowCreation: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update', 'add', 'remove'],

  data() {
    return {
      search: '',
    };
  },

  computed: {
    createLabelPlaceholder() {
      const label = this.$t('CONTACT_PANEL.LABELS.LABEL_SELECT.CREATE_LABEL');
      return this.search ? `${label}:` : label;
    },

    filteredActiveLabels() {
      if (!this.search) return this.accountLabels;

      return picoSearch(this.accountLabels, this.search, ['title']);
    },

    noResult() {
      return this.filteredActiveLabels.length === 0;
    },

    hasExactMatchInResults() {
      return this.filteredActiveLabels.some(
        label => label.title === this.search
      );
    },

    shouldShowCreate() {
      return this.allowCreation && this.filteredActiveLabels.length < 3;
    },

    parsedSearch() {
      return sanitizeLabel(this.search);
    },
  },

  mounted() {
    this.focusInput();
  },

  methods: {
    focusInput() {
      this.$refs.searchbar.focus();
    },

    updateLabels(label) {
      this.$emit('update', label);
    },

    onAdd(label) {
      this.$emit('add', label);
    },

    onRemove(label) {
      this.$emit('remove', label);
    },

    onAddRemove(label) {
      if (this.selectedLabels.includes(label.title)) {
        this.onRemove(label.title);
      } else {
        this.onAdd(label);
      }
    },

    showCreateModal() {
      // A real `<dialog>` now, so it lands in the top layer instead of inside this dropdown's
      // stacking context, and it brings a focus trap the old modal did not have.
      this.$refs.addLabelDialog?.open();
    },
  },
};
</script>

<template>
  <div class="flex flex-col w-full max-h-[12.5rem]">
    <div class="flex items-center justify-center mb-1">
      <h4
        class="flex-grow m-0 overflow-hidden text-sm text-n-slate-12 whitespace-nowrap text-ellipsis"
      >
        {{ $t('CONTACT_PANEL.LABELS.LABEL_SELECT.TITLE') }}
      </h4>
      <Hotkey
        custom-class="border border-solid text-n-slate-12 bg-n-slate-2 text-xxs border-n-strong flex-shrink-0"
      >
        {{ 'L' }}
      </Hotkey>
    </div>
    <div class="flex-auto flex-grow-0 flex-shrink-0 mb-2 max-h-8">
      <input
        ref="searchbar"
        v-model="search"
        type="text"
        class="search-input"
        autofocus="true"
        :placeholder="$t('CONTACT_PANEL.LABELS.LABEL_SELECT.PLACEHOLDER')"
      />
    </div>
    <div
      class="flex items-start justify-start flex-auto flex-grow flex-shrink overflow-auto"
    >
      <div class="w-full my-1">
        <woot-dropdown-menu>
          <LabelDropdownItem
            v-for="label in filteredActiveLabels"
            :key="label.title"
            :title="label.title"
            :color="label.color"
            :selected="selectedLabels.includes(label.title)"
            @select-label="onAddRemove(label)"
          />
        </woot-dropdown-menu>
        <div
          v-if="noResult"
          class="flex justify-center py-4 px-2.5 font-medium text-xs text-n-slate-11"
        >
          {{ $t('CONTACT_PANEL.LABELS.LABEL_SELECT.NO_RESULT') }}
        </div>
        <div
          v-if="allowCreation && shouldShowCreate"
          class="flex pt-1 border-t border-solid border-n-weak"
        >
          <NextButton
            icon="i-lucide-plus"
            slate
            sm
            ghost
            :label="`${createLabelPlaceholder} ${parsedSearch}`"
            :disabled="hasExactMatchInResults"
            @click="showCreateModal"
          />

          <AddLabelModal ref="addLabelDialog" :prefill-title="parsedSearch" />
        </div>
      </div>
    </div>
  </div>
</template>
