// @vitest-environment node

import { describe, it, expect } from 'vitest';

import { TemplateNormalizer } from './TemplateNormalizer';

describe('TemplateNormalizer', () => {
  it('normalizes Twilio call-to-action templates with hyphenated keys', () => {
    const template = {
      types: {
        'twilio/call-to-action': {
          body: 'CTA body for {{date}}',
          actions: [
            {
              id: null,
              title: 'Pay now',
              type: 'URL',
              url: 'https://payments.example.com/pay',
            },
          ],
        },
      },
      variables: {
        date: '01-Jan-2026',
      },
      content_sid: 'HX123',
      friendly_name: 'cta_example',
      template_type: 'call-to-action',
    };

    const normalized = TemplateNormalizer.normalizeTwilio(template);

    expect(normalized.type).toBe('twilio-call-to-action');
    expect(normalized.body).toBe('CTA body for {{date}}');
    expect(normalized.actions).toHaveLength(1);
    expect(normalized.variables).toEqual({ date: '01-Jan-2026' });
  });

  it('normalizes Twilio quick replies', () => {
    const template = {
      template_type: 'quick_reply',
      types: {
        'twilio/quick-reply': {
          body: 'Pick an option',
          actions: [{ id: 'a', title: 'Option A' }],
        },
      },
      variables: {},
    };

    const normalized = TemplateNormalizer.normalizeTwilio(template);

    expect(normalized.type).toBe('twilio-quick-reply');
    expect(normalized.body).toBe('Pick an option');
    expect(normalized.actions).toEqual([{ id: 'a', title: 'Option A' }]);
  });

  it('normalizes Twilio media templates', () => {
    const template = {
      template_type: 'media',
      body: 'Media body {{1}}',
      types: {
        'twilio/media': {
          body: 'Media body {{1}}',
          media: ['https://example.com/image.jpg'],
        },
      },
      variables: { 1: 'value' },
    };

    const normalized = TemplateNormalizer.normalizeTwilio(template);

    expect(normalized.type).toBe('twilio-media');
    expect(normalized.media).toEqual(['https://example.com/image.jpg']);
    expect(normalized.body).toBe('Media body {{1}}');
  });

  it('extracts WhatsApp named variables', () => {
    const template = {
      parameter_format: 'NAMED',
      components: [
        {
          type: 'BODY',
          text: 'Hi {{name}}',
          example: {
            body_text_named_params: [{ param_name: 'name', example: 'John' }],
          },
        },
      ],
    };

    const variables = TemplateNormalizer.extractWhatsAppVariables(template);

    expect(variables).toMatchObject({
      name: 'John',
    });
  });

  it('extracts WhatsApp positional variables', () => {
    const template = {
      parameter_format: 'POSITIONAL',
      components: [
        {
          type: 'BODY',
          text: 'Hi {{1}}',
          example: {
            body_text: [['positional']],
          },
        },
      ],
    };

    const variables = TemplateNormalizer.extractWhatsAppVariables(template);

    expect(variables).toMatchObject({
      1: 'positional',
    });
  });

  // P0/D5. Meta shapes a TEXT header's examples under its own keys, and flat rather than nested. Reading the
  // body keys for every component silently lost every header variable's example.
  it('extracts a TEXT header positional variable from header_text', () => {
    const template = {
      parameter_format: 'POSITIONAL',
      components: [
        {
          type: 'HEADER',
          format: 'TEXT',
          text: 'Order {{1}}',
          example: { header_text: ['A-1001'] },
        },
        {
          type: 'BODY',
          text: 'Hi {{1}}',
          example: { body_text: [['Zuhayr']] },
        },
      ],
    };

    const variables = TemplateNormalizer.extractWhatsAppVariables(template);

    // The body is read last and both use position 1, so the body example wins the key — the point here is that
    // the header lookup resolves at all rather than yielding ''.
    expect(variables[1]).toBe('Zuhayr');

    const headerOnly = TemplateNormalizer.extractWhatsAppVariables({
      parameter_format: 'POSITIONAL',
      components: [template.components[0]],
    });
    expect(headerOnly).toMatchObject({ 1: 'A-1001' });
  });

  it('extracts a TEXT header named variable from header_text_named_params', () => {
    const variables = TemplateNormalizer.extractWhatsAppVariables({
      parameter_format: 'NAMED',
      components: [
        {
          type: 'HEADER',
          format: 'TEXT',
          text: 'Order {{order_id}}',
          example: {
            header_text_named_params: [
              { param_name: 'order_id', example: 'A-1001' },
            ],
          },
        },
      ],
    });

    expect(variables).toMatchObject({ order_id: 'A-1001' });
  });

  it('still reads the body example from the nested body_text shape', () => {
    const variables = TemplateNormalizer.extractWhatsAppVariables({
      parameter_format: 'POSITIONAL',
      components: [
        { type: 'BODY', text: 'Hi {{1}}', example: { body_text: [['John']] } },
      ],
    });

    expect(variables).toMatchObject({ 1: 'John' });
  });

  it('normalizes WhatsApp media image templates', () => {
    const template = {
      id: '1',
      name: 'order_confirmation',
      parameter_format: 'POSITIONAL',
      components: [
        {
          type: 'HEADER',
          format: 'IMAGE',
          example: { header_handle: ['https://example.com/image.jpg'] },
        },
        { type: 'BODY', text: 'Hi {{1}}', example: { body_text: [['John']] } },
      ],
      language: 'en',
    };

    const normalized = TemplateNormalizer.normalizeWhatsApp(template);

    expect(normalized.type).toBe('whatsapp-media-image');
    expect(normalized.header.format).toBe('IMAGE');
    expect(normalized.body.text).toBe('Hi {{1}}');
    expect(normalized.variables).toMatchObject({ 1: 'John' });
  });
});
