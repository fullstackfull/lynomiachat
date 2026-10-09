import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AnalyticsBreakdownCard from '../AnalyticsBreakdownCard.vue';

withFullI18n();

const TabBarStub = {
  name: 'TabBar',
  props: ['tabs', 'initialActiveTab'],
  emits: ['tabChanged'],
  template: '<div class="tab-bar" />',
};

const mountCard = props =>
  mount(AnalyticsBreakdownCard, {
    props: {
      title: 'Where the volume sits',
      dimension: 'inbox',
      dimensions: ['inbox', 'channel', 'team', 'agent'],
      ...props,
    },
    global: { stubs: { TabBar: TabBarStub } },
  });

describe('AnalyticsBreakdownCard', () => {
  const rows = [
    { id: 1, label: 'WhatsApp', value: 60 },
    { id: 2, label: 'Website', value: 40 },
  ];

  it('shows each row with its count and its share of the total', () => {
    const wrapper = mountCard({ rows });

    expect(wrapper.text()).toContain('WhatsApp');
    expect(wrapper.text()).toContain('60');
    expect(wrapper.text()).toContain('60%');
    expect(wrapper.text()).toContain('40%');
  });

  it('does not divide by zero when every row is empty', () => {
    const wrapper = mountCard({
      rows: [{ id: 1, label: 'WhatsApp', value: 0 }],
    });

    expect(wrapper.text()).toContain('0%');
  });

  it('caps the visible rows and says how many were left out', () => {
    const many = Array.from({ length: 11 }, (_, index) => ({
      id: index,
      label: `Inbox ${index}`,
      value: 11 - index,
    }));
    const wrapper = mountCard({ rows: many });

    expect(wrapper.text()).toContain('Inbox 7');
    expect(wrapper.text()).not.toContain('Inbox 8');
    expect(wrapper.text()).toContain('and 3 more');
  });

  it('marks the active dimension in the switcher', () => {
    const wrapper = mountCard({ rows, dimension: 'team' });
    const tabBar = wrapper.findComponent(TabBarStub);

    expect(tabBar.props('initialActiveTab')).toBe(2);
    expect(tabBar.props('tabs').map(tab => tab.label)).toEqual([
      'Inbox',
      'Channel',
      'Team',
      'Agent',
    ]);
  });

  it('emits the chosen dimension', async () => {
    const wrapper = mountCard({ rows });

    await wrapper
      .findComponent(TabBarStub)
      .vm.$emit('tabChanged', { value: 'agent' });

    expect(wrapper.emitted('dimensionChange')).toEqual([['agent']]);
  });

  it('says nothing was recorded when there are no rows', () => {
    const wrapper = mountCard({ rows: [] });

    expect(wrapper.text()).toContain('Nothing was recorded in this period.');
  });
});
