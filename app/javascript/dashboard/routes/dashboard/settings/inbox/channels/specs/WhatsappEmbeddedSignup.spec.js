import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import WhatsappEmbeddedSignup from '../WhatsappEmbeddedSignup.vue';

const mocks = vi.hoisted(() => ({
  runEmbeddedSignup: vi.fn(),
  dispatch: vi.fn(),
  replace: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('vuex', () => ({ useStore: () => ({ dispatch: mocks.dispatch }) }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  I18nT: { template: '<span />' },
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.useAlert }));
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({
    isAuthenticating: ref(false),
    runEmbeddedSignup: mocks.runEmbeddedSignup,
  }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => `${text}|branded` }),
}));

const NextButton = {
  name: 'NextButton',
  emits: ['click'],
  template:
    '<button data-testid="submit" @click="$emit(\'click\')"><slot /></button>',
};

const mountComponent = (props = {}) =>
  mount(WhatsappEmbeddedSignup, {
    props,
    global: {
      mocks: { $t: key => key },
      stubs: { NextButton, Icon: true, Banner: true, LoadingState: true },
    },
  });

const COEXISTENCE_CREDENTIALS = {
  code: 'auth-code',
  business_id: '',
  waba_id: 'waba-1',
  phone_number_id: '',
  is_coexistence: true,
};

describe('WhatsappEmbeddedSignup', () => {
  beforeEach(() => {
    Object.values(mocks).forEach(mock => mock.mockReset());
  });

  it('keeps the default Embedded Signup copy unchanged', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).toContain(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.TITLE'
    );
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BENEFITS.EASY_SETUP'
    );
    expect(wrapper.find('[data-testid="submit"]').text()).toBe(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SUBMIT_BUTTON'
    );
    expect(wrapper.text()).not.toContain('BUSINESS_APP');
  });

  it('shows the WhatsApp Business App copy for the business_app variant', () => {
    const wrapper = mountComponent({ variant: 'business_app' });
    const text = wrapper.text();

    expect(text).toContain(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.TITLE'
    );
    expect(text).toContain(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.DESC|branded'
    );
    expect(text).toContain(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.BENEFITS.KEEP_APP|branded'
    );
    expect(text).toContain(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.NOTE'
    );
    expect(wrapper.find('[data-testid="submit"]').text()).toBe(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BUSINESS_APP.SUBMIT'
    );
  });

  it('sends the Coexistence completion to the same inbox creation action', async () => {
    mocks.runEmbeddedSignup.mockResolvedValue(COEXISTENCE_CREDENTIALS);
    mocks.dispatch.mockResolvedValue({ id: 42 });
    const wrapper = mountComponent({ variant: 'business_app' });

    await wrapper.find('[data-testid="submit"]').trigger('click');
    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith(
      'inboxes/createWhatsAppEmbeddedSignup',
      COEXISTENCE_CREDENTIALS
    );
    expect(mocks.replace).toHaveBeenCalledWith({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: 42 },
    });
  });

  it('does nothing but inform the user when the Meta popup is cancelled', async () => {
    mocks.runEmbeddedSignup.mockResolvedValue(null);
    const wrapper = mountComponent({ variant: 'business_app' });

    await wrapper.find('[data-testid="submit"]').trigger('click');
    await flushPromises();

    expect(mocks.dispatch).not.toHaveBeenCalled();
    expect(mocks.useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'
    );
  });

  it('shows the server error when the inbox cannot be created', async () => {
    mocks.runEmbeddedSignup.mockResolvedValue(COEXISTENCE_CREDENTIALS);
    mocks.dispatch.mockRejectedValue({
      response: { data: { error: 'Token exchange failed' } },
    });
    const wrapper = mountComponent({ variant: 'business_app' });

    await wrapper.find('[data-testid="submit"]').trigger('click');
    await flushPromises();

    expect(mocks.replace).not.toHaveBeenCalled();
    expect(mocks.useAlert).toHaveBeenCalled();
  });
});
