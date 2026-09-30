import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConfigurationPage from '../ConfigurationPage.vue';
import SmtpSettings from '../../SmtpSettings.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({
    runEmbeddedSignup: vi.fn(),
  }),
}));

const mountComponent = inbox =>
  shallowMount(ConfigurationPage, {
    props: { inbox },
    global: {
      plugins: [
        createStore({
          getters: {
            'globalConfig/isOnChatwootCloud': () => true,
          },
        }),
      ],
      mocks: {
        $t: key => key,
      },
      stubs: {
        SettingsFieldSection: {
          template: '<section><slot /></section>',
        },
        NextButton: {
          template: '<button><slot /></button>',
        },
        'woot-code': true,
        'woot-input': true,
        WhatsappBusinessManagementToken: true,
      },
    },
  });

describe('ConfigurationPage', () => {
  it.each([false, true])(
    'shows SMTP settings for email inboxes when IMAP is %s',
    imapEnabled => {
      const inbox = {
        channel_type: 'Channel::Email',
        imap_enabled: imapEnabled,
      };
      const wrapper = mountComponent(inbox);

      expect(wrapper.findComponent(SmtpSettings).exists()).toBe(true);
      expect(wrapper.findComponent(SmtpSettings).props('inbox')).toEqual(inbox);
    }
  );

  it('shows the WhatsApp reconfigure option for embedded signup inboxes without checking account feature flags', () => {
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'embedded_signup',
        webhook_verify_token: 'verify-token',
      },
    });

    expect(wrapper.vm.showWhatsAppReconfigure).toBe(true);
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON'
    );
  });

  it('does not show the WhatsApp reconfigure option for manual WhatsApp inboxes', () => {
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'manual_setup_v2',
        webhook_verify_token: 'verify-token',
      },
    });

    expect(wrapper.vm.showWhatsAppReconfigure).toBe(false);
  });

  // Lynomia: the API no longer sends WhatsApp credentials to the browser.
  it('does not display the WhatsApp access token for manual inboxes', () => {
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'manual_setup_v2',
        webhook_verify_token: 'verify-token',
        api_key: 'stale-access-token',
      },
    });

    const scripts = wrapper
      .findAll('woot-code-stub')
      .map(code => code.attributes('script'));
    expect(scripts).toEqual(['verify-token']);
    expect(wrapper.html()).not.toContain('stale-access-token');
  });

  it('still lets admins replace the WhatsApp access token', async () => {
    const inbox = {
      id: 7,
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'manual_setup_v2',
        webhook_verify_token: 'verify-token',
        phone_number_id: '123',
      },
    };
    const wrapper = mountComponent(inbox);
    const dispatch = vi
      .spyOn(wrapper.vm.$store, 'dispatch')
      .mockResolvedValue();

    wrapper.vm.whatsAppInboxAPIKey = 'new-access-token';
    await wrapper.vm.updateWhatsAppInboxAPIKey();

    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 7,
      formData: false,
      channel: {
        provider_config: {
          ...inbox.provider_config,
          api_key: 'new-access-token',
        },
      },
    });
  });
});
