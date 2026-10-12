import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import SlaPolicyDialog from '../SlaPolicyDialog.vue';

withFullI18n();

vi.mock('dashboard/api/supportTickets', () => ({
  default: {
    createSlaPolicy: vi.fn(),
    updateSlaPolicy: vi.fn(),
  },
}));

const alert = vi.hoisted(() => vi.fn());

vi.mock('dashboard/composables', () => ({ useAlert: alert }));

// jsdom has no `showModal`, so the real dialog cannot be opened here. The stub keeps what this spec is about:
// the form inside it, and the confirm that submits it.
const close = vi.fn();

const DialogStub = {
  props: ['title', 'description', 'isLoading', 'disableConfirmButton'],
  emits: ['confirm', 'close'],
  setup(_props, { expose }) {
    expose({ open: vi.fn(), close });
  },
  template: '<div><span>{{ title }}</span><slot /></div>',
};

const POLICY = {
  id: 4,
  name: 'Standard support',
  description: 'Everything not on a premium plan',
  // Two hours and one day, in seconds.
  first_response_time_threshold: 7200,
  resolution_time_threshold: 86400,
  only_during_business_hours: true,
};

const mountDialog = (policy = null) =>
  mount(SlaPolicyDialog, {
    props: { policy },
    global: { stubs: { Dialog: DialogStub } },
  });

// Name, then description; the two duration controls follow, each an input plus its unit select.
const inputs = wrapper => wrapper.findAll('input[type="text"]');
const durations = wrapper => wrapper.findAll('input[type="number"]');
const units = wrapper => wrapper.findAll('select');

const submit = async wrapper => {
  wrapper.findComponent(DialogStub).vm.$emit('confirm');
  await flushPromises();
};

describe('SlaPolicyDialog', () => {
  beforeEach(() => {
    SupportTicketsAPI.createSlaPolicy.mockReset();
    SupportTicketsAPI.updateSlaPolicy.mockReset();
    SupportTicketsAPI.createSlaPolicy.mockResolvedValue({
      data: { payload: { id: 9 } },
    });
    SupportTicketsAPI.updateSlaPolicy.mockResolvedValue({
      data: { payload: POLICY },
    });
    alert.mockClear();
    close.mockClear();
  });

  it('opens a new policy on defaults a human would recognise', () => {
    const wrapper = mountDialog();

    expect(wrapper.text()).toContain('New SLA policy');
    expect(durations(wrapper)[0].element.value).toBe('1');
    expect(units(wrapper)[0].element.value).toBe('hours');
    expect(durations(wrapper)[1].element.value).toBe('24');
    expect(units(wrapper)[1].element.value).toBe('hours');
  });

  it('opens an existing policy in the largest unit its seconds divide into', () => {
    const wrapper = mountDialog(POLICY);

    expect(wrapper.text()).toContain('Edit SLA policy');
    expect(inputs(wrapper)[0].element.value).toBe('Standard support');
    expect(durations(wrapper)[0].element.value).toBe('2');
    expect(units(wrapper)[0].element.value).toBe('hours');
    expect(durations(wrapper)[1].element.value).toBe('1');
    expect(units(wrapper)[1].element.value).toBe('days');
  });

  it('falls back to minutes for a threshold that is not a whole hour', () => {
    const wrapper = mountDialog({
      ...POLICY,
      first_response_time_threshold: 2700,
    });

    expect(durations(wrapper)[0].element.value).toBe('45');
    expect(units(wrapper)[0].element.value).toBe('minutes');
  });

  it('refuses to save a policy with no name', () => {
    const wrapper = mountDialog();

    expect(
      wrapper.findComponent(DialogStub).props('disableConfirmButton')
    ).toBe(true);
  });

  it('converts the entered durations to seconds on create', async () => {
    const wrapper = mountDialog();

    await inputs(wrapper)[0].setValue('Premium');
    await units(wrapper)[0].setValue('minutes');
    await durations(wrapper)[0].setValue(30);
    await submit(wrapper);

    expect(SupportTicketsAPI.createSlaPolicy).toHaveBeenCalledWith({
      name: 'Premium',
      description: '',
      first_response_time_threshold: 1800,
      resolution_time_threshold: 86400,
      only_during_business_hours: false,
    });
  });

  it('sends a zero threshold as no threshold, never as an instant one', async () => {
    const wrapper = mountDialog();

    await inputs(wrapper)[0].setValue('Resolution only');
    await durations(wrapper)[0].setValue('');
    await submit(wrapper);

    expect(
      SupportTicketsAPI.createSlaPolicy.mock.calls[0][0]
        .first_response_time_threshold
    ).toBeNull();
  });

  it('carries the business-hours switch through', async () => {
    const wrapper = mountDialog();

    await inputs(wrapper)[0].setValue('Office hours');
    await wrapper.find('button[role="switch"]').trigger('click');
    await submit(wrapper);

    expect(
      SupportTicketsAPI.createSlaPolicy.mock.calls[0][0]
        .only_during_business_hours
    ).toBe(true);
  });

  it('updates the existing policy rather than creating a second one', async () => {
    const wrapper = mountDialog(POLICY);

    await inputs(wrapper)[0].setValue('Standard support v2');
    await submit(wrapper);

    expect(SupportTicketsAPI.createSlaPolicy).not.toHaveBeenCalled();
    expect(SupportTicketsAPI.updateSlaPolicy).toHaveBeenCalledWith(4, {
      name: 'Standard support v2',
      description: 'Everything not on a premium plan',
      first_response_time_threshold: 7200,
      resolution_time_threshold: 86400,
      only_during_business_hours: true,
    });
  });

  it('tells the parent to reload once a policy is saved, and closes', async () => {
    const wrapper = mountDialog();

    await inputs(wrapper)[0].setValue('Premium');
    await submit(wrapper);

    expect(wrapper.emitted('saved')).toEqual([[{ id: 9 }]]);
    expect(alert).toHaveBeenCalledWith('SLA policy created.');
    expect(close).toHaveBeenCalled();
  });

  it('shows the message a refused request came with, not one of its own', async () => {
    SupportTicketsAPI.createSlaPolicy.mockRejectedValue({
      response: { data: { message: 'Name has already been taken' } },
    });
    const wrapper = mountDialog();

    await inputs(wrapper)[0].setValue('Premium');
    await submit(wrapper);

    expect(alert).toHaveBeenCalledWith('Name has already been taken');
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(close).not.toHaveBeenCalled();
  });
});
