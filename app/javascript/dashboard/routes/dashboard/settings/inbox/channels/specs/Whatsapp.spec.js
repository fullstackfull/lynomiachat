import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Whatsapp from '../Whatsapp.vue';

const mocks = vi.hoisted(() => ({
  route: { name: 'settings_inboxes_page_channel', params: {}, query: {} },
  push: vi.fn(),
  WhatsappEmbeddedSignup: {
    name: 'WhatsappEmbeddedSignup',
    props: [
      'variant',
      'isDisabled',
      'showRestrictionAlert',
      'restrictionStatusUrl',
    ],
    template: '<div data-testid="embedded-signup">{{ variant }}</div>',
  },
}));

vi.mock('../Twilio.vue', () => ({ default: { template: '<div />' } }));
vi.mock('../360DialogWhatsapp.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../CloudWhatsapp.vue', () => ({
  default: { template: '<div data-testid="cloud-whatsapp" />' },
}));
vi.mock('../WhatsappManualSetup.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../WhatsappEmbeddedSignup.vue', () => ({
  default: mocks.WhatsappEmbeddedSignup,
}));
vi.mock('../../components/WhatsappAccessRequestDialog.vue', () => ({
  default: { template: '<div />' },
}));

vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: mocks.push }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  I18nT: { name: 'I18nT', template: '<p data-testid="manual-fallback" />' },
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => false,
    isOnChatwootCloud: ref(false),
    isMetaInboxCreationDisabled: ref(false),
  }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    replaceInstallationName: text => `${text}|branded`,
  }),
}));

const ChannelSelector = {
  name: 'ChannelSelector',
  props: ['title', 'description', 'icon'],
  emits: ['click'],
  template:
    '<button data-testid="provider" @click="$emit(\'click\')">{{ title }}</button>',
};

const { WhatsappEmbeddedSignup } = mocks;

const mountComponent = () =>
  mount(Whatsapp, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        ChannelSelector,
        Banner: true,
        Button: true,
        Icon: true,
      },
    },
  });

describe('Whatsapp channel picker', () => {
  beforeEach(() => {
    mocks.route.query = {};
    mocks.push.mockReset();
    window.chatwootConfig = { whatsappAppId: 'meta-app-id' };
  });

  it('keeps the existing providers first and adds WhatsApp Business when Embedded Signup is configured', () => {
    const wrapper = mountComponent();
    const titles = wrapper
      .findAll('[data-testid="provider"]')
      .map(node => node.text());

    expect(titles).toEqual([
      'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD',
      'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO',
      'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_BUSINESS_APP',
    ]);
    const businessCard = wrapper.findAllComponents(ChannelSelector)[2];
    expect(businessCard.props('description')).toBe(
      'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_BUSINESS_APP_DESC|branded'
    );
  });

  it('shows only the existing providers when Embedded Signup is not configured', () => {
    window.chatwootConfig = { whatsappAppId: 'none' };
    const wrapper = mountComponent();

    expect(
      wrapper.findAll('[data-testid="provider"]').map(node => node.text())
    ).toEqual([
      'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WHATSAPP_CLOUD',
      'INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.TWILIO',
    ]);
  });

  it('opens the WhatsApp Business flow when its card is chosen', async () => {
    const wrapper = mountComponent();
    await wrapper.findAll('[data-testid="provider"]')[2].trigger('click');

    expect(mocks.push).toHaveBeenCalledWith({
      name: mocks.route.name,
      params: mocks.route.params,
      query: { provider: 'whatsapp_business_app' },
    });
  });

  it('renders the Business App variant of Embedded Signup without the manual fallback', () => {
    mocks.route.query = { provider: 'whatsapp_business_app' };
    const wrapper = mountComponent();

    const signup = wrapper.findComponent(WhatsappEmbeddedSignup);
    expect(signup.props('variant')).toBe('business_app');
    expect(wrapper.find('[data-testid="manual-fallback"]').exists()).toBe(
      false
    );
  });

  it('keeps the existing WhatsApp Cloud flow unchanged', () => {
    mocks.route.query = { provider: 'whatsapp' };
    const wrapper = mountComponent();

    const signup = wrapper.findComponent(WhatsappEmbeddedSignup);
    expect(signup.props('variant')).toBeUndefined();
    expect(wrapper.find('[data-testid="manual-fallback"]').exists()).toBe(true);
  });

  it('falls back to the manual Cloud API form when Business App is requested without Embedded Signup', () => {
    window.chatwootConfig = { whatsappAppId: 'none' };
    mocks.route.query = { provider: 'whatsapp_business_app' };
    const wrapper = mountComponent();

    expect(wrapper.findComponent(WhatsappEmbeddedSignup).exists()).toBe(false);
    expect(wrapper.find('[data-testid="cloud-whatsapp"]').exists()).toBe(true);
  });
});
