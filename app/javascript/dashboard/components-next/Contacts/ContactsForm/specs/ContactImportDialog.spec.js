import { computed } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import contact from 'dashboard/i18n/locale/en/contact.json';
import contactAr from 'dashboard/i18n/locale/ar/contact.json';
import componentsEn from 'dashboard/i18n/locale/en/components.json';
import componentsAr from 'dashboard/i18n/locale/ar/components.json';
import ContactImportDialog from '../ContactImportDialog.vue';

const previewImport = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter =>
    computed(() =>
      getter === 'labels/getLabels'
        ? [{ title: 'vip' }, { title: 'wholesale' }]
        : { isImporting: false }
    ),
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { previewImport: (...args) => previewImport(...args) },
}));

const close = vi.fn();

const DialogStub = {
  emits: ['close'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close });
  },
  template:
    '<div><slot name="description" /><slot /><slot name="footer" /></div>',
};

const ButtonStub = {
  props: ['label', 'isLoading', 'disabled', 'variant', 'color'],
  template:
    '<button :data-label="label" :disabled="disabled" @click="$emit(\'click\')" />',
};

const ComboBoxStub = {
  props: ['modelValue', 'options', 'placeholder'],
  emits: ['update:modelValue'],
  template: '<div data-test-id="combobox" />',
};

const PREVIEW = {
  total_rows: 4,
  previewed_rows: 4,
  row_limit: 500,
  duplicate_policy: 'update',
  default_country: 'SA',
  labels: ['vip'],
  counts: {
    new_contact: 1,
    update_existing: 1,
    skip_existing: 0,
    duplicate_in_file: 1,
    no_identity: 0,
    invalid: 1,
  },
  rows: [
    { number: 1, classification: 'new_contact', phone_number: '+966551112233' },
    {
      number: 3,
      classification: 'duplicate_in_file',
      reason: 'duplicate_in_file',
      detail: '1',
      phone_number: '+966551112233',
    },
    {
      number: 4,
      classification: 'invalid',
      reason: 'phone_country_required',
      phone_number: '0551112299',
    },
  ],
};

const mountDialog = (locale = 'en') =>
  mount(ContactImportDialog, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale,
          messages: {
            en: { ...contact, ...componentsEn },
            ar: { ...contactAr, ...componentsAr },
          },
        }),
      ],
      stubs: {
        Dialog: DialogStub,
        Button: ButtonStub,
        ComboBox: ComboBoxStub,
        TagMultiSelectComboBox: ComboBoxStub,
      },
    },
  });

const clickLabel = async (wrapper, label) => {
  const button = wrapper
    .findAll('button')
    .find(candidate => candidate.attributes('data-label') === label);
  await button.trigger('click');
  await flushPromises();
};

const paste = async (wrapper, text, messages = contact) => {
  await clickLabel(
    wrapper,
    messages.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.SOURCES.PASTE
  );
  await wrapper.find('textarea').setValue(text);
};

describe('ContactImportDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    previewImport.mockResolvedValue({ data: PREVIEW });
  });

  it('starts on the options step with nothing to import yet', () => {
    const wrapper = mountDialog();
    const continueButton = wrapper
      .findAll('button')
      .find(
        candidate =>
          candidate.attributes('data-label') ===
          contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
      );

    expect(continueButton.attributes('disabled')).toBeDefined();
    expect(previewImport).not.toHaveBeenCalled();
  });

  it('previews pasted numbers with the batch choices, and asks the server rather than parsing them', async () => {
    const wrapper = mountDialog();
    await paste(wrapper, '+966551112233\n0551112299');
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );

    expect(previewImport).toHaveBeenCalledWith({
      file: null,
      phoneNumbers: '+966551112233\n0551112299',
      labels: [],
      defaultCountry: '',
      duplicatePolicy: 'update',
    });
  });

  it('shows every count, including the ones that are zero', async () => {
    const wrapper = mountDialog();
    await paste(wrapper, '+966551112233');
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );

    const counts = wrapper.findAll('dd').map(cell => cell.text());
    expect(counts).toEqual(['1', '1', '0', '1', '0', '1']);
  });

  it('explains the rows that need a decision, and leaves the ordinary ones out', async () => {
    const wrapper = mountDialog();
    await paste(wrapper, '+966551112233');
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );

    const rows = wrapper.findAll('tbody tr');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Same contact as row 1');
    expect(rows[1].text()).toContain('a local number needs a country');
  });

  it('states which country local numbers will be read as, before the import runs', async () => {
    const wrapper = mountDialog();
    await paste(wrapper, '0551112299');
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );

    expect(wrapper.text()).toContain('Local numbers will be read as SA');
    expect(wrapper.text()).toContain('Checked all 4 rows');
  });

  it('says so when it only checked the first rows of a longer file', async () => {
    previewImport.mockResolvedValue({
      data: { ...PREVIEW, total_rows: 900, previewed_rows: 500 },
    });
    const wrapper = mountDialog();
    await paste(wrapper, '+966551112233');
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );

    expect(wrapper.text()).toContain('Checked the first 500 of 900 rows');
  });

  it('emits the payload the preview was built from, and only on the second step', async () => {
    const wrapper = mountDialog();
    await paste(wrapper, '+966551112233');
    expect(wrapper.emitted('import')).toBeUndefined();

    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.IMPORT
    );

    expect(wrapper.emitted('import')[0][0]).toMatchObject({
      phoneNumbers: '+966551112233',
      duplicatePolicy: 'update',
    });
  });

  it('goes back to the options without losing what was entered', async () => {
    const wrapper = mountDialog();
    await paste(wrapper, '+966551112233');
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.BACK
    );

    expect(wrapper.find('textarea').element.value).toBe('+966551112233');
  });

  it('refuses a file that is not a CSV without asking the server', async () => {
    const wrapper = mountDialog();
    const input = wrapper.find('input[type="file"]');
    Object.defineProperty(input.element, 'files', {
      value: [new File(['x'], 'contacts.txt', { type: 'text/plain' })],
    });
    await input.trigger('change');

    expect(wrapper.text()).toContain('Choose a .csv file');
    expect(previewImport).not.toHaveBeenCalled();
  });

  it("keeps the server's reason when the preview is refused", async () => {
    previewImport.mockRejectedValue({
      response: {
        data: { message: 'Labels do not exist in this account: ghost' },
      },
    });
    const wrapper = mountDialog();
    await paste(wrapper, '+966551112233');
    await clickLabel(
      wrapper,
      contact.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );

    expect(wrapper.text()).toContain(
      'Labels do not exist in this account: ghost'
    );
    expect(wrapper.findAll('dd')).toHaveLength(0);
  });

  it('renders the preview in Arabic', async () => {
    const wrapper = mountDialog('ar');
    await paste(wrapper, '0551112299', contactAr);
    await clickLabel(
      wrapper,
      contactAr.CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CONTINUE
    );

    expect(wrapper.text()).toContain('صفوف مكررة');
    expect(wrapper.text()).toContain('الرقم المحلي يحتاج إلى بلد');
  });
});
