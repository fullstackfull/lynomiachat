import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';

import NewTicketForm from '../components/NewTicketForm.vue';
import {
  PLATFORM_SUPPORT_ACCEPTED_MIME_TYPES,
  PLATFORM_SUPPORT_CATEGORIES,
  PLATFORM_SUPPORT_MAX_ATTACHMENTS,
  PLATFORM_SUPPORT_PRIORITIES,
} from '../constants';

withFullI18n();

vi.mock('../platformSupportApi', () => ({
  default: { uploadAttachment: vi.fn() },
}));

const mountForm = (props = {}) => mount(NewTicketForm, { props });

const setField = async (wrapper, selector, value) => {
  const field = wrapper.find(selector);
  await field.setValue(value);
};

describe('NewTicketForm', () => {
  it('offers the eleven categories and the four priorities, nothing more', () => {
    const wrapper = mountForm();
    const [category, priority] = wrapper.findAll('select');

    expect(category.findAll('option')).toHaveLength(
      PLATFORM_SUPPORT_CATEGORIES.length
    );
    expect(priority.findAll('option')).toHaveLength(
      PLATFORM_SUPPORT_PRIORITIES.length
    );
  });

  it('defaults to Other and Medium, and labels Urgent honestly', () => {
    const wrapper = mountForm();
    const [category, priority] = wrapper.findAll('select');

    expect(category.element.value).toBe('other');
    expect(priority.element.value).toBe('medium');
    expect(wrapper.text()).toContain('service is down for us');
  });

  it('pre-selects a category it was given, and ignores one outside the allow-list', () => {
    expect(
      mountForm({ initialCategory: 'billing' }).findAll('select')[0].element
        .value
    ).toBe('billing');

    expect(
      mountForm({ initialCategory: 'not_a_category' }).findAll('select')[0]
        .element.value
    ).toBe('other');
  });

  it('states the attachment limits and the accepted types BEFORE the picker', () => {
    const wrapper = mountForm();

    expect(wrapper.text()).toContain(
      `Up to ${PLATFORM_SUPPORT_MAX_ATTACHMENTS} files`
    );
    expect(wrapper.text()).toContain('10 MB each');
    expect(wrapper.text()).toContain('PNG, JPEG, GIF, WebP, PDF');
    // The same list is on the input, so the OS picker filters too.
    expect(wrapper.find('input[type="file"]').attributes('accept')).toBe(
      PLATFORM_SUPPORT_ACCEPTED_MIME_TYPES.join(',')
    );
  });

  it('refuses to submit without a subject or a description, and says which', async () => {
    const wrapper = mountForm();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(wrapper.text()).toContain('Add a subject');
    expect(wrapper.text()).toContain('Add a description');
  });

  it('submits exactly the five contract keys, trimmed', async () => {
    const wrapper = mountForm();
    const [category, priority] = wrapper.findAll('select');

    await category.setValue('whatsapp');
    await priority.setValue('urgent');
    await setField(wrapper, 'input[type="text"]', '  Numbers went offline  ');
    await setField(wrapper, 'textarea', '  It stopped at 09:00.  ');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.emitted('submit')[0][0]).toEqual({
      category: 'whatsapp',
      subject: 'Numbers went offline',
      description: 'It stopped at 09:00.',
      priority: 'urgent',
      attachment_ids: [],
    });
  });

  it('renders the server refusal as it came, rather than guessing at it', () => {
    const wrapper = mountForm({
      errorMessage: 'Subject is too long (maximum is 255 characters)',
    });

    expect(wrapper.text()).toContain('maximum is 255 characters');
  });

  it('disables both buttons and the fields while the request is in flight', () => {
    const wrapper = mountForm({ isSubmitting: true });

    wrapper.findAll('button').forEach(button => {
      expect(button.attributes('disabled')).toBeDefined();
    });
  });

  it('emits cancel rather than navigating itself', async () => {
    const wrapper = mountForm();
    await wrapper.findAll('button')[1].trigger('click');

    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });
});
