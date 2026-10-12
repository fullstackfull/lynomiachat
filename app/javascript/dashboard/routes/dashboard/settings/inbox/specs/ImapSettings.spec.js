import { nextTick } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ImapSettings from '../ImapSettings.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

// The password is no longer part of this payload in either direction: the server does not send it, so the
// field starts empty, and a blank value on save means "keep what is stored"
// (docs/p10/07-security-performance.md). `imap_password_configured` is what the form is told instead.
describe('ImapSettings', () => {
  it('disables IMAP without changing the SMTP configuration, and sends no password it was not given', async () => {
    const updateInboxIMAP = vi.fn();
    const wrapper = shallowMount(ImapSettings, {
      props: {
        inbox: {
          id: 1,
          imap_enabled: true,
          smtp_enabled: true,
          imap_address: 'imap.example.com',
          imap_port: 993,
          imap_login: 'support@example.com',
          imap_password_configured: true,
          imap_enable_ssl: true,
          imap_authentication: 'plain',
        },
      },
      global: {
        plugins: [
          createStore({
            getters: {
              'inboxes/getUIFlags': () => ({ isUpdatingIMAP: false }),
            },
            actions: {
              'inboxes/updateInboxIMAP': updateInboxIMAP,
            },
          }),
        ],
        mocks: { $t: key => key },
        stubs: {
          SettingsFieldSection: {
            template: '<section><slot /></section>',
          },
          'woot-input': true,
        },
      },
    });

    await nextTick();
    await wrapper.find('input[name="toggle-imap-enable"]').setValue(false);
    await wrapper.find('form').trigger('submit');

    expect(updateInboxIMAP).toHaveBeenCalledOnce();
    expect(updateInboxIMAP.mock.calls[0][1]).toEqual({
      id: 1,
      formData: false,
      channel: {
        imap_enabled: false,
        imap_address: 'imap.example.com',
        imap_port: 993,
        imap_login: 'support@example.com',
        imap_password: '',
        imap_enable_ssl: true,
        imap_authentication: 'plain',
      },
    });
  });
});
