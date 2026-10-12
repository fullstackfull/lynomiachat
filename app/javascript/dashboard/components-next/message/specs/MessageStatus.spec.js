import { mount } from '@vue/test-utils';
import MessageStatus from '../MessageStatus.vue';
import { MESSAGE_STATUS } from '../constants';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountStatus = status =>
  mount(MessageStatus, {
    props: { status },
    global: {
      stubs: { Icon: { props: ['icon'], template: '<i :data-icon="icon" />' } },
    },
  });

const iconOf = wrapper => wrapper.find('i').attributes('data-icon');

// The rule: an indicator is a CLAIM. A check says the provider confirmed something and a clock says the
// product is still trying, so neither may be shown for a message nothing reported about
// (docs/product-refinement/04-inbox-modernization.md).
describe('MessageStatus', () => {
  it('shows one check for sent and two for delivered', () => {
    expect(iconOf(mountStatus(MESSAGE_STATUS.SENT))).toBe('i-lucide-check');
    expect(iconOf(mountStatus(MESSAGE_STATUS.DELIVERED))).toBe(
      'i-lucide-check-check'
    );
  });

  it('distinguishes read from delivered by colour, which is the convention agents already read', () => {
    const read = mountStatus(MESSAGE_STATUS.READ);
    const delivered = mountStatus(MESSAGE_STATUS.DELIVERED);

    expect(iconOf(read)).toBe(iconOf(delivered));
    expect(read.find('i').classes().join(' ')).not.toBe(
      delivered.find('i').classes().join(' ')
    );
  });

  // The one that matters. An unknown delivery state is neither a confirmation nor an attempt in progress.
  it('shows neither a check nor a clock when nothing reported a delivery state', () => {
    const icon = iconOf(mountStatus(MESSAGE_STATUS.UNKNOWN));

    expect(icon).toBe('i-lucide-circle-help');
    expect(icon).not.toContain('check');
    expect(icon).not.toContain('clock');
  });

  it('names the unknown state rather than leaving it unlabelled', () => {
    const wrapper = mountStatus(MESSAGE_STATUS.UNKNOWN);

    expect(wrapper.html()).toContain('i-lucide-circle-help');
  });

  it('shows a clock only for a send the server says is in flight', () => {
    expect(iconOf(mountStatus(MESSAGE_STATUS.PROGRESS))).toContain('clock');
  });
});
