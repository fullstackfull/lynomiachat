import { computed } from 'vue';
import { FIXTURES } from './fixtures';

export const useAudienceFilterTypes = () => ({
  audienceFilterTypes: computed(() => []),
  loadAudienceFields: () => Promise.resolve(),
  unreadContacts: computed(() => 0),
  commerceStores: computed(() => FIXTURES.stores),
  commerceCurrencies: computed(() => FIXTURES.currencies),
});

export const audienceValuesForEdit = () => [];
