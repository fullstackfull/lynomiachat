import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AnalyticsSeriesCard from '../AnalyticsSeriesCard.vue';

withFullI18n();

const BarChartStub = {
  name: 'BarChart',
  props: ['data', 'ariaLabel', 'formatValue', 'height'],
  template: '<div class="bar-chart" />',
};

const mountCard = props =>
  mount(AnalyticsSeriesCard, {
    props: { title: 'Conversations started', ...props },
    global: { stubs: { BarChart: BarChartStub } },
  });

describe('AnalyticsSeriesCard', () => {
  const points = [
    { bucket: '2026-03-01', value: 4 },
    { bucket: '2026-03-02', value: 0 },
    { bucket: '2026-03-03', value: 6 },
  ];

  it('totals the buckets', () => {
    const wrapper = mountCard({ points });

    expect(wrapper.text()).toContain('10 total');
  });

  it('draws a bar for every bucket including the empty one, so a gap is visible as zero', () => {
    const wrapper = mountCard({ points });
    const data = wrapper.findComponent(BarChartStub).props('data');

    expect(data.series[0].data).toEqual([4, 0, 6]);
    expect(data.categories).toHaveLength(3);
  });

  it('labels daily buckets by day and month', () => {
    const wrapper = mountCard({ points, groupBy: 'day' });

    expect(
      wrapper.findComponent(BarChartStub).props('data').categories
    ).toEqual(['01 Mar', '02 Mar', '03 Mar']);
  });

  it('labels monthly buckets by month and year', () => {
    const wrapper = mountCard({
      points: [
        { bucket: '2026-01-01', value: 1 },
        { bucket: '2026-02-01', value: 2 },
      ],
      groupBy: 'month',
    });

    expect(
      wrapper.findComponent(BarChartStub).props('data').categories
    ).toEqual(['Jan 2026', 'Feb 2026']);
  });

  it('says nothing was recorded rather than drawing an empty chart', () => {
    const wrapper = mountCard({ points: [] });

    expect(wrapper.text()).toContain('Nothing was recorded in this period.');
    expect(wrapper.findComponent(BarChartStub).exists()).toBe(false);
  });

  it('shows a placeholder while the first request is in flight', () => {
    const wrapper = mountCard({ points: [], loading: true });

    expect(wrapper.find('.animate-pulse').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Nothing was recorded');
  });

  it('passes the title through as the chart accessible label', () => {
    const wrapper = mountCard({ points });

    expect(wrapper.findComponent(BarChartStub).props('ariaLabel')).toBe(
      'Conversations started'
    );
  });
});
