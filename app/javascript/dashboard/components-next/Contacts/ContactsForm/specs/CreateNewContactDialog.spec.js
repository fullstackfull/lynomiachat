import { computed, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import contact from 'dashboard/i18n/locale/en/contact.json';
import contactAr from 'dashboard/i18n/locale/ar/contact.json';
import componentsEn from 'dashboard/i18n/locale/en/components.json';
import componentsAr from 'dashboard/i18n/locale/ar/components.json';
import { DuplicateContactException } from 'shared/helpers/CustomErrors';
import CreateNewContactDialog from '../CreateNewContactDialog.vue';

const dispatch = vi.fn();
const alerts = [];
const push = vi.fn();
const route = ref({ name: 'contacts_dashboard_index', params: {}, query: {} });

const filter = vi.fn();
const bulkCreate = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => computed(() => ({ isCreating: false })),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
}));
vi.mock('vue-router', () => ({
  useRoute: () => route.value,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/api/contacts', () => ({ default: { filter: (...a) => filter(...a) } }));
vi.mock('dashboard/api/bulkActions', () => ({
  default: { create: (...a) => bulkCreate(...a) },
}));

const close = vi.fn();
const resetForm = vi.fn();

const DialogStub = {
  setup(_, { expose }) {
    expose({ open: vi.fn(), close });
  },
  template: '<div><slot /><slot name="footer" /></div>',
};

const ContactsFormStub = {
  props: ['serverErrors', 'isNewContact'],
  emits: ['update'],
  setup(_, { expose }) {
    expose({ resetForm, isFormInvalid: false });
  },
  template: '<div data-test-id="form" />',
};

const ButtonStub = {
  props: ['label', 'isLoading', 'disabled'],
  template: '<button :data-label="label" @click="$emit(\'click\')" />',
};

const FORM_CONTACT = { name: 'Dana', phoneNumber: '+96522201234', email: '' };

const validationError = ({ message, errors, errorTypes }) => {
  const error = new DuplicateContactException(Object.keys(errors ?? {}));
  error.message = message;
  error.fieldErrors = errors ?? {};
  error.fieldErrorTypes = errorTypes ?? {};
  return error;
};

const TAKEN_PHONE = {
  message: 'Phone number has already been taken',
  errors: { phone_number: ['Phone number has already been taken'] },
  errorTypes: { phone_number: ['taken'] },
};

const buildWrapper = (locale = 'en') => {
  const i18n = createI18n({
    legacy: false,
    locale,
    messages: {
      en: { ...contact, ...componentsEn },
      ar: { ...contactAr, ...componentsAr },
    },
  });

  return mount(CreateNewContactDialog, {
    global: {
      plugins: [i18n],
      stubs: {
        Dialog: DialogStub,
        ContactsForm: ContactsFormStub,
        Button: ButtonStub,
      },
    },
  });
};

const submit = async wrapper => {
  wrapper.findComponent(ContactsFormStub).vm.$emit('update', FORM_CONTACT);
  await flushPromises();
  await wrapper.findComponent(DialogStub).vm.$emit('confirm');
  await flushPromises();
};

const buttonWith = (wrapper, text) =>
  wrapper
    .findAll('button')
    .find(button => (button.attributes('data-label') || '').includes(text));

describe('CreateNewContactDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    alerts.length = 0;
    route.value = { name: 'contacts_dashboard_index', params: {}, query: {} };
    filter.mockResolvedValue({ data: { payload: [] } });
    bulkCreate.mockResolvedValue({});
  });

  it('creates the contact without a label on the plain contacts list', async () => {
    dispatch.mockResolvedValue({ id: 7, ...FORM_CONTACT });
    const wrapper = buildWrapper();

    await submit(wrapper);

    expect(dispatch).toHaveBeenCalledWith('contacts/create', FORM_CONTACT);
    expect(close).toHaveBeenCalled();
    expect(resetForm).toHaveBeenCalled();
    expect(wrapper.emitted('created')[0][0]).toEqual({ id: 7, ...FORM_CONTACT });
  });

  // The workflow this phase exists for.
  it('sends the label the list is filtered by, so the contact really owns it', async () => {
    route.value = {
      name: 'contacts_dashboard_labels_index',
      params: { label: 'vip' },
      query: {},
    };
    dispatch.mockResolvedValue({ id: 8, ...FORM_CONTACT });
    const wrapper = buildWrapper();

    await submit(wrapper);

    expect(dispatch).toHaveBeenCalledWith('contacts/create', {
      ...FORM_CONTACT,
      labels: ['vip'],
    });
  });

  it('keeps the dialog open on a 422 and does not report success', async () => {
    dispatch.mockRejectedValue(validationError(TAKEN_PHONE));
    const wrapper = buildWrapper();

    await submit(wrapper);

    expect(close).not.toHaveBeenCalled();
    expect(resetForm).not.toHaveBeenCalled();
    expect(wrapper.emitted('created')).toBeUndefined();
  });

  it('puts the real reason on the field it belongs to', async () => {
    dispatch.mockRejectedValue(validationError(TAKEN_PHONE));
    const wrapper = buildWrapper();

    await submit(wrapper);

    expect(wrapper.findComponent(ContactsFormStub).props('serverErrors')).toEqual(
      {
        phone_number:
          'This phone number already belongs to another contact in this account.',
      }
    );
  });

  it('shows the e164 message for a format rejection, not the duplicate one', async () => {
    dispatch.mockRejectedValue(
      validationError({
        message: 'Phone number should be in e164 format',
        errors: { phone_number: ['Phone number should be in e164 format'] },
        errorTypes: { phone_number: ['invalid'] },
      })
    );
    const wrapper = buildWrapper();

    await submit(wrapper);

    expect(
      wrapper.findComponent(ContactsFormStub).props('serverErrors').phone_number
    ).toBe('Enter the number in international format, for example +96522201234.');
    // A malformed number belongs to nobody, so nothing is looked up.
    expect(filter).not.toHaveBeenCalled();
  });

  it('shows the Arabic message when the dashboard is in Arabic', async () => {
    dispatch.mockRejectedValue(validationError(TAKEN_PHONE));
    const wrapper = buildWrapper('ar');

    await submit(wrapper);

    expect(
      wrapper.findComponent(ContactsFormStub).props('serverErrors').phone_number
    ).toBe('رقم الهاتف هذا يعود إلى جهة اتصال أخرى في هذا الحساب.');
  });

  it('clears the field errors once the form is edited again', async () => {
    dispatch.mockRejectedValue(validationError(TAKEN_PHONE));
    const wrapper = buildWrapper();
    await submit(wrapper);

    wrapper
      .findComponent(ContactsFormStub)
      .vm.$emit('update', { ...FORM_CONTACT, phoneNumber: '+96522209999' });
    await flushPromises();

    expect(
      wrapper.findComponent(ContactsFormStub).props('serverErrors')
    ).toEqual({});
  });

  describe('duplicate recovery', () => {
    beforeEach(() => {
      route.value = {
        name: 'contacts_dashboard_labels_index',
        params: { label: 'vip' },
        query: {},
      };
      dispatch.mockRejectedValue(validationError(TAKEN_PHONE));
      filter.mockResolvedValue({
        data: { payload: [{ id: 42, name: 'Dana Al-Sabah' }] },
      });
    });

    it('looks the existing contact up by the field that collided', async () => {
      const wrapper = buildWrapper();
      await submit(wrapper);

      expect(filter).toHaveBeenCalledWith(1, undefined, {
        payload: [
          {
            attribute_key: 'phone_number',
            filter_operator: 'equal_to',
            values: ['+96522201234'],
            attribute_model: 'standard',
            custom_attribute_type: '',
          },
        ],
      });
      expect(wrapper.text()).toContain('A contact with these details already exists');
    });

    it('opens the existing contact in the list context it came from', async () => {
      const wrapper = buildWrapper();
      await submit(wrapper);

      await buttonWith(wrapper, 'Open').trigger('click');

      expect(close).toHaveBeenCalled();
      expect(push).toHaveBeenCalledWith({
        name: 'contacts_edit_label',
        params: { contactId: 42, label: 'vip' },
        query: {},
      });
    });

    it('adds the label to the existing contact additively, in one call', async () => {
      const wrapper = buildWrapper();
      await submit(wrapper);

      await buttonWith(wrapper, 'Add').trigger('click');
      await flushPromises();

      expect(bulkCreate).toHaveBeenCalledWith({
        type: 'Contact',
        ids: [42],
        labels: { add: ['vip'] },
      });
      expect(alerts).toContain('“vip” added to Dana Al-Sabah');
    });

    it('offers nothing when the lookup finds no contact', async () => {
      filter.mockResolvedValue({ data: { payload: [] } });
      const wrapper = buildWrapper();
      await submit(wrapper);

      expect(wrapper.text()).not.toContain('already exists');
    });

    it('offers nothing when two identity keys collided, because either could be meant', async () => {
      dispatch.mockRejectedValue(
        validationError({
          message: 'Email has already been taken, Phone number has already been taken',
          errors: {
            email: ['Email has already been taken'],
            phone_number: ['Phone number has already been taken'],
          },
          errorTypes: { email: ['taken'], phone_number: ['taken'] },
        })
      );
      const wrapper = buildWrapper();
      await submit(wrapper);

      expect(filter).not.toHaveBeenCalled();
      expect(wrapper.text()).not.toContain('already exists');
    });

    it('does not offer the label action away from a label page', async () => {
      route.value = { name: 'contacts_dashboard_index', params: {}, query: {} };
      const wrapper = buildWrapper();
      await submit(wrapper);

      expect(buttonWith(wrapper, 'Open')).toBeDefined();
      expect(buttonWith(wrapper, 'Add')).toBeUndefined();
    });

    it('survives a lookup that fails', async () => {
      filter.mockRejectedValue(new Error('network'));
      const wrapper = buildWrapper();
      await submit(wrapper);

      expect(wrapper.text()).not.toContain('already exists');
      expect(alerts).toContain(
        'This phone number already belongs to another contact in this account.'
      );
    });
  });
});
