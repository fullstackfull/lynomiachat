import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AnalyticsMetaNote from '../AnalyticsMetaNote.vue';

withFullI18n();

const mountNote = meta => mount(AnalyticsMetaNote, { props: { meta } });

describe('AnalyticsMetaNote', () => {
  const meta = {
    since: '2026-03-01',
    until: '2026-03-31',
    group_by: 'day',
    timezone: 'Asia/Kuwait',
    source: 'raw',
    source_reason: 'feature_disabled',
    warnings: [],
  };

  it('states the resolved range, the grouping and the timezone the buckets were cut in', () => {
    const wrapper = mountNote(meta);

    expect(wrapper.text()).toContain(
      '2026-03-01 to 2026-03-31, grouped by Day, in Asia/Kuwait.'
    );
  });

  it('names which source answered and why', () => {
    const wrapper = mountNote(meta);

    expect(wrapper.text()).toContain('Computed from source records');
    expect(wrapper.text()).toContain('rollups are turned off for this account');
  });

  it('explains a rollup that was used', () => {
    const wrapper = mountNote({
      ...meta,
      source: 'rollup',
      source_reason: 'coverage_verified',
    });

    expect(wrapper.text()).toContain('Served from daily rollups');
    expect(wrapper.text()).toContain('matched the source records');
  });

  it('shows what was left out when the response is partial', () => {
    const wrapper = mountNote({
      ...meta,
      warnings: [{ scope: 'by_team', reason: 'no_teams_configured' }],
    });

    expect(wrapper.text()).toContain(
      'by_team could not be included: no_teams_configured.'
    );
  });

  it('renders no warning list when nothing was left out', () => {
    const wrapper = mountNote(meta);

    expect(wrapper.find('ul').exists()).toBe(false);
  });

  it('renders without a source rather than guessing one', () => {
    const wrapper = mountNote({
      ...meta,
      source: undefined,
      source_reason: undefined,
    });

    expect(wrapper.text()).not.toContain('Computed from source records');
    expect(wrapper.text()).toContain('2026-03-01 to 2026-03-31');
  });
});
