import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  groupTemplates,
  templateRowFromRecord,
  templateState,
  templateStatusLabelKey,
} from '../templateUtils';

const whatsappInbox = ({
  id,
  name,
  businessAccountId,
  provider = 'whatsapp_cloud',
}) => ({
  id,
  name,
  channel_type: INBOX_TYPES.WHATSAPP,
  provider,
  provider_config: { business_account_id: businessAccountId },
});

describe('#groupTemplates', () => {
  it('uses the newest cache fields when grouping a shared provider template', () => {
    const olderInbox = whatsappInbox({
      id: 1,
      name: 'Older inbox',
      businessAccountId: 'waba-1',
    });
    const newerInbox = whatsappInbox({
      id: 2,
      name: 'Newer inbox',
      businessAccountId: 'waba-1',
    });

    const result = groupTemplates([
      {
        inbox: olderInbox,
        lastUpdatedAt: '2026-08-01T10:00:00.000Z',
        template: {
          id: 'template-1',
          name: 'order_update',
          language: 'en_US',
          status: 'pending',
          components: [{ type: 'BODY', text: 'Old body' }],
        },
      },
      {
        inbox: newerInbox,
        lastUpdatedAt: '2026-08-02T10:00:00.000Z',
        template: {
          id: 'template-1',
          name: 'order_update',
          language: 'en_US',
          status: 'approved',
          components: [{ type: 'BODY', text: 'New body' }],
        },
      },
    ]);

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      status: 'approved',
      components: [{ type: 'BODY', text: 'New body' }],
      inboxNames: 'Older inbox, Newer inbox',
      lastUpdatedAt: '2026-08-02T10:00:00.000Z',
    });
    expect(result[0].inboxes).toEqual([olderInbox, newerInbox]);
  });

  it('keeps delimiter-containing provider identities separate', () => {
    const result = groupTemplates([
      {
        inbox: whatsappInbox({
          id: 1,
          name: 'Delimiter A',
          businessAccountId: 'account:a',
        }),
        template: {
          id: 'template',
          name: 'delimiter_a',
          language: 'en_US',
        },
      },
      {
        inbox: whatsappInbox({
          id: 2,
          name: 'Delimiter B',
          businessAccountId: 'account',
        }),
        template: {
          id: 'a:template',
          name: 'delimiter_b',
          language: 'en_US',
        },
      },
    ]);

    expect(result).toHaveLength(2);
    expect(result.map(template => template.inboxes)).toEqual([
      [
        whatsappInbox({
          id: 1,
          name: 'Delimiter A',
          businessAccountId: 'account:a',
        }),
      ],
      [
        whatsappInbox({
          id: 2,
          name: 'Delimiter B',
          businessAccountId: 'account',
        }),
      ],
    ]);
  });

  it('scopes templates without provider identities to their inbox and content', () => {
    const result = groupTemplates([
      {
        inbox: whatsappInbox({
          id: 1,
          name: 'First inbox',
          businessAccountId: 'waba-1',
        }),
        template: {
          name: 'shared_name',
          language: 'en_US',
          components: [{ type: 'BODY', text: 'First body' }],
        },
      },
      {
        inbox: whatsappInbox({
          id: 2,
          name: 'Second inbox',
          businessAccountId: 'waba-1',
        }),
        template: {
          name: 'shared_name',
          language: 'en_US',
          components: [{ type: 'BODY', text: 'Second body' }],
        },
      },
    ]);

    expect(result).toHaveLength(2);
    expect(result.map(template => template.searchableContent)).toEqual([
      '[{"type":"BODY","text":"First body"}]',
      '[{"type":"BODY","text":"Second body"}]',
    ]);
  });
});

describe('#templateState', () => {
  // A draft is never called "pending": WhatsApp has not seen it, so it has none of WhatsApp's statuses at all.
  it('calls a draft unsubmitted, not pending', () => {
    expect(templateState({ state: 'draft', meta_status: null })).toBe(
      'unsubmitted'
    );
  });

  it('separates a submission in flight from one WhatsApp refused', () => {
    expect(templateState({ state: 'submitting' })).toBe('submitting');
    expect(
      templateState({ state: 'submitting', submission_error: 'NAME_TAKEN' })
    ).toBe('submission_failed');
  });

  it('reports a template the last sync did not see, whatever its last status was', () => {
    expect(
      templateState({
        state: 'remote',
        meta_status: 'APPROVED',
        missing_at_meta: true,
      })
    ).toBe('missing');
  });

  it("uses WhatsApp's own status for everything else", () => {
    expect(templateState({ state: 'remote', meta_status: 'PENDING' })).toBe(
      'pending'
    );
    expect(templateState({ state: 'remote', meta_status: 'IN_APPEAL' })).toBe(
      'in_appeal'
    );
  });
});

describe('#templateStatusLabelKey', () => {
  it('names every state the manager can show', () => {
    [
      'unsubmitted',
      'submitting',
      'submission_failed',
      'missing',
      'approved',
      'pending',
      'rejected',
      'paused',
      'disabled',
      'in_appeal',
      'pending_deletion',
      'deleted',
      'archived',
      'limit_exceeded',
    ].forEach(status => {
      expect(templateStatusLabelKey(status)).toBe(
        `WHATSAPP_TEMPLATE_MGMT.STATUSES.${status.toUpperCase()}`
      );
    });
  });

  // A status WhatsApp adds later must not render a translation key at the user.
  it('returns nothing for a status it has no words for', () => {
    expect(templateStatusLabelKey('SOMETHING_NEW')).toBeNull();
  });
});

describe('#templateRowFromRecord', () => {
  const record = {
    id: 7,
    name: 'order_shipped',
    language: 'en_US',
    state: 'remote',
    meta_status: 'APPROVED',
    components: [{ type: 'BODY', text: 'On its way' }],
    inboxes: [{ id: 1, name: 'Support' }],
    last_seen_at: 1_700_000_000,
    allowed_actions: ['edit', 'delete', 'duplicate'],
  };

  it('resolves inboxes to the records the channel icon needs', () => {
    const inbox = whatsappInbox({
      id: 1,
      name: 'Support',
      businessAccountId: 'waba-1',
    });

    const row = templateRowFromRecord(record, { 1: inbox });

    expect(row.inboxes).toEqual([inbox]);
    expect(row.inboxNames).toBe('Support');
  });

  it('keeps an inbox the store has not loaded instead of dropping the row', () => {
    const row = templateRowFromRecord(record, {});

    expect(row.inboxes).toEqual([{ id: 1, name: 'Support' }]);
  });

  it('carries the state, the actions and the content the card and preview read', () => {
    const row = templateRowFromRecord(record, {});

    expect(row.status).toBe('approved');
    expect(row.platform).toBe('whatsapp');
    expect(row.isManaged).toBe(true);
    expect(row.allowed_actions).toEqual(['edit', 'delete', 'duplicate']);
    expect(row.searchableContent).toContain('On its way');
    expect(row.lastUpdatedAt).toBe(1_700_000_000_000);
  });
});
