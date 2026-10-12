import {
  calculateScrollTop,
  elementsToKeepVisible,
} from '../scrollTopCalculationHelper';

describe('#calculateScrollTop', () => {
  it('returns calculated value of the scrollTop property', () => {
    class DOMElement {
      constructor(scrollHeight) {
        this.scrollHeight = scrollHeight;
      }
    }
    let count = 3;
    let relevantMessages = [];
    while (count > 0) {
      relevantMessages.push(new DOMElement(100));
      count -= 1;
    }
    expect(calculateScrollTop(1000, 300, relevantMessages)).toEqual(550);
  });
});

// The unread-separator defect this function exists to close: the component used to query `.message--unread`,
// a class nothing in the tree renders, so "scroll to the first unread message" selected an empty NodeList and
// the panel went to the bottom. The bottom is correct for every OTHER case, which is exactly why nobody
// noticed (docs/product-refinement/04-inbox-modernization.md).
describe('#elementsToKeepVisible', () => {
  const panelWith = html => {
    const panel = document.createElement('ul');
    panel.innerHTML = html;
    return panel;
  };

  it('keeps the unread separator AND everything under it, so the separator lands on screen', () => {
    const panel = panelWith(`
      <li id="read-1"></li>
      <li id="separator" data-unread-separator></li>
      <li id="unread-1"></li>
      <li id="unread-2"></li>
    `);

    expect(elementsToKeepVisible(panel).map(element => element.id)).toEqual([
      'separator',
      'unread-1',
      'unread-2',
    ]);
  });

  it('does not reach back above the separator', () => {
    const panel = panelWith(
      '<li id="read-1"></li><li id="separator" data-unread-separator></li>'
    );

    expect(elementsToKeepVisible(panel).map(element => element.id)).toEqual([
      'separator',
    ]);
  });

  // The suggestion sits below the last message, so it is what to look at when there is nothing unread.
  it('falls back to the label suggestion when there is no separator', () => {
    const panel = panelWith(
      '<li id="read-1"></li><li id="suggestion" class="label-suggestion"></li>'
    );

    expect(elementsToKeepVisible(panel).map(element => element.id)).toEqual([
      'suggestion',
    ]);
  });

  // An empty result is not a failure: calculateScrollTop sums nothing and the panel sits at the bottom, which
  // is the right answer when there is nothing in particular to look at.
  it('returns nothing, meaning the bottom, when there is neither', () => {
    expect(elementsToKeepVisible(panelWith('<li id="read-1"></li>'))).toEqual(
      []
    );
  });

  it('prefers the separator over the label suggestion', () => {
    const panel = panelWith(
      '<li id="separator" data-unread-separator></li><li id="suggestion" class="label-suggestion"></li>'
    );

    expect(elementsToKeepVisible(panel)[0].id).toBe('separator');
  });

  it('answers for no panel at all', () => {
    expect(elementsToKeepVisible(null)).toEqual([]);
  });
});
