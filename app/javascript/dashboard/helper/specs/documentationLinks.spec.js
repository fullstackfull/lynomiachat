import {
  DOC_ARTICLES,
  commerceErrorArticle,
  documentationArticleUrl,
  whatsappErrorArticle,
} from '../documentationLinks';

describe('documentationArticleUrl', () => {
  it('builds an article address from a registry key', () => {
    expect(documentationArticleUrl('https://docs.example.com', 'labels')).toBe(
      'https://docs.example.com/labels'
    );
  });

  it('tolerates a trailing slash on the configured base', () => {
    expect(documentationArticleUrl('https://docs.example.com/', 'labels')).toBe(
      'https://docs.example.com/labels'
    );
  });

  it('returns no link when the installation has no documentation configured', () => {
    expect(documentationArticleUrl('', 'labels')).toBe('');
  });

  it('returns no link for a key the registry does not carry', () => {
    expect(
      documentationArticleUrl('https://docs.example.com', 'notAnArticle')
    ).toBe('');
  });
});

describe('whatsappErrorArticle', () => {
  // The codes the server classifies (custom/app/services/whatsapp/delivery_failure.rb) plus the ones the send
  // and receive paths name. Each has an article under custom/db/documentation/<locale>/whatsapp-errors/.
  it.each([
    [131049, 'whatsapp-error-131049'],
    [131042, 'whatsapp-error-131042'],
    [131053, 'whatsapp-error-131053'],
    [131060, 'whatsapp-error-131060'],
    [190, 'whatsapp-error-190'],
  ])('resolves %i to its own article', (code, slug) => {
    expect(DOC_ARTICLES[whatsappErrorArticle(code)]).toBe(slug);
  });

  it('accepts the code as a string, as a payload may carry it', () => {
    expect(whatsappErrorArticle('131049')).toBe('whatsappError131049');
  });

  it('resolves nothing for a code this installation has no article for', () => {
    expect(whatsappErrorArticle(133010)).toBeUndefined();
  });

  it.each([null, undefined, ''])('resolves nothing for %p', code => {
    expect(whatsappErrorArticle(code)).toBeUndefined();
  });

  it('cannot be tricked into resolving an unrelated registry key', () => {
    expect(whatsappErrorArticle('Window')).toBeUndefined();
  });
});

// Commerce troubleshooting. The thirty entries in Commerce::Error::CODES have five distinct remedies, so the
// registry is grouped by remedy and a code with no answer resolves to nothing rather than to an article that
// does not answer the question (docs/product-refinement/05-documentation-corpus.md).
describe('commerceErrorArticle', () => {
  it('sends a lost authorization to the reconnect article', () => {
    expect(commerceErrorArticle('AUTH_INVALID')).toBe('commerceStoreReconnect');
  });

  it('groups every way a store can fail to answer onto one article', () => {
    const keys = ['STORE_UNAVAILABLE', 'TIMEOUT', 'RATE_LIMITED'].map(
      commerceErrorArticle
    );

    expect(new Set(keys)).toEqual(new Set(['commerceStoreUnreachable']));
  });

  it('groups every permission refusal onto one article', () => {
    const keys = [
      'PERMISSION_DENIED',
      'WRITE_ACCESS_DENIED',
      'PROTECTED_DATA_NOT_APPROVED',
    ].map(commerceErrorArticle);

    expect(new Set(keys)).toEqual(new Set(['commerceStorePermissions']));
  });

  it('sends every order-action outcome to the order-action article', () => {
    const keys = ['ORDER_CHANGED', 'NOT_APPLIED', 'REFUND_DECLINED'].map(
      commerceErrorArticle
    );

    expect(new Set(keys)).toEqual(new Set(['commerceOrderAction']));
  });

  // A code with no answer gets no explanation invented for it; the caller falls back to the overview.
  it('resolves nothing for a code with no article', () => {
    expect(commerceErrorArticle('ENCRYPTION_NOT_CONFIGURED')).toBeUndefined();
    expect(commerceErrorArticle('STORE_ALREADY_CONNECTED')).toBeUndefined();
    expect(commerceErrorArticle(undefined)).toBeUndefined();
  });

  // Every key it can return has to exist in the registry, or the link renders nothing.
  it('only names keys the registry actually holds', () => {
    const codes = [
      'AUTH_INVALID',
      'STORE_UNAVAILABLE',
      'INVALID_STORE_URL',
      'PERMISSION_DENIED',
      'ORDER_CHANGED',
    ];

    codes.forEach(code => {
      expect(DOC_ARTICLES[commerceErrorArticle(code)]).toBeTruthy();
    });
  });
});
