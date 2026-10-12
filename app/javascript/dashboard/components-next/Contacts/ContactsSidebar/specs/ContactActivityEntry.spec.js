import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ContactActivityEntry from '../ContactActivityEntry.vue';

withFullI18n();

const mountEntry = entry => mount(ContactActivityEntry, { props: { entry } });

const baseEntry = {
  id: 'messages:1',
  source: 'messages',
  category: 'messages',
  kind: 'message_incoming',
  occurred_at: '2026-10-02T10:00:00.000000Z',
  conversation_id: 7,
  summary: 'I need help',
  meta: {},
};

describe('ContactActivityEntry', () => {
  it("names the kind in the operator's language", () => {
    const wrapper = mountEntry(baseEntry);

    expect(wrapper.text()).toContain('Message received');
    expect(wrapper.text()).toContain('I need help');
  });

  it('renders a kind the client does not know yet rather than an empty row', () => {
    const wrapper = mountEntry({ ...baseEntry, kind: 'some_future_kind' });

    expect(wrapper.text()).toContain('some_future_kind');
  });

  it('carries a machine-readable timestamp for the row', () => {
    const wrapper = mountEntry(baseEntry);

    expect(wrapper.find('time').attributes('datetime')).toBe(
      '2026-10-02T10:00:00.000000Z'
    );
  });

  it('shows the chips the server sent and nothing it did not', () => {
    const wrapper = mountEntry({
      ...baseEntry,
      kind: 'automation_skipped',
      summary: null,
      meta: { rule_name: 'Chase the customer', skip_reason: 'episode_ended' },
    });

    expect(wrapper.text()).toContain('Chase the customer');
    expect(wrapper.text()).toContain('episode_ended');
  });

  it('renders a CSAT rating as its own chip', () => {
    const wrapper = mountEntry({
      ...baseEntry,
      kind: 'csat_response',
      meta: { rating: 4 },
    });

    expect(wrapper.text()).toContain('Rated 4/5');
  });

  it('renders a duration when the entry measured one', () => {
    const wrapper = mountEntry({
      ...baseEntry,
      kind: 'first_response',
      summary: null,
      meta: { duration_seconds: 120 },
    });

    expect(wrapper.text()).toContain('120s');
  });

  it('renders no chip row when the entry carries no chip values', () => {
    const wrapper = mountEntry(baseEntry);

    expect(wrapper.findAll('.rounded-md')).toHaveLength(0);
  });

  it('marks a private note with its own label', () => {
    const wrapper = mountEntry({
      ...baseEntry,
      kind: 'private_note',
      summary: 'internal',
    });

    expect(wrapper.text()).toContain('Private note');
  });
});
