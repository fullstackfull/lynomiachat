import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TicketSlaLabel from '../TicketSlaLabel.vue';

withFullI18n();

const NOW = Math.floor(Date.now() / 1000);

const mountLabel = (sla, status = 'open') =>
  mount(TicketSlaLabel, {
    props: {
      ticket: {
        status,
        sla: {
          applied: true,
          paused: false,
          breached: false,
          resolution_due_at: NOW + 7200,
          ...sla,
        },
      },
    },
  });

describe('TicketSlaLabel', () => {
  it('counts down to the resolution time while there is time left', () => {
    expect(mountLabel().text()).toContain('Due in about 2 hours');
  });

  it('calls out a target the server recorded as missed', () => {
    const wrapper = mountLabel({ breached: true });

    expect(wrapper.text()).toBe('Target missed');
  });

  it('calls an active case past its resolution time overdue', () => {
    const wrapper = mountLabel({ resolution_due_at: NOW - 60 });

    expect(wrapper.text()).toBe('Overdue');
  });

  it('says the clock is paused while waiting on the customer', () => {
    const wrapper = mountLabel(
      { paused: true, resolution_due_at: NOW - 60 },
      'waiting_on_customer'
    );

    expect(wrapper.text()).toBe('Clock paused');
  });

  it('reads a terminal case with no breach as closed on time', () => {
    const wrapper = mountLabel({ resolution_due_at: NOW - 60 }, 'resolved');

    expect(wrapper.text()).toBe('Closed on time');
  });

  it('says a case with no policy has none', () => {
    const wrapper = mountLabel({ applied: false });

    expect(wrapper.text()).toBe('No SLA policy');
  });

  it('puts the exact due time in the title, so the badge can stay short', () => {
    const wrapper = mountLabel();

    expect(wrapper.find('span').attributes('title')).toContain(
      'Resolution due in about 2 hours'
    );
  });

  it('carries no title when there is no due time to name', () => {
    const wrapper = mountLabel({ applied: false, resolution_due_at: null });

    expect(wrapper.find('span').attributes('title')).toBeUndefined();
  });
});
