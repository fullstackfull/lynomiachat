import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/contactFilters.json';
import ar from 'dashboard/i18n/locale/ar/contactFilters.json';
import AudienceExplainer from '../AudienceExplainer.vue';

const mountExplainer = (props = {}, locale = 'en') =>
  mount(AudienceExplainer, {
    props,
    global: {
      plugins: [createI18n({ legacy: false, locale, messages: { en, ar } })],
      stubs: { Icon: true },
    },
  });

describe('AudienceExplainer', () => {
  it('says what a shared audience is, not only that there is none', () => {
    const text = mountExplainer().text();

    expect(text).toContain('What a shared audience is');
    expect(text).toContain('A live customer group');
  });

  it('shows concrete examples a merchant would recognise', () => {
    const text = mountExplainer().text();

    expect(text).toContain('Recent buyers');
    expect(text).toContain('Customers with an active order');
    expect(text).toContain('High-value customers');
  });

  it('states the label-versus-audience rule, which is the distinction people get wrong', () => {
    const text = mountExplainer().text();

    expect(text).toContain('A label is a sticker');
    expect(text).toContain('a saved question about your customers');
    expect(text).toContain(
      'If you can point at the customers, use a label. If you can describe them, use an audience.'
    );
  });

  it('can leave the label rule out where the surface has already said it', () => {
    const text = mountExplainer({ showLabelRule: false }).text();

    expect(text).toContain('What a shared audience is');
    expect(text).not.toContain('A label is a sticker');
  });

  it('renders an action the surface supplies, because the useful button differs by surface', () => {
    const wrapper = mount(AudienceExplainer, {
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
        stubs: { Icon: true },
      },
      slots: { action: '<button data-test-id="create">Create</button>' },
    });

    expect(wrapper.find('[data-test-id="create"]').exists()).toBe(true);
  });

  it('is fully translated in Arabic, with no English left behind', () => {
    const text = mountExplainer({}, 'ar').text();

    expect(text).toContain('ما هو الجمهور المشترك');
    expect(text).toContain('المشترون حديثًا');
    expect(text).toContain('وسم أم جمهور مشترك؟');
    expect(text).not.toMatch(/What a shared audience|Recent buyers/);
  });
});
