export const IMPORT_SOURCES = [
  {
    value: 'intercom',
    label: 'Intercom',
    icon: '/dashboard/images/integrations/intercom.png',
  },
  {
    value: 'freshdesk',
    label: 'Freshdesk',
    iconClass: 'i-lucide-life-buoy',
    requiresDomain: true,
  },
];

export const importSourceConfigFor = provider =>
  IMPORT_SOURCES.find(source => source.value === provider);

// Intercom and Freshdesk are product names and stay as they are; the file fallback is a phrase, so it
// carries a key for the caller to translate instead of a baked-in English label.
const DEFAULT_IMPORT_SOURCE = {
  value: 'file',
  labelKey: 'DATA_IMPORTS.SOURCE.FILE',
  iconClass: 'i-lucide-file-text',
};

export const importSourceFor = dataImport =>
  importSourceConfigFor(dataImport?.source_provider) || DEFAULT_IMPORT_SOURCE;
