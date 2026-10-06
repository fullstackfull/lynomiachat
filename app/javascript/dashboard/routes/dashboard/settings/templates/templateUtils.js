import { TemplateTypeDetector } from 'dashboard/services/TemplateTypeDetector';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  PLATFORMS,
  TEMPLATE_TYPES,
} from 'dashboard/services/TemplateConstants';

const TEMPLATE_TYPE_KEYS = {
  [TEMPLATE_TYPES.WHATSAPP_TEXT]: 'TEXT',
  [TEMPLATE_TYPES.WHATSAPP_TEXT_HEADER]: 'TEXT',
  [TEMPLATE_TYPES.WHATSAPP_MEDIA_IMAGE]: 'IMAGE',
  [TEMPLATE_TYPES.WHATSAPP_MEDIA_VIDEO]: 'VIDEO',
  [TEMPLATE_TYPES.WHATSAPP_MEDIA_DOCUMENT]: 'DOCUMENT',
  [TEMPLATE_TYPES.WHATSAPP_INTERACTIVE]: 'CALL_TO_ACTION',
  [TEMPLATE_TYPES.WHATSAPP_COPY_CODE]: 'COPY_CODE',
  [TEMPLATE_TYPES.TWILIO_TEXT]: 'TEXT',
  [TEMPLATE_TYPES.TWILIO_MEDIA]: 'MEDIA',
  [TEMPLATE_TYPES.TWILIO_QUICK_REPLY]: 'QUICK_REPLY',
  [TEMPLATE_TYPES.TWILIO_CALL_TO_ACTION]: 'CALL_TO_ACTION',
  [TEMPLATE_TYPES.TWILIO_CARD]: 'CATALOG',
};

export const groupTemplates = templateRecords => {
  const groupedTemplates = new Map();

  templateRecords.forEach(({ template, inbox, lastUpdatedAt }) => {
    const platform =
      inbox.channel_type === INBOX_TYPES.TWILIO
        ? PLATFORMS.TWILIO
        : PLATFORMS.WHATSAPP;
    const providerAccountId =
      inbox.provider_config?.business_account_id ||
      inbox.account_sid ||
      inbox.id;
    const name = template.name || template.friendly_name;
    const providerTemplateIdentifier = template.id || template.content_sid;
    const templateIdentifier = providerTemplateIdentifier || name;
    const key = JSON.stringify(
      providerTemplateIdentifier
        ? [
            platform,
            providerAccountId,
            providerTemplateIdentifier,
            template.language,
          ]
        : [platform, inbox.id, name, template.language, template]
    );
    const searchableContent = JSON.stringify(
      template.components || template.types || template.body || []
    );
    const normalizedTemplate = {
      ...template,
      id: templateIdentifier,
      name,
      platform,
      key,
      inboxes: [inbox],
      inboxNames: inbox.name,
      lastUpdatedAt,
      searchableContent,
    };
    const existingTemplate = groupedTemplates.get(key);

    if (existingTemplate) {
      const inboxes = [...existingTemplate.inboxes, inbox];
      const incomingIsNewer =
        lastUpdatedAt &&
        (!existingTemplate.lastUpdatedAt ||
          new Date(lastUpdatedAt) > new Date(existingTemplate.lastUpdatedAt));

      groupedTemplates.set(key, {
        ...(incomingIsNewer ? normalizedTemplate : existingTemplate),
        inboxes,
        inboxNames: inboxes.map(item => item.name).join(', '),
        lastUpdatedAt: incomingIsNewer
          ? lastUpdatedAt
          : existingTemplate.lastUpdatedAt,
      });
      return;
    }

    groupedTemplates.set(key, normalizedTemplate);
  });

  return [...groupedTemplates.values()].sort((first, second) =>
    first.name.localeCompare(second.name)
  );
};

export const formatTemplateLabel = value => {
  if (!value) return '—';

  return value
    .toLowerCase()
    .replaceAll('_', ' ')
    .replace(/\b\w/g, character => character.toUpperCase());
};

export const formatTemplateLanguage = language => {
  if (!language) return '—';

  const locale = language.replace('_', '-');
  const languageCode = locale.split('-')[0];
  const displayName = new Intl.DisplayNames([locale], {
    type: 'language',
  }).of(languageCode);

  return `${displayName} (${locale})`;
};

export const formatTemplateDate = value => {
  if (!value) return '—';

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
  }).format(new Date(value));
};

