import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AnalyticsKpiGrid from '../AnalyticsKpiGrid.vue';

withFullI18n();

const mountGrid = (kpis, scope = 'CONVERSATIONS') =>
  mount(AnalyticsKpiGrid, { props: { kpis, scope } });

describe('AnalyticsKpiGrid', () => {
  it('renders a card per KPI with its translated label', () => {
    const wrapper = mountGrid([
      { key: 'conversations_created', value: 12, unit: 'count', kind: 'event' },
      {
        key: 'unresolved_backlog',
        value: 3,
        unit: 'count',
        kind: 'current_state',
      },
    ]);

    expect(wrapper.text()).toContain('Conversations started');
    expect(wrapper.text()).toContain('Open right now');
  });

  it('formats a seconds metric as a duration rather than a raw number', () => {
    const wrapper = mountGrid([
      {
        key: 'avg_first_response_time',
        value: 3661,
        unit: 'seconds',
        kind: 'event',
      },
    ]);

    expect(wrapper.text()).toContain('1 Hr 1 Min');
    expect(wrapper.text()).not.toContain('3,661');
  });

  it('shows a dash for a null duration, so "nothing was measured" never reads as "instant"', () => {
    const wrapper = mountGrid([
      {
        key: 'avg_resolution_time',
        value: null,
        unit: 'seconds',
        kind: 'event',
      },
    ]);

    expect(wrapper.text()).toContain('—');
    expect(wrapper.text()).not.toContain('0 Sec');
  });

  it('keeps a real zero as zero', () => {
    const wrapper = mountGrid([
      { key: 'conversations_resolved', value: 0, unit: 'count', kind: 'event' },
    ]);

    expect(wrapper.text()).toContain('0');
    expect(wrapper.text()).not.toContain('—');
  });

  it('labels a current-state KPI as a reading taken now instead of a period count', () => {
    const wrapper = mountGrid([
      {
        key: 'unresolved_backlog',
        value: 5,
        unit: 'count',
        kind: 'current_state',
      },
    ]);
    const hint = wrapper.find('button[aria-label]');

    expect(hint.attributes('aria-label')).toBe(
      'A reading taken now, not a count over the selected dates.'
    );
  });

  it('gives an event KPI its own explanation rather than the current-state note', () => {
    const wrapper = mountGrid([
      { key: 'inbound_messages', value: 5, unit: 'count', kind: 'event' },
    ]);
    const hint = wrapper.find('button[aria-label]');

    expect(hint.attributes('aria-label')).toContain('Customer messages');
  });

  it('separates thousands so a large count stays readable', () => {
    const wrapper = mountGrid([
      {
        key: 'inbound_messages',
        value: 1234567,
        unit: 'count',
        kind: 'event',
      },
    ]);

    expect(wrapper.text()).toContain('1,234,567');
  });
});

describe('AnalyticsKpiGrid, per-family scopes', () => {
  it('formats a percent metric with its unit', () => {
    const wrapper = mount(AnalyticsKpiGrid, {
      props: {
        scope: 'WHATSAPP',
        kpis: [
          {
            key: 'delivery_rate',
            value: 93.5,
            unit: 'percent',
            kind: 'event',
          },
        ],
      },
    });

    expect(wrapper.text()).toContain('93.5%');
    expect(wrapper.text()).toContain('Delivery rate');
  });

  it('reads the same metric key differently per family', () => {
    const kpis = [{ key: 'delivered', value: 7, unit: 'count', kind: 'event' }];
    const whatsapp = mount(AnalyticsKpiGrid, {
      props: { scope: 'WHATSAPP', kpis },
    });
    const campaigns = mount(AnalyticsKpiGrid, {
      props: { scope: 'CAMPAIGNS', kpis },
    });

    expect(
      whatsapp.find('button[aria-label]').attributes('aria-label')
    ).toContain('Messages Meta confirmed');
    expect(
      campaigns.find('button[aria-label]').attributes('aria-label')
    ).toContain('Recipients Meta confirmed');
  });
});