// The meaning of a template's status, for `Label` to paint. Returning the semantic rather than the
// class string is what lets one badge component serve every status in the product.
export const templateStatusTone = status => {
  const tones = {
    approved: { tone: 'success', variant: 'solid' },
    pending: { tone: 'warning', variant: 'solid' },
    rejected: { tone: 'danger', variant: 'solid' },
    paused: { tone: 'warning', variant: 'solid' },
    disabled: { tone: 'neutral', variant: 'subtle' },
    // Lynomia Template Manager states. A draft and a submission that failed are ours; the rest are WhatsApp's.
    unsubmitted: { tone: 'neutral', variant: 'subtle' },
    submitting: { tone: 'info', variant: 'subtle' },
    submission_failed: { tone: 'danger', variant: 'subtle' },
    missing: { tone: 'danger', variant: 'subtle' },
    in_appeal: { tone: 'warning', variant: 'subtle' },
    pending_deletion: { tone: 'warning', variant: 'subtle' },
    deleted: { tone: 'neutral', variant: 'subtle' },
    archived: { tone: 'neutral', variant: 'subtle' },
    limit_exceeded: { tone: 'danger', variant: 'subtle' },
  };

  return tones[status?.toLowerCase()] || { tone: 'neutral', variant: 'subtle' };
};

// What WhatsApp publishes, mirrored here only so an input can stop typing at the limit instead of letting a review
// cycle find it. The authority is the server (custom/app/services/whatsapp/templates/validator.rb), which is what a
// submit is refused on; these are the same numbers, named once on the client.
export const TEMPLATE_LIMITS = {
  name: 512,
  headerText: 60,
  body: 1024,
  footer: 60,
  buttonText: 25,
  buttonUrl: 2000,
  buttonPhone: 20,
  buttonCopyCode: 15,
  buttons: 10,
};

// The one place a record becomes a word. A draft is never called "pending": WhatsApp has not seen it, so it has no
// status of WhatsApp's at all. A submission WhatsApp refused at the API is not "rejected" either -- it never reached
// review. Everything else is WhatsApp's own status, lowercased, so a value it adds later still renders.
export const templateState = record => {
  if (record.state === 'draft') return 'unsubmitted';
  if (record.state === 'submitting') {
    return record.submission_error ? 'submission_failed' : 'submitting';
  }
  if (record.missing_at_meta) return 'missing';

  return (record.meta_status || 'unsubmitted').toLowerCase();
};

// Every state the manager can show, so an unknown one from WhatsApp falls back to its own formatted name instead of
// rendering a translation key.
const STATUS_KEYS = [
  'UNSUBMITTED',
  'SUBMITTING',
  'SUBMISSION_FAILED',
  'MISSING',
  'APPROVED',
  'PENDING',
  'REJECTED',
  'PAUSED',
  'DISABLED',
  'IN_APPEAL',
  'PENDING_DELETION',
  'DELETED',
  'ARCHIVED',
  'LIMIT_EXCEEDED',
];

export const templateStatusLabelKey = status => {
  const key = (status || 'unsubmitted').toUpperCase();

  return STATUS_KEYS.includes(key)
    ? `WHATSAPP_TEMPLATE_MGMT.STATUSES.${key}`
    : null;
};

// The manager's API shape, rendered by the same card and preview the synced list already uses. `inboxes` has to be
// whole inbox records, because that is what ChannelIcon reads; the API sends ids and names, so the caller resolves
// them against the inboxes it already has in the store.
export const templateRowFromRecord = (record, inboxesById) => {
  const inboxes = (record.inboxes || [])
    .map(inbox => inboxesById[inbox.id] || { id: inbox.id, name: inbox.name })
    .filter(Boolean);

  return {
    ...record,
    platform: PLATFORMS.WHATSAPP,
    key: `whatsapp-${record.id}`,
    status: templateState(record),
    inboxes,
    inboxNames: (record.inboxes || []).map(inbox => inbox.name).join(', '),
    lastUpdatedAt: record.last_seen_at ? record.last_seen_at * 1000 : null,
    searchableContent: JSON.stringify(record.components || []),
    isManaged: true,
  };
};

export const templateTypeKey = template => {
  const type =
    template.platform === PLATFORMS.TWILIO
      ? TemplateTypeDetector.detectTwilioType(template)
      : TemplateTypeDetector.detectWhatsAppType(template);
  return TEMPLATE_TYPE_KEYS[type] || 'TEXT';
};
